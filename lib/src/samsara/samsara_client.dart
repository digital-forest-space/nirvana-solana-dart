import 'dart:convert';
import 'dart:typed_data';

import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

import '../models/transaction_price_result.dart';
import '../rpc/solana_rpc_client.dart';
import 'config.dart';
import 'pda.dart';
import 'transaction_builder.dart';

/// Client for fetching data from Samsara protocol (navTokens)
class SamsaraClient {
  final SolanaRpcClient _rpcClient;
  final SamsaraConfig _config;

  SamsaraClient({
    required SolanaRpcClient rpcClient,
    SamsaraConfig? config,
  })  : _rpcClient = rpcClient,
        _config = config ?? SamsaraConfig.mainnet();

  /// Create a SamsaraClient from an existing RPC client.
  factory SamsaraClient.fromRpcClient(SolanaRpcClient rpcClient) {
    return SamsaraClient(rpcClient: rpcClient);
  }

  /// Fetches the user's navToken balances (wallet + staked), base token
  /// balance, deposited prANA, unclaimed rewards, and debt for a market
  /// using a single batched RPC call.
  ///
  /// Returns a map with keys:
  ///   - `'{name}'` (e.g., `'navSOL'`): unstaked navToken in user's wallet
  ///   - `'{name}_deposited'` (e.g., `'navSOL_deposited'`): navToken deposited in
  ///     the Mayflower personal position escrow
  ///   - `'{baseName}'` (e.g., `'SOL'`): user's base token balance
  ///   - `'prANA_deposited'`: prANA deposited in this market's gov account
  ///   - `'rewards_unclaimed'`: unclaimed revenue in base token units
  ///   - `'debt'`: borrowed base token debt
  ///
  /// Balances are in human-readable units (e.g., 1.5 SOL, not lamports).
  /// Returns 0.0 for tokens the user doesn't hold or hasn't staked.
  Future<Map<String, double>> fetchMarketBalances({
    required String userPubkey,
    required NavTokenMarket market,
    int batchSize = 30,
  }) async {
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final samsaraPda = SamsaraPda(
        Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));

