import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

import '../models/config.dart';
import '../models/prices.dart';
import '../models/personal_account_info.dart';
import '../models/transaction_result.dart';
import '../models/transaction_price_result.dart';
import '../models/nirvana_transaction.dart';
import '../rpc/solana_rpc_client.dart';
import '../instructions/transaction_builder.dart';
import '../accounts/account_resolver.dart';
import '../utils/retry.dart';

/// Main client for interacting with Nirvana V2 protocol
class NirvanaClient {
  static const List<int> _tenantDiscriminator = [61, 43, 215, 51, 232, 242, 209, 170];

  // Instruction discriminators for transaction type identification
  static const List<int> _buyExact2Discriminator = [109, 5, 199, 243, 164, 233, 19, 152];
  static const List<int> _sell2Discriminator = [47, 191, 120, 1, 28, 35, 253, 79];
  static const List<int> _depositAnaDiscriminator = [68, 100, 197, 87, 22, 85, 190, 78];
  static const List<int> _withdrawAnaDiscriminator = [93, 87, 203, 252, 78, 187, 97, 82];
  static const List<int> _borrowNirvDiscriminator = [155, 1, 43, 62, 79, 104, 66, 42];
  static const List<int> _repayDiscriminator = [28, 158, 130, 191, 125, 127, 195, 94];
  static const List<int> _realizeDiscriminator = [64, 34, 113, 17, 141, 79, 61, 38];
  static const List<int> _claimPranaDiscriminator = [47, 124, 203, 241, 4, 53, 226, 166];
  static const List<int> _claimRevenueShareDiscriminator = [69, 140, 105, 250, 40, 226, 233, 116];

  final SolanaRpcClient _rpcClient;
  final NirvanaTransactionBuilder _transactionBuilder;
  final NirvanaAccountResolver _accountResolver;
  final NirvanaConfig _config;

  NirvanaClient({
    required SolanaRpcClient rpcClient,
    NirvanaConfig? config,
  }) : _rpcClient = rpcClient,
       _config = config ?? NirvanaConfig.mainnet(),
       _transactionBuilder = NirvanaTransactionBuilder(config: config),
       _accountResolver = NirvanaAccountResolver(rpcClient, config: config);

  /// Create a NirvanaClient with a default RPC client
  factory NirvanaClient.withDefaultRpc({
    required SolanaClient solanaClient,
    NirvanaConfig? config,
  }) {
    final rpcClient = DefaultSolanaRpcClient(solanaClient);
    return NirvanaClient(rpcClient: rpcClient, config: config);
  }

