import 'dart:convert';
import 'dart:typed_data';

import '../models/transaction_price_result.dart';
import '../rpc/solana_rpc_client.dart';
import 'config.dart';

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
}