    // Derive all addresses locally (pure PDA math, no RPC)
    final navMintKey = Ed25519HDPublicKey.fromBase58(market.navMint);
    final navAta = (await findAssociatedTokenAddress(
        owner: ownerKey, mint: navMintKey)).toBase58();

    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final escrow = (await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey)).toBase58();
    final personalPosition = personalPositionKey.toBase58();

    // Derive Samsara gov account and prANA escrow
    final samsaraMarketKey =
        Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
    final govAccountKey = await samsaraPda.personalGovAccount(
        market: samsaraMarketKey, owner: ownerKey);
    final pranaEscrow = (await samsaraPda.personalGovPranaEscrow(
        govAccount: govAccountKey)).toBase58();
    final govAccount = govAccountKey.toBase58();

    final isNativeSol = market.baseMint == _nativeSolMint;

    // Build account list for batch fetch
    // Order: wallet, navAta, escrow, [baseAta], pranaEscrow, govAccount, personalPosition
    final addresses = <String>[userPubkey, navAta, escrow];
    int? baseAtaIdx;
    if (!isNativeSol) {
      final baseMintKey = Ed25519HDPublicKey.fromBase58(market.baseMint);
      final baseAta = (await findAssociatedTokenAddress(
          owner: ownerKey, mint: baseMintKey)).toBase58();
      baseAtaIdx = addresses.length;
      addresses.add(baseAta);
    }
    final pranaEscrowIdx = addresses.length;
    addresses.add(pranaEscrow);
    final govAccountIdx = addresses.length;
    addresses.add(govAccount);
    final personalPositionIdx = addresses.length;
    addresses.add(personalPosition);

    // Single batched RPC call
    final accounts = await _rpcClient.getMultipleAccounts(
        addresses, batchSize: batchSize);

    // Parse results
    final walletAccount = accounts[0];
    final navAtaAccount = accounts[1];
    final escrowAccount = accounts[2];

    // Base token balance
    double baseBalance;
    if (isNativeSol) {
      final lamports = walletAccount?['lamports'] as int? ?? 0;
      baseBalance = lamports / _pow10(market.baseDecimals);
    } else {
      final baseAtaAccount = accounts[baseAtaIdx!];
      baseBalance = _parseTokenAmountFromAccountData(
          baseAtaAccount, market.baseDecimals);
    }

    return {
      market.name: _parseTokenAmountFromAccountData(
          navAtaAccount, market.navDecimals),
      '${market.name}_deposited': _parseTokenAmountFromAccountData(
          escrowAccount, market.navDecimals),
      market.baseName: baseBalance,
      'prANA_deposited': _parseTokenAmountFromAccountData(
          accounts[pranaEscrowIdx], _pranaDecimals),
      'rewards_unclaimed': await getClaimableRewardsViaSimulation(
          userPubkey: userPubkey, market: market),
      'debt': _parsePersonalPositionDebt(
          accounts[personalPositionIdx], market.baseDecimals),
    };
  }

  /// Fetches balances for all navToken markets in a single batched RPC call.
  ///
  /// Returns a map keyed by market name, where each value is the same
  /// balance map returned by [fetchMarketBalances].
  Future<Map<String, Map<String, double>>> fetchAllMarketBalances({
    required String userPubkey,
    List<NavTokenMarket>? markets,
    int batchSize = 30,
  }) async {
    final allMarkets = markets ?? NavTokenMarket.all.values.toList();
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final samsaraPda = SamsaraPda(
        Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));

    // Derive all addresses locally for all markets
    // Track which addresses belong to which market
    final addresses = <String>[userPubkey]; // wallet always first
    final marketSlices = <_MarketSlice>[];

    for (final market in allMarkets) {
      final startIndex = addresses.length;

      final navMintKey = Ed25519HDPublicKey.fromBase58(market.navMint);
      final navAta = (await findAssociatedTokenAddress(
          owner: ownerKey, mint: navMintKey)).toBase58();
      addresses.add(navAta); // +0

      final marketMetaKey =
          Ed25519HDPublicKey.fromBase58(market.marketMetadata);
      final personalPositionKey = await mayflowerPda.personalPosition(
          marketMeta: marketMetaKey, owner: ownerKey);
      final escrow = (await mayflowerPda.personalPositionEscrow(
          personalPosition: personalPositionKey)).toBase58();
      addresses.add(escrow); // +1

      // Track index offsets from startIndex
      int nextOffset = 2;
      int? baseAtaOffset;
      if (market.baseMint != _nativeSolMint) {
        final baseMintKey = Ed25519HDPublicKey.fromBase58(market.baseMint);
        final baseAta = (await findAssociatedTokenAddress(
            owner: ownerKey, mint: baseMintKey)).toBase58();
        addresses.add(baseAta);
        baseAtaOffset = nextOffset;
        nextOffset++;
      }

      // Derive Samsara gov account and prANA escrow
      final samsaraMarketKey =
          Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
      final govAccountKey = await samsaraPda.personalGovAccount(
          market: samsaraMarketKey, owner: ownerKey);
      final pranaEscrow = (await samsaraPda.personalGovPranaEscrow(
          govAccount: govAccountKey)).toBase58();
      addresses.add(pranaEscrow); // prANA escrow
      final pranaEscrowOffset = nextOffset;
      nextOffset++;

      addresses.add(govAccountKey.toBase58()); // gov account
      final govAccountOffset = nextOffset;
      nextOffset++;

      addresses.add(personalPositionKey.toBase58()); // personal position
      final personalPositionOffset = nextOffset;

      marketSlices.add(_MarketSlice(
        market: market,
        navAtaIndex: startIndex,
        escrowIndex: startIndex + 1,
        baseAtaIndex: baseAtaOffset != null ? startIndex + baseAtaOffset : null,
        pranaEscrowIndex: startIndex + pranaEscrowOffset,
        govAccountIndex: startIndex + govAccountOffset,
        personalPositionIndex: startIndex + personalPositionOffset,
      ));
    }

    // Single RPC call for all markets
    final accounts = await _rpcClient.getMultipleAccounts(
        addresses, batchSize: batchSize);
    final walletAccount = accounts[0];

    // Parse results per market
    final results = <String, Map<String, double>>{};
    for (final slice in marketSlices) {
      final market = slice.market;
      final navAtaAccount = accounts[slice.navAtaIndex];
      final escrowAccount = accounts[slice.escrowIndex];

      double baseBalance;
      if (slice.baseAtaIndex != null) {
        baseBalance = _parseTokenAmountFromAccountData(
            accounts[slice.baseAtaIndex!], market.baseDecimals);
      } else {
        // Native SOL — read lamports from wallet
        final lamports = walletAccount?['lamports'] as int? ?? 0;
        baseBalance = lamports / _pow10(market.baseDecimals);
      }

      results[market.name] = {
        market.name: _parseTokenAmountFromAccountData(
            navAtaAccount, market.navDecimals),
        '${market.name}_deposited': _parseTokenAmountFromAccountData(
            escrowAccount, market.navDecimals),
        market.baseName: baseBalance,
        'prANA_deposited': _parseTokenAmountFromAccountData(
            accounts[slice.pranaEscrowIndex], _pranaDecimals),
        'rewards_unclaimed': await getClaimableRewardsViaSimulation(
            userPubkey: userPubkey, market: market),
        'debt': _parsePersonalPositionDebt(
            accounts[slice.personalPositionIndex], market.baseDecimals),
      };
    }

    return results;
  }

  static const _nativeSolMint =
      'So11111111111111111111111111111111111111112';
  static const _pranaDecimals = 6;

  /// Parses an SPL token amount from raw account data.
  ///
  /// SPL token account layout stores the amount as a u64 at byte offset 64.
  /// Returns 0.0 if the account is null or data is missing/too short.
  static double _parseTokenAmountFromAccountData(
      Map<String, dynamic>? account, int decimals) {
    if (account == null || account['data'] == null) return 0.0;

    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return 0.0;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return 0.0;

    final bytes = base64Decode(base64Data);
    if (bytes.length < 72) return 0.0; // offset 64 + 8 bytes for u64

    // Read u64 little-endian at offset 64
    final byteData = ByteData.sublistView(Uint8List.fromList(bytes), 64, 72);
    final amount = byteData.getUint64(0, Endian.little);

    return amount / _pow10(decimals);
  }

  static double _pow10(int n) {
    double result = 1.0;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }

  /// Parses unclaimed rewards from a GovAccount's raw account data.
  ///
  /// GovAccount layout (435 bytes, Samsara program):
  ///   - Bytes 0-7: discriminator [37, 169, 199, 114, 141, 109, 9, 167]
  ///   - Bytes 8-39: pubkey (market)
  ///   - Bytes 40-71: pubkey (owner)
  ///   - Bytes 72-103: pubkey (unknown)
  ///   - Bytes 104-111: u64 (accumulator, not direct claimable amount)
  ///   - Bytes 112-143: pubkey (unknown)
  ///   - Bytes 144-151: u64 (26 observed — epoch or counter)
  ///   - Bytes 152-434: zeros
  ///
  /// Rewards are not stored as a simple claimable balance. The GovAccount
  /// uses an accumulator model (reward-per-share) that requires the global
  /// market state to compute the actual claimable amount. Returns 0.0
  /// until a simulation-based approach is implemented.
  static double _parseGovAccountRewards(
      Map<String, dynamic>? account, int baseDecimals) {
    // Rewards use an accumulator model that can't be read directly.
    // Use getClaimableRewardsViaSimulation() instead.
    return 0.0;
  }

  /// Gets claimable prANA revenue for a market by simulating a
  /// collectRevPrana transaction and reading the post-state token balance.
  ///
  /// This simulates without signing — the RPC node replaces the blockhash
  /// and skips signature verification.
  ///
  /// Returns 0.0 if the user has no govAccount or no claimable rewards.
  Future<double> getClaimableRewardsViaSimulation({
    required String userPubkey,
    required NavTokenMarket market,
  }) async {
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final samsaraPda = SamsaraPda(
        Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // Derive PDAs
    final samsaraMarketKey =
        Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
    final govAccountKey = await samsaraPda.personalGovAccount(
        market: samsaraMarketKey, owner: ownerKey);
    final cashEscrowKey = await samsaraPda.marketCashEscrow(
        market: samsaraMarketKey);
    final samLogCounterKey = await samsaraPda.logCounter();

    // Cash destination: user's base token ATA (wSOL ATA for SOL markets)
    final baseMintKey = Ed25519HDPublicKey.fromBase58(market.baseMint);
    final cashDstKey = await findAssociatedTokenAddress(
        owner: ownerKey, mint: baseMintKey);
    final cashDst = cashDstKey.toBase58();

    // Build instructions
    final instructions = <Instruction>[];

    // CreateATA idempotent — ensures the destination exists (critical for
    // SOL markets where wSOL ATA may not exist)
    instructions.add(txBuilder.buildCreateAtaIdempotentInstruction(
      payer: userPubkey,
      associatedTokenAccount: cashDst,
      owner: userPubkey,
      mint: market.baseMint,
    ));

    // collectRevPrana — claims revenue into cashDst
    instructions.add(txBuilder.buildCollectRevPranaInstruction(
      userPubkey: userPubkey,
      samsaraMarket: market.samsaraMarket,
      govAccount: govAccountKey.toBase58(),
      cashEscrow: cashEscrowKey.toBase58(),
      cashDst: cashDst,
      baseMint: market.baseMint,
      samLogCounter: samLogCounterKey.toBase58(),
    ));

    // NOTE: No CloseAccount — we want post-state to show the balance

    // Build and serialize the transaction (unsigned, for simulation only)
    final blockhash = await _rpcClient.getLatestBlockhash();
    final message = Message(instructions: instructions);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: ownerKey,
    );

    final serializedMessage = compiledMessage.toByteArray().toList();
    final txBytes = <int>[
      1, // signature count
      ...List.filled(64, 0), // empty signature (simulation skips verification)
      ...serializedMessage,
    ];
    final txBase64 = base64Encode(txBytes);

    // Simulate and read post-state of cashDst
    final simResult = await _rpcClient.simulateTransactionWithAccounts(
      txBase64,
      [cashDst],
    );

    // Check for simulation errors
    if (simResult['err'] != null) {
      return 0.0;
    }

    // Parse post-state balance from the cashDst account
    final simAccounts = simResult['accounts'] as List?;
    if (simAccounts == null || simAccounts.isEmpty) return 0.0;

    final postState = simAccounts[0] as Map<String, dynamic>?;
    if (postState == null || postState['data'] == null) return 0.0;

    final dataArray = postState['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return 0.0;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return 0.0;

    final bytes = base64Decode(base64Data);
    if (bytes.length < 72) return 0.0;

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes), 64, 72);
    final postBalance = byteData.getUint64(0, Endian.little);

    return postBalance / _pow10(market.baseDecimals);
  }

  /// Parses deposited navToken shares from a PersonalPosition's raw account data.
  ///
  /// PersonalPosition layout: u64 at byte offset 104.
  /// Returns 0.0 if the account is null or data is missing/too short.
  static double _parsePersonalPositionShares(
      Map<String, dynamic>? account, int navDecimals) {
    if (account == null || account['data'] == null) return 0.0;

    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return 0.0;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return 0.0;

    final bytes = base64Decode(base64Data);
    if (bytes.length < 112) return 0.0;

    // Read shares u64 at offset 104
    final byteData = ByteData.sublistView(
        Uint8List.fromList(bytes), 104, 112);
    final sharesLamports = byteData.getUint64(0, Endian.little);

    return sharesLamports / _pow10(navDecimals);
  }

  /// Parses borrow debt from a PersonalPosition's raw account data.
  ///
  /// PersonalPosition layout (~120 bytes, Mayflower program):
  ///   - Bytes 0-7: discriminator [40, 172, 123, 89, 170, 15, 56, 141]
  ///   - Bytes 8-39: pubkey (field 1)
  ///   - Bytes 40-71: pubkey (field 2)
  ///   - Bytes 72-103: pubkey (field 3)
  ///   - Bytes 104-111: u64 (deposited navToken shares)
  ///   - Bytes 112-119: u64 (debt in base token lamports)
  static double _parsePersonalPositionDebt(
      Map<String, dynamic>? account, int baseDecimals) {
    if (account == null || account['data'] == null) return 0.0;

    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return 0.0;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return 0.0;

    final bytes = base64Decode(base64Data);
    // Need at least 120 bytes: disc(8) + 3 pubkeys(96) + shares(8) + debt(8)
    if (bytes.length < 120) return 0.0;

    // Read debt u64 at offset 112
    final byteData = ByteData.sublistView(
        Uint8List.fromList(bytes), 112, 120);
    final debtLamports = byteData.getUint64(0, Endian.little);

    return debtLamports / _pow10(baseDecimals);
  }

  /// Dumps all u64 fields from a GovAccount for offset discovery.
  ///
  /// Returns a map of offset → raw u64 value for every 8-byte aligned
  /// position after the known pubkey fields.
  static Map<int, int> dumpGovAccountFields(
      Map<String, dynamic>? account) {
    final fields = <int, int>{};
    if (account == null || account['data'] == null) return fields;

    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return fields;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return fields;

    final bytes = Uint8List.fromList(base64Decode(base64Data));
    if (bytes.length < 72) return fields;

    // GovAccount: disc(8) + market(32) + owner(32) = 72, then u64 fields
    final bd = ByteData.sublistView(bytes);
    for (int offset = 72; offset + 8 <= bytes.length; offset += 8) {
      fields[offset] = bd.getUint64(offset, Endian.little);
    }
    return fields;
  }

  /// Dumps all u64 fields from a PersonalPosition for offset discovery.
  ///
  /// Returns a map of offset → raw u64 value for every 8-byte aligned
  /// position after the known pubkey fields.
  static Map<int, int> dumpPersonalPositionFields(
      Map<String, dynamic>? account) {
    final fields = <int, int>{};
    if (account == null || account['data'] == null) return fields;

    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return fields;

    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return fields;

    final bytes = Uint8List.fromList(base64Decode(base64Data));
    if (bytes.length < 72) return fields;

    // PersonalPosition: disc(8) + marketMeta(32) + owner(32) = 72, then fields
    final bd = ByteData.sublistView(bytes);
    for (int offset = 72; offset + 8 <= bytes.length; offset += 8) {
      fields[offset] = bd.getUint64(offset, Endian.little);
    }
    return fields;
  }

  /// Fetches the floor price for a navToken market from on-chain data.
  ///
  /// Reads the Mayflower Market account and decodes the floor price stored
  /// as a Rust Decimal at byte offset 104 (same encoding as Nirvana's
  /// PriceCurve2 account).
  ///
  /// Returns the floor price in base token units (e.g., SOL per navSOL).
  Future<double> fetchFloorPrice(NavTokenMarket market) async {
    final accountInfo =
        await _rpcClient.getAccountInfo(market.mayflowerMarket);
    return _parseFloorPriceFromAccount(accountInfo, market);
  }

  /// Fetches floor prices for multiple markets in a single batched RPC call.
  ///
  /// Returns a map of market name to floor price in base token units.
  Future<Map<String, double>> fetchAllFloorPrices({
    required List<NavTokenMarket> markets,
    int batchSize = 30,
  }) async {
    final addresses = markets.map((m) => m.mayflowerMarket).toList();
    final accounts = await _rpcClient.getMultipleAccounts(
        addresses, batchSize: batchSize);

    final results = <String, double>{};
    for (var i = 0; i < markets.length; i++) {
      results[markets[i].name] =
          _parseFloorPriceFromAccount(accounts[i], markets[i]);
    }
    return results;
  }

  /// Fetches the user's borrow capacity for a navToken market.
  ///
  /// Reads the on-chain PersonalPosition (deposited navToken shares + current
  /// debt) and the market's floor price to compute the borrow limit.
  ///
  /// Max borrow = deposited navTokens * floor price (100% LTV against floor).
  ///
  /// Returns `{'deposited': ..., 'debt': ..., 'limit': ..., 'available': ...}`
  /// in base token units (e.g., SOL). Returns null if the user has no position.
  Future<Map<String, double>?> fetchBorrowCapacity({
    required String userPubkey,
    required NavTokenMarket market,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));

    // Derive personal position PDA
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);

    // Batch-fetch personal position + mayflower market in one RPC call
    final accounts = await _rpcClient.getMultipleAccounts(
        [personalPositionKey.toBase58(), market.mayflowerMarket]);

    final positionAccount = accounts[0];
    if (positionAccount == null || positionAccount['data'] == null) {
      return null;
    }

    // Parse deposited shares (u64 at offset 104) and debt (u64 at offset 112)
    final deposited = _parsePersonalPositionShares(
        positionAccount, market.navDecimals);
    final debt = _parsePersonalPositionDebt(
        positionAccount, market.baseDecimals);

    // Parse floor price from market account
    final floorPrice = _parseFloorPriceFromAccount(accounts[1], market);

    final limit = deposited * floorPrice;
    final available = limit > debt ? limit - debt : 0.0;

    return {
      'deposited': deposited,
      'debt': debt,
      'limit': limit,
      'available': available,
    };
  }

  /// Estimates the borrow capacity from a buy, without making any RPC calls.
  ///
  /// Buy gives navTokens at market price, borrow limit uses floor price:
  ///   navTokens = inputBaseAmount / marketPrice
  ///   maxBorrow = navTokens * floorPrice
  ///
  /// All amounts are in human-readable units (e.g., 1.5 SOL, not lamports).
  static Map<String, double> estimateBorrowCapacityAfterBuy({
    required double inputBaseAmount,
    required double marketPrice,
    required double floorPrice,
  }) {
    final estimatedNavTokens = inputBaseAmount / marketPrice;
    final borrowLimit = estimatedNavTokens * floorPrice;

    return {
      'estimatedNavTokens': estimatedNavTokens,
      'borrowLimit': borrowLimit,
    };
  }

  /// Discovers all navToken markets from on-chain Mayflower program data.
  ///
  /// Algorithm (3 RPC calls):
  /// 1. `getProgramAccounts` for all MarketLinear accounts (304 bytes)
  /// 2. `getMultipleAccounts` to batch-fetch MarketMeta accounts (488 bytes)
  /// 3. `getMultipleAccounts` to batch-fetch SPL Mint accounts for decimals
  ///
  /// PDAs (samsaraMarket, authorityPda) are derived locally with no RPC.
  /// Names are resolved from [NavTokenMarket.wellKnownMints], falling back to
  /// truncated pubkey for unknown mints.
  Future<List<NavTokenMarket>> discoverMarkets({int batchSize = 30}) async {
    final samsaraPda =
        SamsaraPda(Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));
    final mayflowerPda =
        MayflowerPda(Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));

    // 1. Fetch all MarketLinear accounts (304 bytes)
    final marketLinearAccounts = await _rpcClient.getProgramAccounts(
      _config.mayflowerProgramId,
      dataSize: 304,
    );

    if (marketLinearAccounts.isEmpty) return [];

    // Extract marketMetadata pubkey (offset 8-40) from each MarketLinear
    final metadataAddresses = <String>[];
    final mayflowerMarketPubkeys = <String>[];
    for (final account in marketLinearAccounts) {
      final bytes = _decodeAccountData(account['account']);
      if (bytes.length < 40) continue;
      metadataAddresses.add(_bytesToBase58(bytes.sublist(8, 40)));
      mayflowerMarketPubkeys.add(account['pubkey'] as String);
    }

    // 2. Batch-fetch all MarketMeta accounts (488 bytes)
    final metaAccounts = await _rpcClient.getMultipleAccounts(
        metadataAddresses,
        batchSize: batchSize);

    // Parse MarketMeta fields and collect unique mints
    final mintSet = <String>{};
    final parsedMetas = <_ParsedMarketMeta>[];

    for (var i = 0; i < metaAccounts.length; i++) {
      final metaAccount = metaAccounts[i];
      if (metaAccount == null) continue;

      final bytes = _decodeAccountData(metaAccount);
      if (bytes.length < 296) continue;

      final baseMint = _bytesToBase58(bytes.sublist(8, 40));
      final navMint = _bytesToBase58(bytes.sublist(40, 72));
      final marketGroup = _bytesToBase58(bytes.sublist(104, 136));
      final baseVault = _bytesToBase58(bytes.sublist(200, 232));
      final navVault = _bytesToBase58(bytes.sublist(232, 264));
      final feeVault = _bytesToBase58(bytes.sublist(264, 296));

      mintSet.add(baseMint);
      mintSet.add(navMint);

      parsedMetas.add(_ParsedMarketMeta(
        mayflowerMarket: mayflowerMarketPubkeys[i],
        marketMetadata: metadataAddresses[i],
        baseMint: baseMint,
        navMint: navMint,
        marketGroup: marketGroup,
        baseVault: baseVault,
        navVault: navVault,
        feeVault: feeVault,
      ));
    }

    // 3. Batch-fetch SPL Mint accounts for decimals
    final mintList = mintSet.toList();
    final mintAccounts = await _rpcClient.getMultipleAccounts(mintList,
        batchSize: batchSize);
    final mintDecimals = <String, int>{};
    for (var i = 0; i < mintList.length; i++) {
      mintDecimals[mintList[i]] = _parseMintDecimals(mintAccounts[i]);
    }

    // 4. Derive PDAs and build NavTokenMarket objects
    final markets = <NavTokenMarket>[];
    for (final meta in parsedMetas) {
      final metaKey = Ed25519HDPublicKey.fromBase58(meta.marketMetadata);
      final samsaraMarketKey = await samsaraPda.market(marketMeta: metaKey);
      final authorityPdaKey =
          await mayflowerPda.liqVaultMain(marketMeta: metaKey);

      // Resolve names from well-known mints
      final navInfo = NavTokenMarket.wellKnownMints[meta.navMint];
      final baseInfo = NavTokenMarket.wellKnownMints[meta.baseMint];
      final name = navInfo?.symbol ?? 'nav_${meta.navMint.substring(0, 8)}';
      final baseName =
          baseInfo?.symbol ?? meta.baseMint.substring(0, 8);

      markets.add(NavTokenMarket(
        name: name,
        baseName: baseName,
        baseMint: meta.baseMint,
        navMint: meta.navMint,
        samsaraMarket: samsaraMarketKey.toBase58(),
        mayflowerMarket: meta.mayflowerMarket,
        marketMetadata: meta.marketMetadata,
        marketGroup: meta.marketGroup,
        marketSolVault: meta.baseVault,
        marketNavVault: meta.navVault,
        feeVault: meta.feeVault,
        authorityPda: authorityPdaKey.toBase58(),
        baseDecimals: mintDecimals[meta.baseMint] ?? 9,
        navDecimals: mintDecimals[meta.navMint] ?? 9,
      ));
    }

    return markets;
  }

  /// Fetches the on-chain fee schedule for a single market.
  ///
  /// Reads the MarketGroup account (154 bytes, owned by Mayflower) and parses
  /// the fee fields stored as u32 little-endian values in micro-basis-points.
  ///
  /// Returns null if the MarketGroup account cannot be read.
  Future<MarketFees?> fetchMarketFees(NavTokenMarket market) async {
    final info = await _rpcClient.getAccountInfo(market.marketGroup);
    if (info.isEmpty) return null;
    final bytes = _decodeAccountData(info);
    return _parseMarketGroupFees(bytes, market.name);
  }

  /// Fetches fees for all provided markets in a single batched RPC call.
  ///
  /// Returns a map from market name to [MarketFees]. Markets whose
  /// MarketGroup account could not be read are omitted from the result.
  Future<Map<String, MarketFees>> fetchAllMarketFees(
    List<NavTokenMarket> markets, {
    int batchSize = 100,
  }) async {
    final addresses = markets.map((m) => m.marketGroup).toList();
    final accounts =
        await _rpcClient.getMultipleAccounts(addresses, batchSize: batchSize);

    final result = <String, MarketFees>{};
    for (var i = 0; i < markets.length; i++) {
      final account = accounts[i];
      if (account == null) continue;
      final bytes = _decodeAccountData(account);
      final fees = _parseMarketGroupFees(bytes, markets[i].name);
      if (fees != null) {
        result[markets[i].name] = fees;
      }
    }
    return result;
  }

  /// Parses fee fields from a MarketGroup account's raw bytes.
  ///
  /// MarketGroup layout (154 bytes):
  ///   0-7:     discriminator
  ///   8-103:   3 × Pubkey (tenant, samsaraMarket, unknown)
  ///   104-105: u16 (unknown)
  ///   106-109: u32 buy fee (ubps)
  ///   110-113: u32 sell fee (ubps)
  ///   114-117: u32 borrow fee (ubps)
  ///   118-121: u32 exercise option fee (ubps)
  ///   122-153: reserved
  static MarketFees? _parseMarketGroupFees(Uint8List bytes, String name) {
    if (bytes.length < 122) return null;
    final bd = ByteData.sublistView(bytes);
    return MarketFees(
      marketName: name,
      buyFeeUbps: bd.getUint32(106, Endian.little),
      sellFeeUbps: bd.getUint32(110, Endian.little),
      borrowFeeUbps: bd.getUint32(114, Endian.little),
      exerciseOptionFeeUbps: bd.getUint32(118, Endian.little),
    );
  }

  /// Fetches all governance parameters for a single market.
  ///
  /// Reads the SamsaraMarket account (876 bytes) which contains 7 governance
  /// parameter blocks (fees + floor-raise settings), each 32 bytes at
  /// offset 152 with 32-byte stride. Also reads the MarketGroup account for
  /// the exercise option fee.
  ///
  /// Returns null if the SamsaraMarket account cannot be read.
  Future<MarketGovernance?> fetchMarketGovernance(
      NavTokenMarket market) async {
    final accounts = await _rpcClient.getMultipleAccounts(
        [market.samsaraMarket, market.marketGroup]);

    final samsaraBytes =
        accounts[0] != null ? _decodeAccountData(accounts[0]) : null;
    if (samsaraBytes == null || samsaraBytes.length < 376) return null;

    // Exercise option fee from MarketGroup (offset 118, u32)
    var exerciseUbps = 0;
    if (accounts[1] != null) {
      final mgBytes = _decodeAccountData(accounts[1]);
      if (mgBytes.length >= 122) {
        exerciseUbps = ByteData.sublistView(mgBytes)
            .getUint32(118, Endian.little);
      }
    }

    return _parseSamsaraMarketGovernance(
        samsaraBytes, market.name, exerciseUbps);
  }

  /// Fetches governance parameters for all provided markets in a single batch.
  ///
  /// Returns a map from market name to [MarketGovernance]. Markets whose
  /// accounts could not be read are omitted.
  Future<Map<String, MarketGovernance>> fetchAllMarketGovernance(
    List<NavTokenMarket> markets, {
    int batchSize = 100,
  }) async {
    // Interleave SamsaraMarket + MarketGroup addresses for batch fetch
    final addresses = <String>[];
    for (final m in markets) {
      addresses.add(m.samsaraMarket);
      addresses.add(m.marketGroup);
    }

    final accounts =
        await _rpcClient.getMultipleAccounts(addresses, batchSize: batchSize);

    final result = <String, MarketGovernance>{};
    for (var i = 0; i < markets.length; i++) {
      final samsaraAccount = accounts[i * 2];
      final mgAccount = accounts[i * 2 + 1];

      if (samsaraAccount == null) continue;
      final samsaraBytes = _decodeAccountData(samsaraAccount);
      if (samsaraBytes.length < 376) continue;

      var exerciseUbps = 0;
      if (mgAccount != null) {
        final mgBytes = _decodeAccountData(mgAccount);
        if (mgBytes.length >= 122) {
          exerciseUbps = ByteData.sublistView(mgBytes)
              .getUint32(118, Endian.little);
        }
      }

      final gov = _parseSamsaraMarketGovernance(
          samsaraBytes, markets[i].name, exerciseUbps);
      if (gov != null) {
        result[markets[i].name] = gov;
      }
    }
    return result;
  }

  /// Parses a single governance parameter block (32 bytes) from account data.
  static GovernanceParam _parseGovParam(ByteData bd, int offset) {
    return GovernanceParam(
      previous: bd.getUint32(offset, Endian.little),
      current: bd.getUint32(offset + 4, Endian.little),
      step: bd.getUint32(offset + 8, Endian.little),
      maximum: bd.getUint32(offset + 12, Endian.little),
      minimum: bd.getUint32(offset + 16, Endian.little),
    );
  }

  /// Parses all 7 governance parameter blocks from a SamsaraMarket account.
  ///
  /// SamsaraMarket governance layout (32-byte blocks):
  ///   offset 152: Buy Fee
  ///   offset 184: Sell Fee
  ///   offset 216: Borrow Fee
  ///   offset 248: Floor Raise Cooldown (seconds)
  ///   offset 280: Floor Raise Buffer (ubps)
  ///   offset 312: Floor Investment (ubps)
  ///   offset 344: Floor Raise Increase Ratio (ubps)
  static MarketGovernance? _parseSamsaraMarketGovernance(
      Uint8List bytes, String name, int exerciseOptionFeeUbps) {
    if (bytes.length < 376) return null;
    final bd = ByteData.sublistView(bytes);
    return MarketGovernance(
      marketName: name,
      buyFee: _parseGovParam(bd, 152),
      sellFee: _parseGovParam(bd, 184),
      borrowFee: _parseGovParam(bd, 216),
      floorRaiseCooldown: _parseGovParam(bd, 248),
      floorRaiseBuffer: _parseGovParam(bd, 280),
      floorInvestment: _parseGovParam(bd, 312),
      floorRaiseIncrease: _parseGovParam(bd, 344),
      exerciseOptionFeeUbps: exerciseOptionFeeUbps,
    );
  }

  /// Parses SPL Mint decimals (u8 at byte offset 44).
  static int _parseMintDecimals(Map<String, dynamic>? account) {
    if (account == null || account['data'] == null) return 9;
    final dataArray = account['data'] as List<dynamic>?;
    if (dataArray == null || dataArray.isEmpty) return 9;
    final base64Data = dataArray[0] as String?;
    if (base64Data == null || base64Data.isEmpty) return 9;
    final bytes = base64Decode(base64Data);
    if (bytes.length < 45) return 9;
    return bytes[44];
  }

  /// Converts raw bytes to a base58-encoded pubkey string.
  static String _bytesToBase58(Uint8List bytes) {
    return Ed25519HDPublicKey(bytes.toList()).toBase58();
  }

  /// Decodes base64 account data from an RPC response.
  static Uint8List _decodeAccountData(dynamic accountOrInfo) {
    if (accountOrInfo is Map<String, dynamic>) {
      final data = accountOrInfo['data'];
      String? base64Data;
      if (data is List) {
        base64Data = data[0] as String?;
      } else if (data is Map) {
        base64Data = data['data']?[0] as String?;
      }
      if (base64Data == null || base64Data.isEmpty) return Uint8List(0);
      return Uint8List.fromList(base64Decode(base64Data));
    }
    return Uint8List(0);
  }

  /// Parses floor price from a Mayflower Market account's raw data.
  static double _parseFloorPriceFromAccount(
      Map<String, dynamic>? accountInfo, NavTokenMarket market) {
    if (accountInfo == null ||
        accountInfo.isEmpty ||
        accountInfo['data'] == null) {
      throw Exception(
          'Mayflower Market account not found: ${market.mayflowerMarket}');
    }

    final base64Data = accountInfo['data']?[0] as String?;
    if (base64Data == null || base64Data.isEmpty) {
      throw Exception('Mayflower Market account data is empty');
    }

    final bytes = Uint8List.fromList(base64Decode(base64Data));
    const floorPriceOffset = 104;
    const decimalLength = 16;

    if (bytes.length < floorPriceOffset + decimalLength) {
      throw Exception(
          'Mayflower Market data too short: ${bytes.length} bytes, '
          'need at least ${floorPriceOffset + decimalLength}');
    }

    final floorPrice = _decodeRustDecimal(
      bytes.sublist(floorPriceOffset, floorPriceOffset + decimalLength),
    );

    if (floorPrice <= 0 || floorPrice > 1000) {
      throw Exception(
          '${market.name} floor price out of range: $floorPrice');
    }

    return floorPrice;
  }

  /// Decodes a 16-byte Rust Decimal (borsh-serialized).
  ///
  /// Format: [flags(4), mantissa(12)]
  ///   - flags byte 2 = scale (number of decimal places)
  ///   - bytes 4-15 = 96-bit unsigned integer (LE)
  ///   - value = mantissa / 10^scale
  ///
  /// Same encoding used by Nirvana's PriceCurve2 account.
  static double _decodeRustDecimal(List<int> bytes) {
    final int scale = bytes[2];
    if (scale < 1 || scale > 28) return 0.0;

    BigInt rawValue = BigInt.zero;
    for (int i = 4; i < 16; i++) {
      rawValue |= BigInt.from(bytes[i]) << (8 * (i - 4));
    }

    if (rawValue == BigInt.zero) return 0.0;

    final BigInt divisor = BigInt.from(10).pow(scale);
    return rawValue.toDouble() / divisor.toDouble();
  }

  /// Fetches the latest navToken price by parsing a recent buy/sell transaction.
  ///
  /// Returns price in base token units per navToken (e.g., SOL per navSOL).
  ///
  /// Uses the same paging pattern as NirvanaClient.fetchLatestAnaPrice:
  /// - [afterSignature]: skip signatures newer than this (for caching)
  /// - [beforeSignature]: skip signatures older than this (for paging)
  /// - [pageSize]: number of signatures to fetch per page
  /// - [initialDelayMs]: delay between RPC calls
  /// - [maxDelayMs]: max delay after backoff
  /// - [maxRetries]: max retries per transaction on 429 errors
  Future<TransactionPriceResult> fetchLatestNavTokenPrice(
    NavTokenMarket market, {
    String? afterSignature,
    String? beforeSignature,
    int pageSize = 20,
    int initialDelayMs = 500,
    int maxDelayMs = 10000,
    int maxRetries = 5,
  }) async {
    try {
      // Query signatures for the market account (market-specific)
      final signatures = await _rpcClient.getSignaturesForAddress(
        market.mayflowerMarket,
        limit: pageSize,
        until: afterSignature,
        before: beforeSignature,
      );

      if (signatures.isEmpty) {
        if (afterSignature != null) {
          return TransactionPriceResult.reachedAfterLimit();
        }
        return TransactionPriceResult.error(
            'No transactions found for ${market.name} market');
      }

      int txIndex = 0;
      int txChecked = 0;
      int retryCount = 0;
      int currentDelayMs = initialDelayMs;
      String? lastCheckedSig;
      final newestSig = signatures.first;

      while (txIndex < signatures.length && txChecked < pageSize) {
        final sig = signatures[txIndex];
        lastCheckedSig = sig;

        try {
          if (txChecked > 0 && currentDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: currentDelayMs));
          }

          final result = await _parseNavTokenTransactionPrice(sig, market);
          return TransactionPriceResult.found(
            price: result.price!,
            signature: sig,
            newestCheckedSignature: newestSig,
            fee: result.fee,
            currency: result.currency,
          );
        } catch (e) {
          final errorMsg = e.toString();

          if (errorMsg.contains('429') && retryCount < maxRetries) {
            retryCount++;
            currentDelayMs =
                (currentDelayMs * 2).clamp(initialDelayMs, maxDelayMs);
            await Future.delayed(Duration(milliseconds: currentDelayMs));
            continue;
          }

          retryCount = 0;
          currentDelayMs = initialDelayMs;
          txIndex++;
          txChecked++;
        }
      }

      if (txIndex >= signatures.length && afterSignature != null) {
        return TransactionPriceResult.reachedAfterLimit();
      }

      if (lastCheckedSig != null) {
        return TransactionPriceResult.limitReached(
          signature: lastCheckedSig,
          newestCheckedSignature: newestSig,
        );
      }

      return TransactionPriceResult.error(
          'No recent ${market.name} buy/sell transactions found');
    } catch (e) {
      return TransactionPriceResult.error(e.toString());
    }
  }

  /// Fetches the latest navToken price with automatic paging.
  Future<TransactionPriceResult> fetchLatestNavTokenPriceWithPaging(
    NavTokenMarket market, {
    String? afterSignature,
    int maxPages = 10,
    int pageSize = 20,
    int initialDelayMs = 500,
    int maxDelayMs = 10000,
    int maxRetries = 5,
  }) async {
    String? beforeSignature;
    String? lastSignature;
    String? newestCheckedSig;

    for (var page = 1; page <= maxPages; page++) {
      final result = await fetchLatestNavTokenPrice(
        market,
        afterSignature: afterSignature,
        beforeSignature: beforeSignature,
        pageSize: pageSize,
        initialDelayMs: initialDelayMs,
        maxDelayMs: maxDelayMs,
        maxRetries: maxRetries,
      );

      if (page == 1 && result.newestCheckedSignature != null) {
        newestCheckedSig = result.newestCheckedSignature;
      }

      if (result.status != PriceResultStatus.limitReached) {
        return result;
      }

      lastSignature = result.signature;
      beforeSignature = result.signature;
      afterSignature = null;
    }

    return TransactionPriceResult.limitReached(
      signature: lastSignature!,
      newestCheckedSignature: newestCheckedSig!,
    );
  }

  /// Parses a Mayflower transaction to extract navToken price.
  ///
  /// For buy: price = base spent / navToken received
  /// For sell: price = base received / navToken spent
  ///
  /// navToken amount is determined by net balance change (works because
  /// navTokens are minted/burned). Base token amount uses the vault's
  /// balance change, which works for both native-SOL and non-native markets.
  Future<TransactionPriceResult> _parseNavTokenTransactionPrice(
    String signature,
    NavTokenMarket market,
  ) async {
    final txData = await _rpcClient.getTransaction(signature);

    final meta = txData['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw Exception('Transaction metadata not found');
    }

    if (meta['err'] != null) {
      throw Exception('Transaction failed');
    }

    final preTokenBalances = meta['preTokenBalances'] as List? ?? [];
    final postTokenBalances = meta['postTokenBalances'] as List? ?? [];

    // navToken: net change across all accounts (non-zero because mint/burn)
    final navChange =
        _getTokenBalanceChangeByOwner(preTokenBalances, postTokenBalances, market.navMint, null);

    // Base token: use the vault's change.
    // For non-native tokens (cbBTC, ZEC), the net change across ALL accounts
    // is zero (tokens just move between accounts). We must look at the vault
    // specifically. The vault's owner is the market metadata PDA.
    final baseChange = _getTokenBalanceChangeByOwner(
        preTokenBalances, postTokenBalances, market.baseMint,
        market.marketMetadata);

    if (navChange == 0.0 || baseChange == 0.0) {
      throw Exception('Not a ${market.name} buy/sell transaction');
    }

    // price = abs(base vault change) / abs(nav change)
    // Buy: vault gains base, nav minted → both positive
    // Sell: vault loses base, nav burned → both negative
    final price = baseChange.abs() / navChange.abs();

    return TransactionPriceResult.found(
      price: price,
      signature: signature,
      currency: market.baseName,
    );
  }

  /// Gets the balance change for a specific mint filtered by token account owner.
  ///
  /// Used for base tokens where the net change across all accounts is zero
  /// (e.g., cbBTC). By filtering to the vault owner (market metadata PDA),
  /// we get the actual base amount involved in the trade.
  double _getTokenBalanceChangeByOwner(
    List<dynamic> preTokenBalances,
    List<dynamic> postTokenBalances,
    String mint,
    String? owner,
  ) {
    final preAmounts = <int, double>{};
    final postAmounts = <int, double>{};
    final allIndices = <int>{};

    for (final balance in preTokenBalances) {
      if (balance['mint'] != mint) continue;
      if (owner != null && balance['owner'] != owner) continue;
      final index = balance['accountIndex'] as int;
      final amount = double.parse(
          balance['uiTokenAmount']?['uiAmountString'] ?? '0');
      preAmounts[index] = amount;
      allIndices.add(index);
    }

    for (final balance in postTokenBalances) {
      if (balance['mint'] != mint) continue;
      if (owner != null && balance['owner'] != owner) continue;
      final index = balance['accountIndex'] as int;
      final amount = double.parse(
          balance['uiTokenAmount']?['uiAmountString'] ?? '0');
      postAmounts[index] = amount;
      allIndices.add(index);
    }

    double totalChange = 0.0;
    for (final index in allIndices) {
      final pre = preAmounts[index] ?? 0.0;
      final post = postAmounts[index] ?? 0.0;
      totalChange += (post - pre);
    }

    return totalChange;
  }

  /// Build an unsigned deposit prANA transaction for a Samsara market.
  ///
  /// Automatically initializes the govAccount if it doesn't exist yet.
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedDepositPranaTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required double pranaAmount,
    required String recentBlockhash,
  }) async {
    final pda = SamsaraPda(
        Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive PDAs
    final samsaraMarketKey =
        Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final govAccount = await pda.personalGovAccount(
        market: samsaraMarketKey, owner: ownerKey);
    final pranaEscrow =
        await pda.personalGovPranaEscrow(govAccount: govAccount);
    final logCounter = await pda.logCounter();

    // 2. Check if govAccount exists on-chain
    final govAccountInfo =
        await _rpcClient.getAccountInfo(govAccount.toBase58());
    final needsInit =
        govAccountInfo.isEmpty || govAccountInfo['data'] == null;

    // 3. Find user's prANA ATA
    final pranaSrc = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, _config.pranaMint);

    // 4. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(200000),
      txBuilder.buildSetComputeUnitPriceInstruction(50000),
    ];

    if (needsInit) {
      instructions.add(txBuilder.buildInitGovAccountInstruction(
        payerPubkey: userPubkey,
        ownerPubkey: userPubkey,
        market: market,
        govAccount: govAccount.toBase58(),
        pranaEscrow: pranaEscrow.toBase58(),
        logCounter: logCounter.toBase58(),
      ));
    }

    final pranaLamports = (pranaAmount * 1e6).round(); // prANA has 6 decimals
    instructions.add(txBuilder.buildDepositPranaInstruction(
      depositorPubkey: userPubkey,
      market: market,
      govAccount: govAccount.toBase58(),
      pranaSrc: pranaSrc,
      pranaEscrow: pranaEscrow.toBase58(),
      logCounter: logCounter.toBase58(),
      amount: pranaLamports,
    ));

    // 5. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned buy navToken transaction for a Mayflower market.
  ///
  /// Wraps SOL into wSOL, buys navToken via Mayflower, then closes the wSOL
  /// account to return dust. Automatically initializes the personal position
  /// if the user hasn't interacted with this market before.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedBuyNavSolTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int inputLamports,
    required String recentBlockhash,
    int minOutputLamports = 0,
    int computeUnitLimit = 400000,
    int computeUnitPrice = 280000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user ATAs
    final userWsolAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);
    final userNavAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.navMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final userSharesKey = await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey);
    final logAccount = (await mayflowerPda.logAccount()).toBase58();

    final personalPosition = personalPositionKey.toBase58();
    final userShares = userSharesKey.toBase58();

    // 3. Check if personal position exists on-chain
    final positionInfo =
        await _rpcClient.getAccountInfo(personalPosition);
    final needsInit =
        positionInfo.isEmpty || positionInfo['data'] == null;

    // 4. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create wSOL ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userWsolAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),

      // Transfer SOL to wSOL ATA
      txBuilder.buildTransferInstruction(
        from: userPubkey,
        to: userWsolAta,
        lamports: inputLamports,
      ),

      // Sync native (wrap SOL)
      txBuilder.buildSyncNativeInstruction(userWsolAta),

      // Create navToken ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userNavAta,
        owner: userPubkey,
        mint: market.navMint,
      ),
    ];

    // Init personal position if first-time user
    if (needsInit) {
      instructions.add(txBuilder.buildInitPositionInstruction(
        userPubkey: userPubkey,
        personalPosition: personalPosition,
        userShares: userShares,
        logAccount: logAccount,
        market: market,
      ));
    }

    // Mayflower buy navToken
    instructions.add(txBuilder.buildBuyNavSolInstruction(
      userPubkey: userPubkey,
      userWsolAccount: userWsolAta,
      userNavSolAccount: userNavAta,
      personalPosition: personalPosition,
      userShares: userShares,
      logAccount: logAccount,
      market: market,
      inputLamports: inputLamports,
      minOutputLamports: minOutputLamports,
    ));

    // Close wSOL account (return dust to user)
    instructions.add(txBuilder.buildCloseAccountInstruction(
      account: userWsolAta,
      destination: userPubkey,
      owner: userPubkey,
    ));

    // 5. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned sell navToken transaction for a Mayflower market.
  ///
  /// Sells navToken for base token (SOL). Creates a temporary wSOL account
  /// to receive the output, then closes it to unwrap back to native SOL.
  /// The user must already have a personal position (i.e., have bought before).
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedSellNavSolTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int inputNavLamports,
    required String recentBlockhash,
    int minOutputLamports = 0,
    int computeUnitLimit = 400000,
    int computeUnitPrice = 280000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user ATAs
    final userWsolAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);
    final userNavAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.navMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final userSharesKey = await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey);
    final logAccount = (await mayflowerPda.logAccount()).toBase58();

    final personalPosition = personalPositionKey.toBase58();
    final userShares = userSharesKey.toBase58();

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create wSOL ATA (idempotent) - for receiving sell output
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userWsolAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),

      // Transfer 0 lamports to wSOL ATA (ensure account exists)
      txBuilder.buildTransferInstruction(
        from: userPubkey,
        to: userWsolAta,
        lamports: 0,
      ),

      // Sync native (activate wSOL)
      txBuilder.buildSyncNativeInstruction(userWsolAta),

      // Create navToken ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userNavAta,
        owner: userPubkey,
        mint: market.navMint,
      ),

      // Mayflower sell navToken
      txBuilder.buildSellNavSolInstruction(
        userPubkey: userPubkey,
        userWsolAccount: userWsolAta,
        userNavSolAccount: userNavAta,
        personalPosition: personalPosition,
        userShares: userShares,
        logAccount: logAccount,
        market: market,
        inputNavLamports: inputNavLamports,
        minOutputLamports: minOutputLamports,
      ),

      // Close wSOL account (unwrap to native SOL)
      txBuilder.buildCloseAccountInstruction(
        account: userWsolAta,
        destination: userPubkey,
        owner: userPubkey,
      ),
    ];

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned borrow transaction for a Mayflower market.
  ///
  /// Borrows the market's base token (e.g., SOL for navSOL) against the user's
  /// deposited prANA. The user must already have a personal position for this
  /// market (i.e., have bought navTokens before).
  ///
  /// For native SOL markets, wraps/unwraps via a temporary wSOL account.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedBorrowTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int borrowLamports,
    required String recentBlockhash,
    int computeUnitLimit = 200000,
    int computeUnitPrice = 500000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user's base token ATA
    final userBaseAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final personalPosition = personalPositionKey.toBase58();
    final logAccount = (await mayflowerPda.logAccount()).toBase58();

    final isNativeSol = market.baseMint == _nativeSolMint;

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create base token ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userBaseAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),
    ];

    if (isNativeSol) {
      // Transfer 0 lamports + sync native (ensure wSOL account is active)
      instructions.addAll([
        txBuilder.buildTransferInstruction(
          from: userPubkey,
          to: userBaseAta,
          lamports: 0,
        ),
        txBuilder.buildSyncNativeInstruction(userBaseAta),
      ]);
    }

    // Mayflower borrow base token
    instructions.add(txBuilder.buildBorrowInstruction(
      userPubkey: userPubkey,
      userBaseTokenAccount: userBaseAta,
      personalPosition: personalPosition,
      logAccount: logAccount,
      market: market,
      borrowLamports: borrowLamports,
    ));

    if (isNativeSol) {
      // Close wSOL account (unwrap to native SOL)
      instructions.add(txBuilder.buildCloseAccountInstruction(
        account: userBaseAta,
        destination: userPubkey,
        owner: userPubkey,
      ));
    }

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }
  /// Build an unsigned atomic buy + borrow transaction for a Mayflower market.
  ///
  /// Combines buying navToken and borrowing base token into a single
  /// transaction requiring only one user signature. The buy executes first
  /// (minting + auto-depositing navToken as collateral), then the borrow
  /// draws against that collateral.
  ///
  /// For native SOL markets, a single wSOL ATA serves both operations:
  /// buy consumes SOL from it, borrow deposits borrowed SOL back into it,
  /// and a final CloseAccount unwraps everything to native SOL.
  ///
  /// Automatically initializes the personal position if the user hasn't
  /// interacted with this market before.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedBuyAndBorrowTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int inputLamports,
    required int borrowLamports,
    required String recentBlockhash,
    int minOutputLamports = 0,
    int computeUnitLimit = 600000,
    int computeUnitPrice = 500000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user ATAs (base token ATA shared between buy and borrow)
    final userBaseAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);
    final userNavAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.navMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final userSharesKey = await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey);
    final logAccount = (await mayflowerPda.logAccount()).toBase58();

    final personalPosition = personalPositionKey.toBase58();
    final userShares = userSharesKey.toBase58();

    // 3. Check if personal position exists on-chain
    final positionInfo =
        await _rpcClient.getAccountInfo(personalPosition);
    final needsInit =
        positionInfo.isEmpty || positionInfo['data'] == null;

    final isNativeSol = market.baseMint == _nativeSolMint;

    // 4. Build combined instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create base token ATA (idempotent) — shared between buy and borrow
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userBaseAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),
    ];

    if (isNativeSol) {
      // Wrap SOL for buy input
      instructions.addAll([
        txBuilder.buildTransferInstruction(
          from: userPubkey,
          to: userBaseAta,
          lamports: inputLamports,
        ),
        txBuilder.buildSyncNativeInstruction(userBaseAta),
      ]);
    }

    // Create navToken ATA (idempotent)
    instructions.add(txBuilder.buildCreateAtaIdempotentInstruction(
      payer: userPubkey,
      associatedTokenAccount: userNavAta,
      owner: userPubkey,
      mint: market.navMint,
    ));

    // Init personal position if first-time user
    if (needsInit) {
      instructions.add(txBuilder.buildInitPositionInstruction(
        userPubkey: userPubkey,
        personalPosition: personalPosition,
        userShares: userShares,
        logAccount: logAccount,
        market: market,
      ));
    }

    // Buy navToken (takes base token, mints + auto-deposits navToken)
    instructions.add(txBuilder.buildBuyNavSolInstruction(
      userPubkey: userPubkey,
      userWsolAccount: userBaseAta,
      userNavSolAccount: userNavAta,
      personalPosition: personalPosition,
      userShares: userShares,
      logAccount: logAccount,
      market: market,
      inputLamports: inputLamports,
      minOutputLamports: minOutputLamports,
    ));

    // Borrow base token against deposited navToken collateral
    instructions.add(txBuilder.buildBorrowInstruction(
      userPubkey: userPubkey,
      userBaseTokenAccount: userBaseAta,
      personalPosition: personalPosition,
      logAccount: logAccount,
      market: market,
      borrowLamports: borrowLamports,
    ));

    if (isNativeSol) {
      // Close wSOL account (unwrap buy dust + borrowed SOL to native)
      instructions.add(txBuilder.buildCloseAccountInstruction(
        account: userBaseAta,
        destination: userPubkey,
        owner: userPubkey,
      ));
    }

    // 5. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned deposit navToken transaction for a Mayflower market.
  ///
  /// Deposits navToken (e.g., navSOL) from the user's wallet ATA into the
  /// market's personal position escrow. The user must already have a personal
  /// position for this market (i.e., have bought navTokens before).
  ///
  /// No wSOL wrapping needed — we're depositing navToken, not base token.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedDepositNavTokenTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int depositLamports,
    required String recentBlockhash,
    int computeUnitLimit = 200000,
    int computeUnitPrice = 500000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user's navToken ATA
    final userNavAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.navMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final userSharesKey = await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey);
    final personalPosition = personalPositionKey.toBase58();
    final userShares = userSharesKey.toBase58();

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create navToken ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userNavAta,
        owner: userPubkey,
        mint: market.navMint,
      ),

      // Mayflower deposit navToken
      txBuilder.buildDepositNavTokenInstruction(
        userPubkey: userPubkey,
        userNavTokenAccount: userNavAta,
        personalPosition: personalPosition,
        userShares: userShares,
        market: market,
        depositLamports: depositLamports,
      ),
    ];

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned withdraw navToken transaction for a Mayflower market.
  ///
  /// Withdraws navToken (e.g., navSOL) from the market's personal position
  /// escrow back to the user's wallet ATA. The user must already have a
  /// personal position with deposited navToken.
  ///
  /// No wSOL wrapping needed — we're withdrawing navToken, not base token.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedWithdrawNavTokenTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int withdrawLamports,
    required String recentBlockhash,
    int computeUnitLimit = 200000,
    int computeUnitPrice = 500000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user's navToken ATA
    final userNavAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.navMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final userSharesKey = await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPositionKey);
    final personalPosition = personalPositionKey.toBase58();
    final userShares = userSharesKey.toBase58();

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create navToken ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userNavAta,
        owner: userPubkey,
        mint: market.navMint,
      ),

      // Mayflower withdraw navToken
      txBuilder.buildWithdrawNavTokenInstruction(
        userPubkey: userPubkey,
        userNavTokenAccount: userNavAta,
        personalPosition: personalPosition,
        userShares: userShares,
        market: market,
        withdrawLamports: withdrawLamports,
      ),
    ];

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned claim rewards transaction for a Samsara market.
  ///
  /// Claims all accrued prANA revenue (paid in base token, e.g., SOL).
  /// No amount parameter — claims everything available.
  /// For native SOL markets, wraps/unwraps via a temporary wSOL account.
  ///
  /// Returns serialized transaction bytes ready for wallet signing.
  Future<Uint8List> buildUnsignedClaimRewardsTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required String recentBlockhash,
    int computeUnitLimit = 200000,
    int computeUnitPrice = 500000,
  }) async {
    final samsaraPda = SamsaraPda(
        Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user's base token ATA
    final userBaseAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);

    // 2. Derive Samsara PDAs
    final samsaraMarketKey =
        Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final govAccount = await samsaraPda.personalGovAccount(
        market: samsaraMarketKey, owner: ownerKey);
    final cashEscrow = await samsaraPda.marketCashEscrow(
        market: samsaraMarketKey);
    final logCounter = await samsaraPda.logCounter();

    final isNativeSol = market.baseMint == _nativeSolMint;

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create base token ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userBaseAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),
    ];

    if (isNativeSol) {
      // Transfer 0 lamports + sync native (ensure wSOL account is active)
      instructions.addAll([
        txBuilder.buildTransferInstruction(
          from: userPubkey,
          to: userBaseAta,
          lamports: 0,
        ),
        txBuilder.buildSyncNativeInstruction(userBaseAta),
      ]);
    }

    // Samsara collect revenue (claim rewards)
    instructions.add(txBuilder.buildCollectRevPranaInstruction(
      userPubkey: userPubkey,
      samsaraMarket: market.samsaraMarket,
      govAccount: govAccount.toBase58(),
      cashEscrow: cashEscrow.toBase58(),
      cashDst: userBaseAta,
      baseMint: market.baseMint,
      samLogCounter: logCounter.toBase58(),
    ));

    if (isNativeSol) {
      // Close wSOL account (unwrap to native SOL)
      instructions.add(txBuilder.buildCloseAccountInstruction(
        account: userBaseAta,
        destination: userPubkey,
        owner: userPubkey,
      ));
    }

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build an unsigned Mayflower repay transaction.
  ///
  /// Repays borrowed base token (e.g., SOL) back to the market.
  /// For native SOL markets, wraps SOL→wSOL before repay and unwraps after.
  Future<Uint8List> buildUnsignedRepayTransaction({
    required String userPubkey,
    required NavTokenMarket market,
    required int repayLamports,
    required String recentBlockhash,
    int computeUnitLimit = 200000,
    int computeUnitPrice = 500000,
  }) async {
    final mayflowerPda = MayflowerPda(
        Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId));
    final txBuilder = SamsaraTransactionBuilder(config: _config);

    // 1. Derive user's base token ATA
    final userBaseAta = await _rpcClient.getAssociatedTokenAddress(
        userPubkey, market.baseMint);

    // 2. Derive Mayflower PDAs
    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalPositionKey = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final personalPosition = personalPositionKey.toBase58();

    final isNativeSol = market.baseMint == _nativeSolMint;

    // 3. Build instruction list
    final instructions = <Instruction>[
      txBuilder.buildSetComputeUnitLimitInstruction(computeUnitLimit),
      txBuilder.buildSetComputeUnitPriceInstruction(computeUnitPrice),

      // Create base token ATA (idempotent)
      txBuilder.buildCreateAtaIdempotentInstruction(
        payer: userPubkey,
        associatedTokenAccount: userBaseAta,
        owner: userPubkey,
        mint: market.baseMint,
      ),
    ];

    if (isNativeSol) {
      // Transfer repay amount to wSOL + sync native
      instructions.addAll([
        txBuilder.buildTransferInstruction(
          from: userPubkey,
          to: userBaseAta,
          lamports: repayLamports,
        ),
        txBuilder.buildSyncNativeInstruction(userBaseAta),
      ]);
    }

    // Mayflower repay base token
    instructions.add(txBuilder.buildRepayInstruction(
      userPubkey: userPubkey,
      userBaseTokenAccount: userBaseAta,
      personalPosition: personalPosition,
      market: market,
      repayLamports: repayLamports,
    ));

    if (isNativeSol) {
      // Close wSOL account (unwrap to native SOL)
      instructions.add(txBuilder.buildCloseAccountInstruction(
        account: userBaseAta,
        destination: userPubkey,
        owner: userPubkey,
      ));
    }

    // 4. Compile and return unsigned tx
    final message = Message(instructions: instructions);
    final feePayer = Ed25519HDPublicKey.fromBase58(userPubkey);
    final compiledMessage = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
    );
    final signature = Signature(List.filled(64, 0), publicKey: feePayer);
    final signedTx = SignedTx(
        compiledMessage: compiledMessage, signatures: [signature]);
    return Uint8List.fromList(signedTx.toByteArray().toList());
  }
}