  /// Fetches current ANA token prices from the Nirvana V2 protocol
  /// Uses transaction-based price for ANA and on-chain calculation for floor
  Future<NirvanaPrices> fetchPrices() async {
    try {
      final transactionPrice = await fetchLatestAnaPrice();
      final floorPrice = await fetchFloorPrice();

      final ana = transactionPrice.price;
      final floor = floorPrice;
      final prana = ana - floor;

      return NirvanaPrices(
        ana: ana,
        floor: floor,
        prana: prana,
        updatedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      throw Exception('Failed to fetch Nirvana prices: $e');
    }
  }

  /// Fetches the floor price from on-chain data
  Future<double> fetchFloorPrice() async {
    final priceCurveData = await _fetchPriceCurveAccountData();
    return _decodeFloorPriceFromPriceCurve(priceCurveData);
  }

  /// Fetches the latest ANA price from a recent buy/sell transaction
  /// [maxTxToCheck] - Maximum number of transactions to check
  /// [delayMs] - Delay between RPC calls in milliseconds to avoid rate limiting
  /// [maxRetries] - Maximum retries per transaction on rate limit errors
  Future<TransactionPriceResult> fetchLatestAnaPrice({
    int maxTxToCheck = 20,
    int delayMs = 2000,
    int maxRetries = 3,
  }) async {
    try {
      final signatures = await _rpcClient.getSignaturesForAddress(
        _config.programId,
        limit: 100,
      );

      int txIndex = 0;
      int txChecked = 0;
      int retryCount = 0;

      while (txIndex < signatures.length && txChecked < maxTxToCheck) {
        final sig = signatures[txIndex];

        try {
          if (txChecked > 0 && delayMs > 0) {
            await Future.delayed(Duration(milliseconds: delayMs));
          }

          final result = await _parseTransactionPrice(sig);
          return result;
        } catch (e) {
          final errorMsg = e.toString();

          // Handle rate limiting with retry
          if (errorMsg.contains('429') && retryCount < maxRetries) {
            retryCount++;
            await Future.delayed(const Duration(seconds: 10));
            // Don't increment txIndex or txChecked - retry same transaction
            continue;
          }

          // Reset retry count and move to next transaction
          retryCount = 0;
          txIndex++;
          txChecked++;
        }
      }

      throw Exception('No recent ANA buy/sell transactions found');
    } catch (e) {
      throw Exception('Failed to fetch latest ANA price: $e');
    }
  }

  /// Parses a transaction to extract ANA price
  /// Ported from companion's get_price_from_transaction.dart
  Future<TransactionPriceResult> _parseTransactionPrice(String signature) async {
    final txData = await _rpcClient.getTransaction(signature);

    final meta = txData['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw Exception('Transaction metadata not found');
    }

    if (meta['err'] != null) {
      throw Exception('Transaction failed');
    }

    // Get account keys to identify user address
    final transaction = txData['transaction'] as Map<String, dynamic>?;
    final message = transaction?['message'] as Map<String, dynamic>?;
    final accountKeys = message?['accountKeys'] as List? ?? [];

    String? userAddress;
    if (accountKeys.isNotEmpty) {
      final firstKey = accountKeys[0];
      userAddress = firstKey is String ? firstKey : firstKey['pubkey'];
    }

    // Parse instructions to find burn/mint/transfer operations
    final instructions = message?['instructions'] as List? ?? [];
    final innerInstructions = meta['innerInstructions'] as List? ?? [];

    // Collect all instructions (both top-level and inner)
    List<Map<String, dynamic>> allInstructions = [];
    for (final instruction in instructions) {
      allInstructions.add(instruction as Map<String, dynamic>);
    }
    for (final inner in innerInstructions) {
      final innerList = inner['instructions'] as List? ?? [];
      for (final instruction in innerList) {
        allInstructions.add(instruction as Map<String, dynamic>);
      }
    }

    // Track burn/mint changes separately for accurate pricing
    Map<String, double> burnMintChanges = {};
    Map<String, double> feeChanges = {};

    const String tenantFeeAccount = '42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP';

    for (final instruction in allInstructions) {
      if (instruction['program'] != 'spl-token') continue;

      final parsed = instruction['parsed'];
      if (parsed == null) continue;

      final type = parsed['type'] as String?;
      final info = parsed['info'] as Map<String, dynamic>?;
      if (info == null) continue;

      if (type == 'burn') {
        final mint = info['mint'] as String?;
        final amount = info['amount'] as String?;
        final authority = info['authority'] as String?;
        if (mint != null && amount != null && authority != null) {
          final rawAmount = int.parse(amount);
          final uiAmount = rawAmount / 1000000.0; // 6 decimals
          burnMintChanges['burn_${mint}_$authority'] = -uiAmount;
        }
      } else if (type == 'mint' || type == 'mintTo') {
        final mint = info['mint'] as String?;
        final amount = info['amount'] as String?;
        final account = info['account'] as String?;
        if (mint != null && amount != null) {
          final rawAmount = int.parse(amount);
          final uiAmount = rawAmount / 1000000.0;
          burnMintChanges['mint_${mint}_$account'] = uiAmount;
        }
      } else if (type == 'transfer' || type == 'transferChecked') {
        final destination = info['destination'] as String?;
        final authority = info['authority'] as String?;
        String? mint = info['mint'] as String?;
        double? uiAmount;

        if (type == 'transferChecked') {
          final tokenAmount = info['tokenAmount'] as Map<String, dynamic>?;
          uiAmount = tokenAmount?['uiAmount'] as double?;
        }

        // Track fee transfers to tenant fee account
        if (mint != null && uiAmount != null && authority != null) {
          if (destination == tenantFeeAccount) {
            feeChanges['fee_${mint}_$authority'] = -uiAmount;
          }
        }
      }
    }

    // Extract token balance changes
    final preTokenBalances = meta['preTokenBalances'] as List? ?? [];
    final postTokenBalances = meta['postTokenBalances'] as List? ?? [];

    final allChanges = _extractBalanceChanges(preTokenBalances, postTokenBalances);

    final tenantChanges = allChanges.where((c) => c['owner'] == _config.tenantAccount).toList();
    final userChanges = allChanges.where((c) => c['owner'] != _config.tenantAccount).toList();

    // Check if prANA is involved - skip if so (these are staking operations)
    final pranaUserChange = _getChangeForMint(userChanges, _config.pranaMint);
    final pranaTenantChange = _getChangeForMint(tenantChanges, _config.pranaMint);
    if (pranaUserChange != 0.0 || pranaTenantChange != 0.0) {
      throw Exception('prANA involved - not a buy/sell transaction');
    }

    // Get balance changes
    double anaUserChange = _getChangeForMint(userChanges, _config.anaMint);
    double nirvUserChange = _getChangeForMint(userChanges, _config.nirvMint);
    double usdcUserChange = _getChangeForMint(userChanges, _config.usdcMint);

    // Fall back to instruction-based changes if balance changes are 0
    if (anaUserChange == 0.0) {
      for (final entry in burnMintChanges.entries) {
        if (entry.key.contains(_config.anaMint)) {
          anaUserChange += entry.value;
        }
      }
    }

    if (nirvUserChange == 0.0) {
      for (final entry in burnMintChanges.entries) {
        if (entry.key.contains(_config.nirvMint)) {
          nirvUserChange += entry.value;
        }
      }
    }

    if (usdcUserChange == 0.0) {
      for (final entry in burnMintChanges.entries) {
        if (entry.key.contains(_config.usdcMint)) {
          usdcUserChange += entry.value;
        }
      }
    }

    // Calculate burn/mint amounts for pricing
    double anaBurnMint = 0.0;
    double nirvBurnMint = 0.0;
    for (final entry in burnMintChanges.entries) {
      if (entry.key.contains(_config.anaMint)) {
        anaBurnMint += entry.value;
      } else if (entry.key.contains(_config.nirvMint)) {
        nirvBurnMint += entry.value;
      }
    }

    // Calculate fee amounts per currency
    double anaFee = 0.0;
    double nirvFee = 0.0;
    double usdcFee = 0.0;
    for (final entry in feeChanges.entries) {
      if (entry.key.contains(_config.anaMint)) {
        anaFee += entry.value.abs();
      } else if (entry.key.contains(_config.nirvMint)) {
        nirvFee += entry.value.abs();
      } else if (entry.key.contains(_config.usdcMint)) {
        usdcFee += entry.value.abs();
      }
    }

    // Determine direction from burn/mint if available, otherwise from balance
    final anaChange = anaBurnMint != 0.0 ? anaBurnMint : anaUserChange;

    if (anaChange == 0.0) {
      throw Exception('No ANA balance change detected');
    }

    double pricePerAna;
    double paymentAmount;
    String currency;

    if (anaChange > 0) {
      // Minted ANA = BUY transaction
      final anaAmount = anaChange;
      if (nirvUserChange < 0 || nirvBurnMint < 0) {
        paymentAmount = (nirvBurnMint != 0.0 ? nirvBurnMint.abs() : nirvUserChange.abs());
        currency = 'NIRV';
      } else if (usdcUserChange < 0) {
        paymentAmount = usdcUserChange.abs();
        currency = 'USDC';
      } else {
        throw Exception('Could not determine payment currency for buy');
      }
      pricePerAna = paymentAmount / anaAmount;
    } else {
      // Burned ANA = SELL transaction
      final anaAmount = anaChange.abs();
      if (nirvUserChange > 0 || nirvBurnMint > 0) {
        paymentAmount = (nirvBurnMint != 0.0 ? nirvBurnMint : nirvUserChange);
        currency = 'NIRV';
      } else if (usdcUserChange > 0) {
        paymentAmount = usdcUserChange;
        currency = 'USDC';
      } else {
        throw Exception('Could not determine received currency for sell');
      }
      pricePerAna = paymentAmount / anaAmount;
    }

    return TransactionPriceResult(
      price: pricePerAna,
      transaction: signature,
      fee: anaFee,
      currency: currency,
    );
  }

  List<Map<String, dynamic>> _extractBalanceChanges(
    List<dynamic> preTokenBalances,
    List<dynamic> postTokenBalances,
  ) {
    final List<Map<String, dynamic>> changes = [];
    final Set<int> processedIndices = {};

    for (final preBalance in preTokenBalances) {
      final accountIndex = preBalance['accountIndex'] as int;
      final mint = preBalance['mint'] as String;
      processedIndices.add(accountIndex);

      final postBalance = postTokenBalances
          .cast<Map<String, dynamic>>()
          .where((pb) => pb['accountIndex'] == accountIndex)
          .firstOrNull;

      if (postBalance == null) continue;

      final preAmount = double.parse(preBalance['uiTokenAmount']['uiAmountString'] ?? '0');
      final postAmount = double.parse(postBalance['uiTokenAmount']['uiAmountString'] ?? '0');
      final change = postAmount - preAmount;

      if (change.abs() < 0.000001) continue;

      changes.add({
        'mint': mint,
        'change': change,
        'owner': preBalance['owner'] ?? 'unknown',
      });
    }

    // Check for new accounts (in post but not in pre)
    for (final postBalance in postTokenBalances) {
      final accountIndex = postBalance['accountIndex'] as int;
      if (processedIndices.contains(accountIndex)) continue;

      final mint = postBalance['mint'] as String;
      final postAmount = double.parse(postBalance['uiTokenAmount']['uiAmountString'] ?? '0');

      if (postAmount.abs() < 0.000001) continue;

      changes.add({
        'mint': mint,
        'change': postAmount,
        'owner': postBalance['owner'] ?? 'unknown',
      });
      processedIndices.add(accountIndex);
    }

    // Check for closed accounts (in pre but not in post)
    for (final preBalance in preTokenBalances) {
      final accountIndex = preBalance['accountIndex'] as int;
      if (processedIndices.contains(accountIndex)) continue;

      final mint = preBalance['mint'] as String;
      final preAmount = double.parse(preBalance['uiTokenAmount']['uiAmountString'] ?? '0');

      if (preAmount.abs() < 0.000001) continue;

      changes.add({
        'mint': mint,
        'change': -preAmount,
        'owner': preBalance['owner'] ?? 'unknown',
      });
    }

    return changes;
  }

  double _getChangeForMint(List<Map<String, dynamic>> changes, String mint) {
    final match = changes.where((c) => c['mint'] == mint).firstOrNull;
    return (match?['change'] as double?) ?? 0.0;
  }

  /// Build a map of token account addresses to their mint addresses
  /// from the transaction's token balance data
  Map<String, String> _buildAccountToMintMap(
    List accountKeys,
    List preTokenBalances,
    List postTokenBalances,
  ) {
    final accountToMint = <String, String>{};

    // Process both pre and post balances to get account->mint mappings
    for (final balance in [...preTokenBalances, ...postTokenBalances]) {
      final accountIndex = balance['accountIndex'] as int?;
      final mint = balance['mint'] as String?;

      if (accountIndex != null && mint != null && accountIndex < accountKeys.length) {
        final accountKey = accountKeys[accountIndex];
        final address = accountKey is String ? accountKey : accountKey['pubkey'] as String?;
        if (address != null) {
          accountToMint[address] = mint;
        }
      }
    }

    return accountToMint;
  }

  Future<Uint8List> _fetchPriceCurveAccountData() async {
    final accountInfo = await _rpcClient.getAccountInfo(_config.priceCurve);

    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      throw Exception('PriceCurve2 account not found');
    }

    final base64Data = accountInfo['data']?[0];
    if (base64Data == null || base64Data.isEmpty) {
      throw Exception('PriceCurve2 account contains no data');
    }

    final bytes = base64.decode(base64Data);

    return bytes;
  }

