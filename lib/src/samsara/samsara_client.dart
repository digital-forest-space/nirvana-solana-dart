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

  /// Fetches the user's navToken balances (wallet + staked) and base token
  /// balance for a market using a single batched RPC call.
  ///
  /// Returns a map with keys:
  ///   - `'{name}'` (e.g., `'navSOL'`): unstaked navToken in user's wallet
  ///   - `'{name}_deposited'` (e.g., `'navSOL_deposited'`): navToken deposited in
  ///     the Mayflower personal position escrow
  ///   - `'{baseName}'` (e.g., `'SOL'`): user's base token balance
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

    // Derive all addresses locally (pure PDA math, no RPC)
    final navMintKey = Ed25519HDPublicKey.fromBase58(market.navMint);
    final navAta = (await findAssociatedTokenAddress(
        owner: ownerKey, mint: navMintKey)).toBase58();

    final marketMetaKey =
        Ed25519HDPublicKey.fromBase58(market.marketMetadata);
    final personalPosition = await mayflowerPda.personalPosition(
        marketMeta: marketMetaKey, owner: ownerKey);
    final escrow = (await mayflowerPda.personalPositionEscrow(
        personalPosition: personalPosition)).toBase58();

    final isNativeSol = market.baseMint == _nativeSolMint;

    // Build account list for batch fetch
    final addresses = <String>[userPubkey, navAta, escrow];
    if (!isNativeSol) {
      final baseMintKey = Ed25519HDPublicKey.fromBase58(market.baseMint);
      final baseAta = (await findAssociatedTokenAddress(
          owner: ownerKey, mint: baseMintKey)).toBase58();
      addresses.add(baseAta);
    }

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
      final baseAtaAccount = accounts[3];
      baseBalance = _parseTokenAmountFromAccountData(
          baseAtaAccount, market.baseDecimals);
    }

    return {
      market.name: _parseTokenAmountFromAccountData(
          navAtaAccount, market.navDecimals),
      '${market.name}_deposited': _parseTokenAmountFromAccountData(
          escrowAccount, market.navDecimals),
      market.baseName: baseBalance,
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

    // Derive all addresses locally for all markets
    // Track which addresses belong to which market
    final addresses = <String>[userPubkey]; // wallet always first
    final marketSlices = <_MarketSlice>[];

    for (final market in allMarkets) {
      final startIndex = addresses.length;

      final navMintKey = Ed25519HDPublicKey.fromBase58(market.navMint);
      final navAta = (await findAssociatedTokenAddress(
          owner: ownerKey, mint: navMintKey)).toBase58();
      addresses.add(navAta);

      final marketMetaKey =
          Ed25519HDPublicKey.fromBase58(market.marketMetadata);
      final personalPosition = await mayflowerPda.personalPosition(
          marketMeta: marketMetaKey, owner: ownerKey);
      final escrow = (await mayflowerPda.personalPositionEscrow(
          personalPosition: personalPosition)).toBase58();
      addresses.add(escrow);

      String? baseAta;
      if (market.baseMint != _nativeSolMint) {
        final baseMintKey = Ed25519HDPublicKey.fromBase58(market.baseMint);
        baseAta = (await findAssociatedTokenAddress(
            owner: ownerKey, mint: baseMintKey)).toBase58();
        addresses.add(baseAta);
      }

      marketSlices.add(_MarketSlice(
        market: market,
        navAtaIndex: startIndex,
        escrowIndex: startIndex + 1,
        baseAtaIndex: baseAta != null ? startIndex + 2 : null,
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
      };
    }

    return results;
  }

  static const _nativeSolMint =
      'So11111111111111111111111111111111111111112';

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

    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      throw Exception('Mayflower Market account not found: ${market.mayflowerMarket}');
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
    instructions.add(txBuilder.buildBorrowBaseInstruction(
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
    instructions.add(txBuilder.buildRepayBaseInstruction(
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

  const _MarketSlice({
    required this.market,
    required this.navAtaIndex,
    required this.escrowIndex,
    this.baseAtaIndex,
  });
}