/// Tracks which indices in the getMultipleAccounts result belong to a market.
class _MarketSlice {
  final NavTokenMarket market;
  final int navAtaIndex;
  final int escrowIndex;
  final int? baseAtaIndex; // null for native SOL markets
  final int pranaEscrowIndex;
  final int govAccountIndex;
  final int personalPositionIndex;

  const _MarketSlice({
    required this.market,
    required this.navAtaIndex,
    required this.escrowIndex,
    this.baseAtaIndex,
    required this.pranaEscrowIndex,
    required this.govAccountIndex,
    required this.personalPositionIndex,
  });
}

/// Per-market fee schedule read from the on-chain MarketGroup account.
///
/// All fee values are in micro-basis-points (ubps), where 10,000 ubps = 1%.
/// For example, a buyFeeUbps of 9000 means a 0.9% buy fee.
class MarketFees {
  final String marketName;
  final int buyFeeUbps;
  final int sellFeeUbps;
  final int borrowFeeUbps;
  final int exerciseOptionFeeUbps;

  const MarketFees({
    required this.marketName,
    required this.buyFeeUbps,
    required this.sellFeeUbps,
    required this.borrowFeeUbps,
    required this.exerciseOptionFeeUbps,
  });

  /// Buy fee as a percentage (e.g., 0.9 for 0.9%).
  double get buyFeePercent => buyFeeUbps / 10000.0;