  Future<Uint8List> _fetchTenantAccountData() async {
    final accountInfo = await _rpcClient.getAccountInfo(_config.tenantAccount);
    
    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      throw Exception('Nirvana Tenant account not found');
    }

    final base64Data = accountInfo['data']?[0];
    if (base64Data == null || base64Data.isEmpty) {
      throw Exception('Tenant account contains no data');
    }

    final bytes = base64.decode(base64Data);

    if (!_verifyTenantAccount(bytes)) {
      throw Exception('Invalid Tenant account discriminator - not a valid Nirvana V2 account');
    }

    return bytes;
  }

  bool _verifyTenantAccount(Uint8List bytes) {
    if (bytes.length < 8) return false;

    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _tenantDiscriminator[i]) {
        return false;
      }
    }
    return true;
  }

  _PriceData _calculatePrices(Uint8List tenantBytes, Uint8List priceCurveBytes) {
    final int minimumTenantBytes = 593;
    if (tenantBytes.length < minimumTenantBytes) {
      throw Exception('Tenant account data too small - expected at least $minimumTenantBytes bytes, got ${tenantBytes.length}');
    }

    final int minimumPriceCurveBytes = 104;
    if (priceCurveBytes.length < minimumPriceCurveBytes) {
      throw Exception('PriceCurve2 account data too small - expected at least $minimumPriceCurveBytes bytes, got ${priceCurveBytes.length}');
    }

    final double anaFloor = _decodeFloorPriceFromPriceCurve(priceCurveBytes);

    final int depositedAna = _readDepositedAna(tenantBytes);

    final int floorEndVertexX = _readFloorEndVertexX(priceCurveBytes);

    final double floorEndVertexSlope = _readFloorEndVertexSlope(priceCurveBytes);

    final double sellFeeRatio = _readSellFeeRatio(tenantBytes);

    final double anaMarketRaw = _calculateMarketPrice(
      anaFloor,
      depositedAna,
      floorEndVertexX,
      floorEndVertexSlope,
    );

    final double anaMarket = anaMarketRaw * (1 - sellFeeRatio);

    final double prana = anaMarket - anaFloor;

    final bool isFloorPriceValid = anaFloor > 0 && anaFloor < 1000;
    if (!isFloorPriceValid) {
      throw Exception('Floor price out of reasonable range: \$${anaFloor.toStringAsFixed(4)}');
    }

    final bool isMarketPriceValid = anaMarket > 0 && anaMarket < 1000;
    if (!isMarketPriceValid) {
      throw Exception('Market price out of reasonable range: \$${anaMarket.toStringAsFixed(4)}');
    }

    final bool isPranaPriceValid = prana >= 0 && prana < 100;
    if (!isPranaPriceValid) {
      throw Exception('prANA price out of reasonable range: \$${prana.toStringAsFixed(4)}');
    }

    return _PriceData(
      anaMarket: anaMarket,
      anaFloor: anaFloor,
      prana: prana,
    );
  }

  double _decodeFloorPriceFromPriceCurve(Uint8List priceCurveBytes) {
    const int floorPriceOffset = 40;
    const int floorPriceBytesLength = 16;

    final List<int> floorPriceBytes = priceCurveBytes.sublist(
      floorPriceOffset,
      floorPriceOffset + floorPriceBytesLength,
    );

    final double floorPrice = _decodeDecimalBytes(floorPriceBytes);

    return floorPrice;
  }

  int _readDepositedAna(Uint8List tenantBytes) {
    const int discriminatorLength = 8;
    const int adminPubkeyLength = 32;
    const int flagsLength = 1;
    const int vaultFieldsLength = 32 * 12;

    const int depositedAnaOffset = discriminatorLength +
        adminPubkeyLength +
        flagsLength +
        vaultFieldsLength;

    final int depositedAna = _bytesToUint64(
      tenantBytes.sublist(depositedAnaOffset, depositedAnaOffset + 8),
    );

    return depositedAna;
  }

  int _readFloorEndVertexX(Uint8List priceCurveBytes) {
    const int floorEndVertexXOffset = 56;

    final int floorEndVertexX = _bytesToUint64(
      priceCurveBytes.sublist(floorEndVertexXOffset, floorEndVertexXOffset + 8),
    );

    return floorEndVertexX;
  }

  double _readFloorEndVertexSlope(Uint8List priceCurveBytes) {
    const int floorEndVertexSlopeOffset = 64;
    const int slopeBytesLength = 16;

    final List<int> slopeBytes = priceCurveBytes.sublist(
      floorEndVertexSlopeOffset,
      floorEndVertexSlopeOffset + slopeBytesLength,
    );

    final double slope = _decodeDecimalBytes(slopeBytes);

    return slope;
  }

  double _readSellFeeRatio(Uint8List tenantBytes) {
    // Offset 585 contains the total sell fee (8953 Mbps = 0.8953%)
    // This includes both the ANA fee portion and USDC adjustment
    const int sellFeeMbpsOffset = 585;

    final int sellFeeMbps = _bytesToUint64(
      tenantBytes.sublist(sellFeeMbpsOffset, sellFeeMbpsOffset + 8),
    );

    final double sellFeeRatio = sellFeeMbps / 1000000.0;

    return sellFeeRatio;
  }

  double _calculateMarketPrice(
    double floorPrice,
    int depositedAna,
    int floorEndVertexX,
    double slope,
  ) {
    final bool isDepositedAnaValid = depositedAna > 0;
    if (!isDepositedAnaValid) {
      throw Exception('Invalid deposited ANA - value is zero');
    }

    final bool isAtOrAboveFloor = depositedAna >= floorEndVertexX;
    if (isAtOrAboveFloor) {
      return floorPrice;
    }

    final int distanceToFloor = floorEndVertexX - depositedAna;

    final double premium = slope * distanceToFloor.toDouble();

    final double marketPrice = floorPrice + premium;

    return marketPrice;
  }

  double _decodeDecimalBytes(List<int> bytes) {
    final int scale = bytes[2];
    if (scale < 10 || scale > 32) return 0.0;

    BigInt rawValue = BigInt.zero;
    for (int i = 4; i < 16; i++) {
      rawValue |= BigInt.from(bytes[i]) << (8 * (i - 4));
    }

    final BigInt divisor = BigInt.from(10).pow(scale);
    return rawValue.toDouble() / divisor.toDouble();
  }

  int _bytesToUint64(List<int> bytes) {
    if (bytes.length < 8) {
      throw Exception('Insufficient bytes for uint64 conversion');
    }

    int value = 0;
    for (int i = 0; i < 8; i++) {
      value |= bytes[i] << (8 * i);
    }
    return value;
  }
  
  /// Get user's personal account information
  Future<PersonalAccountInfo?> getPersonalAccountInfo(String userPubkey) async {
    final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
    if (personalAccount == null) return null;
    
    try {
      final accountInfo = await _rpcClient.getAccountInfo(personalAccount);
      if (accountInfo.isEmpty || accountInfo['data'] == null) return null;
      
      final accountData = base64Decode(accountInfo['data'][0]);
      
      // Parse PersonalAccount data structure
      // Skip discriminator (8) + field_0 (32) + field_1 (32) = 72 bytes
      int offset = 72;
      
      // Read fields
      final anaDebt = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      final stakedAna = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      // Skip fields 2-5 (4 * 8 = 32 bytes)
      offset += 32;
      
      // Read field 6 (claimable prANA)
      final claimablePrana = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      // Skip fields 7-13 (7 * 8 = 56 bytes)
      offset += 56;
      
      // Read field 14 (staked prANA)
      final stakedPrana = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      
      return PersonalAccountInfo(
        address: personalAccount,
        anaDebt: anaDebt,
        stakedAna: stakedAna,
        claimablePrana: claimablePrana,
        stakedPrana: stakedPrana,
        lastUpdated: DateTime.now().toUtc(),
      );
    } catch (e) {
      throw Exception('Failed to get personal account info: $e');
    }
  }
  
  /// Get user's token balances (ANA, NIRV, USDC, prANA)
  Future<Map<String, double>> getUserBalances(String userPubkey) async {
    return await _accountResolver.getUserBalances(userPubkey);
  }

  /// Parse a Nirvana protocol transaction to extract details
  /// Returns transaction type, amounts received/spent, and timestamp
  /// Uses retry with exponential backoff for transient errors
  Future<NirvanaTransaction> parseTransaction(String signature) async {
    final txData = await Retry.withBackoff(
      operation: () => _rpcClient.getTransaction(signature),
      maxAttempts: 5,
      initialDelay: 2000,
      retryIf: Retry.isRetryableError,
    );

    final meta = txData['meta'] as Map<String, dynamic>?;
    if (meta == null) {
      throw Exception('Transaction metadata not found');
    }

    if (meta['err'] != null) {
      throw Exception('Transaction failed: ${meta['err']}');
    }

    // Get timestamp
    final blockTime = txData['blockTime'] as int?;
    final timestamp = blockTime != null
        ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000, isUtc: true)
        : DateTime.now().toUtc();

    // Get account keys and user address
    final transaction = txData['transaction'] as Map<String, dynamic>?;
    final message = transaction?['message'] as Map<String, dynamic>?;
    final accountKeys = message?['accountKeys'] as List? ?? [];

    String userAddress = '';
    if (accountKeys.isNotEmpty) {
      final firstKey = accountKeys[0];
      userAddress = firstKey is String ? firstKey : firstKey['pubkey'] ?? '';
    }

    // Identify transaction type from instruction discriminator
    final instructions = message?['instructions'] as List? ?? [];
    NirvanaTransactionType txType = NirvanaTransactionType.unknown;

    for (final instruction in instructions) {
      final programId = instruction['programId'] as String?;
      if (programId != _config.programId) continue;

      final data = instruction['data'] as String?;
      if (data == null) continue;

      // Decode base58 instruction data
      final dataBytes = _decodeBase58(data);
      if (dataBytes.length < 8) continue;

      final discriminator = dataBytes.sublist(0, 8);
      txType = _identifyTransactionType(discriminator);
      if (txType != NirvanaTransactionType.unknown) break;
    }

    // Extract token balance changes
    final preTokenBalances = meta['preTokenBalances'] as List? ?? [];
    final postTokenBalances = meta['postTokenBalances'] as List? ?? [];
    final allChanges = _extractBalanceChanges(preTokenBalances, postTokenBalances);

    // Build map of token account address -> mint address from token balances
    // This is needed to resolve mint for simple transfer instructions
    final accountToMint = _buildAccountToMintMap(accountKeys, preTokenBalances, postTokenBalances);

    // Separate by owner
    final tenantChanges = allChanges.where((c) => c['owner'] == _config.tenantAccount).toList();
    final userChanges = allChanges.where((c) => c['owner'] != _config.tenantAccount).toList();

    // Get balance changes for each token
    double anaChange = _getChangeForMint(userChanges, _config.anaMint);
    double nirvChange = _getChangeForMint(userChanges, _config.nirvMint);
    double usdcChange = _getChangeForMint(userChanges, _config.usdcMint);
    double pranaChange = _getChangeForMint(userChanges, _config.pranaMint);

    // Parse inner instructions for burn/mint operations (fallback if balance changes are 0)
    final innerInstructions = meta['innerInstructions'] as List? ?? [];
    final burnMintChanges = _parseBurnMintOperations(instructions, innerInstructions);
    final feeTransfers = _parseFeeTransfers(instructions, innerInstructions, accountToMint, userAddress);

    if (anaChange == 0.0) {
      anaChange = burnMintChanges['ANA'] ?? 0.0;
    }
    if (nirvChange == 0.0) {
      nirvChange = burnMintChanges['NIRV'] ?? 0.0;
    }

    // Determine received and sent based on transaction type and balance changes
    final List<TokenAmount> receivedList = [];
    final List<TokenAmount> sentList = [];
    TokenAmount? fee;

    // Build fee TokenAmount from the first fee found (there's typically only one fee per transaction)
    TokenAmount? buildFeeFromTransfers(Map<String, double> fees) {
      for (final entry in fees.entries) {
        if (entry.value > 0) {
          return TokenAmount(amount: entry.value, currency: entry.key);
        }
      }
      return null;
    }

    switch (txType) {
      case NirvanaTransactionType.buy:
        // User receives ANA, sends NIRV or USDC
        // Fee is minted to treasury in ANA (different currency from sent)
        if (anaChange > 0) {
          receivedList.add(TokenAmount(amount: anaChange, currency: 'ANA'));
        }
        if (nirvChange < 0) {
          sentList.add(TokenAmount(amount: nirvChange.abs(), currency: 'NIRV'));
        } else if (usdcChange < 0) {
          sentList.add(TokenAmount(amount: usdcChange.abs(), currency: 'USDC'));
        }
        fee = buildFeeFromTransfers(feeTransfers);
        break;

      case NirvanaTransactionType.sell:
        // User sends ANA, receives USDC or NIRV
        // Fee is taken from the ANA being sold
        if (anaChange < 0) {
          sentList.add(TokenAmount(amount: anaChange.abs(), currency: 'ANA'));
        }
        if (usdcChange > 0) {
          receivedList.add(TokenAmount(amount: usdcChange, currency: 'USDC'));
        } else if (nirvChange > 0) {
          receivedList.add(TokenAmount(amount: nirvChange, currency: 'NIRV'));
        }
        fee = buildFeeFromTransfers(feeTransfers);
        break;

      case NirvanaTransactionType.stake:
        // User sends ANA (transfers to vault)
        if (anaChange < 0) {
          sentList.add(TokenAmount(amount: anaChange.abs(), currency: 'ANA'));
        }
        break;

      case NirvanaTransactionType.unstake:
        // User receives ANA (from vault), may have ANA fee
        if (anaChange > 0) {
          receivedList.add(TokenAmount(amount: anaChange, currency: 'ANA'));
        }
        fee = buildFeeFromTransfers(feeTransfers);
        break;

      case NirvanaTransactionType.borrow:
        // User receives NIRV (minted), fee is also minted in NIRV to escrow
        if (nirvChange > 0) {
          receivedList.add(TokenAmount(amount: nirvChange, currency: 'NIRV'));
        }
        fee = buildFeeFromTransfers(feeTransfers);
        break;

      case NirvanaTransactionType.repay:
        // User sends NIRV (burned to repay debt)
        if (nirvChange < 0) {
          sentList.add(TokenAmount(amount: nirvChange.abs(), currency: 'NIRV'));
        }
        break;

      case NirvanaTransactionType.realize:
        // User sends prANA + NIRV/USDC, receives ANA
        if (pranaChange < 0) {
          sentList.add(TokenAmount(amount: pranaChange.abs(), currency: 'prANA'));
        }
        if (nirvChange < 0) {
          sentList.add(TokenAmount(amount: nirvChange.abs(), currency: 'NIRV'));
        } else if (usdcChange < 0) {
          sentList.add(TokenAmount(amount: usdcChange.abs(), currency: 'USDC'));
        }
        if (anaChange > 0) {
          receivedList.add(TokenAmount(amount: anaChange, currency: 'ANA'));
        }
        break;

      case NirvanaTransactionType.claimPrana:
        // User receives prANA
        if (pranaChange > 0) {
          receivedList.add(TokenAmount(amount: pranaChange, currency: 'prANA'));
        }
        break;

      case NirvanaTransactionType.claimRevenueShare:
        // User receives ANA + NIRV (revenue share from fees)
        if (anaChange > 0) {
          receivedList.add(TokenAmount(amount: anaChange, currency: 'ANA'));
        }
        if (nirvChange > 0) {
          receivedList.add(TokenAmount(amount: nirvChange, currency: 'NIRV'));
        }
        break;

      case NirvanaTransactionType.unknown:
        // Try to infer from balance changes
        if (anaChange > 0) {
          receivedList.add(TokenAmount(amount: anaChange, currency: 'ANA'));
        } else if (anaChange < 0) {
          sentList.add(TokenAmount(amount: anaChange.abs(), currency: 'ANA'));
        }
        if (nirvChange > 0 && receivedList.isEmpty) {
          receivedList.add(TokenAmount(amount: nirvChange, currency: 'NIRV'));
        } else if (nirvChange < 0 && sentList.isEmpty) {
          sentList.add(TokenAmount(amount: nirvChange.abs(), currency: 'NIRV'));
        }
        if (usdcChange > 0 && receivedList.isEmpty) {
          receivedList.add(TokenAmount(amount: usdcChange, currency: 'USDC'));
        } else if (usdcChange < 0 && sentList.isEmpty) {
          sentList.add(TokenAmount(amount: usdcChange.abs(), currency: 'USDC'));
        }
        fee = buildFeeFromTransfers(feeTransfers);
        break;
    }

    return NirvanaTransaction(
      signature: signature,
      type: txType,
      received: receivedList,
      sent: sentList,
      fee: fee,
      timestamp: timestamp,
      userAddress: userAddress,
    );
  }

  NirvanaTransactionType _identifyTransactionType(List<int> discriminator) {
    if (_listEquals(discriminator, _buyExact2Discriminator)) {
      return NirvanaTransactionType.buy;
    }
    if (_listEquals(discriminator, _sell2Discriminator)) {
      return NirvanaTransactionType.sell;
    }
    if (_listEquals(discriminator, _depositAnaDiscriminator)) {
      return NirvanaTransactionType.stake;
    }
    if (_listEquals(discriminator, _withdrawAnaDiscriminator)) {
      return NirvanaTransactionType.unstake;
    }
    if (_listEquals(discriminator, _borrowNirvDiscriminator)) {
      return NirvanaTransactionType.borrow;
    }
    if (_listEquals(discriminator, _repayDiscriminator)) {
      return NirvanaTransactionType.repay;
    }
    if (_listEquals(discriminator, _realizeDiscriminator)) {
      return NirvanaTransactionType.realize;
    }
    if (_listEquals(discriminator, _claimPranaDiscriminator)) {
      return NirvanaTransactionType.claimPrana;
    }
    if (_listEquals(discriminator, _claimRevenueShareDiscriminator)) {
      return NirvanaTransactionType.claimRevenueShare;
    }
    return NirvanaTransactionType.unknown;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<int> _decodeBase58(String data) {
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var result = BigInt.zero;
    for (int i = 0; i < data.length; i++) {
      final index = alphabet.indexOf(data[i]);
      if (index < 0) return [];
      result = result * BigInt.from(58) + BigInt.from(index);
    }
    final bytes = <int>[];
    while (result > BigInt.zero) {
      bytes.insert(0, (result % BigInt.from(256)).toInt());
      result = result ~/ BigInt.from(256);
    }
    // Add leading zeros
    for (int i = 0; i < data.length && data[i] == '1'; i++) {
      bytes.insert(0, 0);
    }
    return bytes;
  }

  Map<String, double> _parseBurnMintOperations(List instructions, List innerInstructions) {
    final changes = <String, double>{};

    void processInstruction(Map<String, dynamic> instruction) {
      if (instruction['program'] != 'spl-token') return;

      final parsed = instruction['parsed'];
      if (parsed == null) return;

      final type = parsed['type'] as String?;
      final info = parsed['info'] as Map<String, dynamic>?;
      if (info == null) return;

      if (type == 'burn') {
        final mint = info['mint'] as String?;
        final amount = info['amount'] as String?;
        if (mint != null && amount != null) {
          final rawAmount = int.parse(amount);
          final uiAmount = rawAmount / 1000000.0;
          final currency = _mintToCurrency(mint);
          changes[currency] = (changes[currency] ?? 0.0) - uiAmount;
        }
      } else if (type == 'mint' || type == 'mintTo') {
        final mint = info['mint'] as String?;
        final amount = info['amount'] as String?;
        if (mint != null && amount != null) {
          final rawAmount = int.parse(amount);
          final uiAmount = rawAmount / 1000000.0;
          final currency = _mintToCurrency(mint);
          changes[currency] = (changes[currency] ?? 0.0) + uiAmount;
        }
      }
    }

    for (final instruction in instructions) {
      if (instruction is Map<String, dynamic>) {
        processInstruction(instruction);
      }
    }

    for (final inner in innerInstructions) {
      final innerList = inner['instructions'] as List? ?? [];
      for (final instruction in innerList) {
        if (instruction is Map<String, dynamic>) {
          processInstruction(instruction);
        }
      }
    }

    return changes;
  }

  /// Parse fee amounts from instructions
  /// Fees can be:
  /// - Mints to fee account (42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP) for buy transactions
  /// - Mints to treasury (BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV) for borrow transactions
  /// - Transfers to fee account for other transactions
  ///
  /// [accountToMint] maps token account addresses to their mint addresses
  /// (used to resolve mint for simple transfer instructions that don't include it)
  /// [userAddress] is the user's wallet address to exclude user mints from fee detection
  Map<String, double> _parseFeeTransfers(
    List instructions,
    List innerInstructions,
    Map<String, String> accountToMint,
    String userAddress,
  ) {
    // Protocol fee accounts - fees go to one of these depending on operation type
    const feeAccounts = {
      '42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP', // escrowRevNirv (buy/sell fees)
      'v2EeX2VjgsMbwokj6UDmAm691oePzrcvKpK5DT7LwbQ',  // escrowNirvAccount (borrow fees)
    };
    final fees = <String, double>{};

    void processInstruction(Map<String, dynamic> instruction) {
      if (instruction['program'] != 'spl-token') return;

      final parsed = instruction['parsed'];
      if (parsed == null) return;

      final type = parsed['type'] as String?;
      final info = parsed['info'] as Map<String, dynamic>?;
      if (info == null) return;

      // Track mints to fee accounts (fee on buy/borrow)
      if (type == 'mintTo') {
        final account = info['account'] as String?;
        final mint = info['mint'] as String?;
        final amount = info['amount'] as String?;

        // Check if mint destination is a fee account
        if (feeAccounts.contains(account) && mint != null && amount != null) {
          final uiAmount = int.parse(amount) / 1000000.0;
          final currency = _mintToCurrency(mint);
          fees[currency] = (fees[currency] ?? 0.0) + uiAmount;
        }
      }

      // Track transfers to fee accounts (fee on sell/other)
      if (type == 'transfer' || type == 'transferChecked') {
        final destination = info['destination'] as String?;
        final source = info['source'] as String?;
        String? mint = info['mint'] as String?;

        // Only track transfers to fee accounts
        if (!feeAccounts.contains(destination)) return;

        // For simple 'transfer' instructions, mint is not included - look it up from source account
        if (mint == null && source != null) {
          mint = accountToMint[source];
        }

        double? uiAmount;
        if (type == 'transferChecked') {
          final tokenAmount = info['tokenAmount'] as Map<String, dynamic>?;
          uiAmount = tokenAmount?['uiAmount'] as double?;
        } else {
          final amount = info['amount'] as String?;
          if (amount != null) {
            uiAmount = int.parse(amount) / 1000000.0;
          }
        }

        if (mint != null && uiAmount != null) {
          final currency = _mintToCurrency(mint);
          fees[currency] = (fees[currency] ?? 0.0) + uiAmount;
        }
      }
    }

    for (final instruction in instructions) {
      if (instruction is Map<String, dynamic>) {
        processInstruction(instruction);
      }
    }

    for (final inner in innerInstructions) {
      final innerList = inner['instructions'] as List? ?? [];
      for (final instruction in innerList) {
        if (instruction is Map<String, dynamic>) {
          processInstruction(instruction);
        }
      }
    }

    return fees;
  }

  String _mintToCurrency(String mint) {
    if (mint == _config.anaMint) return 'ANA';
    if (mint == _config.nirvMint) return 'NIRV';
    if (mint == _config.usdcMint) return 'USDC';
    if (mint == _config.pranaMint) return 'prANA';
    return mint.substring(0, 8);
  }

  /// Buy ANA tokens
  Future<TransactionResult> buyAna({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double amount,
    required bool useNirv,
    double? minAnaAmount,
  }) async {
    try {
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);

      // Validate payment account
      final paymentAccount = useNirv ? accounts.nirvAccount : accounts.usdcAccount;
      if (paymentAccount == null) {
        throw Exception('User does not have ${useNirv ? "NIRV" : "USDC"} token account');
      }

      // Ensure ANA and NIRV accounts exist
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }

      // Convert amount to lamports (6 decimals)
      final amountLamports = (amount * 1000000).toInt();
      final minAnaLamports = minAnaAmount != null
          ? (minAnaAmount * 1000000).toInt()
          : 0;

      // Build buy instruction
      final instruction = _transactionBuilder.buildBuyExact2Instruction(
        userPubkey: userPubkey,
        userPaymentAccount: paymentAccount,
        userAnaAccount: accounts.anaAccount!,
        userNirvAccount: accounts.nirvAccount!,
        amountLamports: amountLamports,
        useNirv: useNirv,
        minAnaLamports: minAnaLamports,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Buy ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Sell ANA tokens for USDC or NIRV
  /// Set useNirv=true to receive NIRV instead of USDC
  Future<TransactionResult> sellAna({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double anaAmount,
    double? minOutputAmount,
    bool useNirv = false,
  }) async {
    try {
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);

      // Validate accounts
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      if (useNirv && accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      if (!useNirv && accounts.usdcAccount == null) {
        throw Exception('User does not have USDC token account');
      }

      // Convert amount to lamports (6 decimals)
      final anaLamports = (anaAmount * 1000000).toInt();
      final minOutputLamports = minOutputAmount != null
          ? (minOutputAmount * 1000000).toInt()
          : 0;

      // Get destination account (NIRV or USDC)
      final destinationAccount = useNirv ? accounts.nirvAccount! : accounts.usdcAccount!;

      // Build sell instruction (sell2 - sells ANA for USDC or NIRV)
      final instruction = _transactionBuilder.buildSellInstruction(
        userPubkey: userPubkey,
        userAnaAccount: accounts.anaAccount!,
        userDestinationAccount: destinationAccount,
        anaLamports: anaLamports,
        minOutputLamports: minOutputLamports,
        useNirv: useNirv,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Sell ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Stake ANA tokens
  Future<TransactionResult> stakeAna({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double anaAmount,
  }) async {
    try {
      // Find personal account
      var personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        // Initialize personal account first
        personalAccount = await initializePersonalAccount(
          userPubkey: userPubkey,
          keypair: keypair,
        );
      }

      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }

      // Convert amount to lamports
      final anaLamports = (anaAmount * 1000000).toInt();

      // Build stake instruction
      final instruction = _transactionBuilder.buildDepositAnaInstruction(
        userPubkey: userPubkey,
        userAnaAccount: accounts.anaAccount!,
        personalAccount: personalAccount,
        anaLamports: anaLamports,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Stake ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Initialize personal account for staking
  Future<String> initializePersonalAccount({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
  }) async {
    // Derive personal account PDA
    // TODO: Implement proper PDA derivation
    const String tempPersonalAccount = 'TempPersonalAccountAddress'; // Placeholder
    
    final instruction = _transactionBuilder.buildInitPersonalAccountInstruction(
      userPubkey: userPubkey,
      personalAccount: tempPersonalAccount,
    );
    
    final message = Message(instructions: [instruction]);
    await _rpcClient.sendAndConfirmTransaction(
      message: message,
      signers: [keypair],
    );
    
    return tempPersonalAccount;
  }
  
  /// Borrow NIRV against staked ANA
  Future<TransactionResult> borrowNirv({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double nirvAmount,
  }) async {
    try {
      // Find personal account
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('PersonalAccount not found. You need to stake ANA first.');
      }
      
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      
      // Convert amount to lamports
      final nirvLamports = (nirvAmount * 1000000).toInt();
      
      // Build borrow instruction
      final instruction = _transactionBuilder.buildBorrowNirvInstruction(
        userPubkey: userPubkey,
        personalAccount: personalAccount,
        userNirvAccount: accounts.nirvAccount!,
        nirvLamports: nirvLamports,
      );
      
      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );
      
      return TransactionResult.success(
        signature: signature,
        logs: ['Borrow NIRV transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Unstake (withdraw) ANA tokens from staking position
  Future<TransactionResult> unstakeAna({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double anaAmount,
  }) async {
    try {
      // Find personal account (required for unstake)
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('PersonalAccount not found. You need to have staked tokens first.');
      }

      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }

      // Convert to lamports (ANA has 6 decimals)
      final anaLamports = (anaAmount * 1000000).toInt();

      // Build withdraw instruction
      final instruction = _transactionBuilder.buildWithdrawAnaInstruction(
        userPubkey: userPubkey,
        userAnaAccount: accounts.anaAccount!,
        personalAccount: personalAccount,
        anaLamports: anaLamports,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Unstake ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(signature: '', error: e.toString());
    }
  }
  
  /// Claim accumulated prANA rewards from staking
  /// Claims all available prANA - no amount parameter needed
  Future<TransactionResult> claimPrana({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
  }) async {
    try {
      // Find personal account
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('User does not have a personal account (must stake first)');
      }

      // Resolve user token accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.pranaAccount == null) {
        throw Exception('User does not have prANA token account');
      }

      // Build claim instruction
      final instruction = _transactionBuilder.buildClaimPranaInstruction(
        userPubkey: userPubkey,
        personalAccount: personalAccount,
        userPranaAccount: accounts.pranaAccount!,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Claim prANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }

  /// Claim accumulated revenue share (ANA + NIRV from protocol fees)
  /// Claims all available revenue - no amount parameter needed
  Future<TransactionResult> claimRevenueShare({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
  }) async {
    try {
      // Find personal account
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('User does not have a personal account (must stake first)');
      }

      // Resolve user token accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }

      // Build claim revenue share instruction
      final instruction = _transactionBuilder.buildClaimRevenueShareInstruction(
        userPubkey: userPubkey,
        personalAccount: personalAccount,
        userAnaAccount: accounts.anaAccount!,
        userNirvAccount: accounts.nirvAccount!,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Claim revenue share transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }

  /// Repay NIRV debt by burning NIRV tokens
  /// The NIRV is burned to reduce outstanding NIRV debt on the personal account
  Future<TransactionResult> repayNirv({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double nirvAmount,
  }) async {
    try {
      // Find personal account (required for repay)
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('User does not have a personal account. Cannot repay without borrowed position.');
      }

      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }

      // Convert to lamports (NIRV has 6 decimals)
      final nirvLamports = (nirvAmount * 1000000).toInt();

      // Build repay instruction - burns NIRV to reduce debt
      final instruction = _transactionBuilder.buildRepayInstruction(
        userPubkey: userPubkey,
        personalAccount: personalAccount,
        userNirvAccount: accounts.nirvAccount!,
        nirvLamports: nirvLamports,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Repay NIRV transaction successful - burned $nirvAmount NIRV'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Realize prANA tokens to ANA by paying with USDC or NIRV
  /// Converts prANA to ANA at current prices
  Future<TransactionResult> realizePrana({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double pranaAmount,
    bool useNirv = false,
  }) async {
    try {
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.pranaAccount == null) {
        throw Exception('User does not have prANA token account');
      }
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }

      // Check USDC account is needed when not using NIRV
      if (!useNirv && accounts.usdcAccount == null) {
        throw Exception('User does not have USDC token account');
      }

      // Convert to lamports (prANA has 6 decimals)
      final pranaLamports = (pranaAmount * 1000000).toInt();

      // Build realize instruction
      final instruction = _transactionBuilder.buildRealizeInstruction(
        userPubkey: userPubkey,
        userPranaAccount: accounts.pranaAccount!,
        userNirvAccount: accounts.nirvAccount!,
        userUsdcAccount: accounts.usdcAccount ?? '', // Only used when not useNirv
        userAnaAccount: accounts.anaAccount!,
        pranaLamports: pranaLamports,
        useNirv: useNirv,
      );

      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );

      return TransactionResult.success(
        signature: signature,
        logs: ['Realize prANA transaction successful - converted $pranaAmount prANA'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
}

class _PriceData {
  final double anaMarket;
  final double anaFloor;
  final double prana;

  _PriceData({
    required this.anaMarket,
    required this.anaFloor,
    required this.prana,
  });
}