  /// Sell fee as a percentage.
  double get sellFeePercent => sellFeeUbps / 10000.0;

  /// Borrow fee as a percentage.
  double get borrowFeePercent => borrowFeeUbps / 10000.0;

  /// Exercise option fee as a percentage.
  double get exerciseOptionFeePercent => exerciseOptionFeeUbps / 10000.0;

  /// Buy fee as a ratio (e.g., 0.009 for 0.9%).
  double get buyFeeRatio => buyFeeUbps / 1000000.0;

  /// Sell fee as a ratio.
  double get sellFeeRatio => sellFeeUbps / 1000000.0;

  /// Borrow fee as a ratio.
  double get borrowFeeRatio => borrowFeeUbps / 1000000.0;

  @override
  String toString() =>
      'MarketFees($marketName: buy=${buyFeePercent.toStringAsFixed(2)}%, '
      'sell=${sellFeePercent.toStringAsFixed(2)}%, '
      'borrow=${borrowFeePercent.toStringAsFixed(2)}%, '
      'exerciseOption=${exerciseOptionFeePercent.toStringAsFixed(2)}%)';
}

/// Full per-market governance parameters read from the SamsaraMarket account.
///
/// Contains all governance-controlled parameters including fees, floor-raise
/// settings, and their vote metadata. Each parameter is stored in a 32-byte
/// block in the SamsaraMarket account (876 bytes, Samsara program-owned).
///
/// Fee values are in ubps (10,000 = 1%). Floor raise cooldown is in seconds.
/// Floor raise buffer, investment, and increase ratio are in ubps.
class MarketGovernance {
  final String marketName;

  // Fees (ubps)
  final GovernanceParam buyFee;
  final GovernanceParam sellFee;
  final GovernanceParam borrowFee;

  // Floor raise parameters
  final GovernanceParam floorRaiseCooldown;
  final GovernanceParam floorRaiseBuffer;
  final GovernanceParam floorInvestment;
  final GovernanceParam floorRaiseIncrease;

  // Exercise option fee from MarketGroup (ubps), not governance-voted
  final int exerciseOptionFeeUbps;

  const MarketGovernance({
    required this.marketName,
    required this.buyFee,
    required this.sellFee,
    required this.borrowFee,
    required this.floorRaiseCooldown,
    required this.floorRaiseBuffer,
    required this.floorInvestment,
    required this.floorRaiseIncrease,
    this.exerciseOptionFeeUbps = 0,
  });

  /// Convenience: extract just the fee values as a [MarketFees].
  MarketFees get fees => MarketFees(
        marketName: marketName,
        buyFeeUbps: buyFee.current,
        sellFeeUbps: sellFee.current,
        borrowFeeUbps: borrowFee.current,
        exerciseOptionFeeUbps: exerciseOptionFeeUbps,
      );

  @override
  String toString() => 'MarketGovernance($marketName: '
      'buy=${buyFee.current}, sell=${sellFee.current}, '
      'borrow=${borrowFee.current}, '
      'cooldown=${floorRaiseCooldown.current}s, '
      'buffer=${floorRaiseBuffer.currentPercent.toStringAsFixed(2)}%, '
      'investment=${floorInvestment.currentPercent.toStringAsFixed(2)}%, '
      'increase=${floorRaiseIncrease.currentPercent.toStringAsFixed(2)}%)';
}

/// A single governance-controlled parameter with its current value and bounds.
///
/// Stored as a 32-byte block in the SamsaraMarket account:
///   +0:  u32 previous value (or pending)
///   +4:  u32 current value
///   +8:  u32 step size (vote change rate)
///   +12: u32 maximum
///   +16: u32 minimum (or step)
class GovernanceParam {
  final int previous;
  final int current;
  final int step;
  final int maximum;
  final int minimum;

  const GovernanceParam({
    required this.previous,
    required this.current,
    required this.step,
    required this.maximum,
    required this.minimum,
  });

  /// Current value as a percentage (for ubps-encoded params, 10000 = 1%).
  double get currentPercent => current / 10000.0;

  @override
  String toString() =>
      'GovernanceParam(current=$current, step=$step, '
      'min=$minimum, max=$maximum)';
}

/// Parsed fields from a MarketMeta on-chain account.
class _ParsedMarketMeta {
  final String mayflowerMarket;
  final String marketMetadata;
  final String baseMint;
  final String navMint;
  final String marketGroup;
  final String baseVault;
  final String navVault;
  final String feeVault;

  const _ParsedMarketMeta({
    required this.mayflowerMarket,
    required this.marketMetadata,
    required this.baseMint,
    required this.navMint,
    required this.marketGroup,
    required this.baseVault,
    required this.navVault,
    required this.feeVault,
  });
}
