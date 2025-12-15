import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';

/// Fetch current Nirvana token prices with caching and pagination
///
/// Usage: dart scripts/get_prices.dart [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/get_prices.dart
///   dart scripts/get_prices.dart --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)
///
/// Caching:
///   Stores last result in /tmp/nirvana_price_cache.json
///   Uses cached signature to skip already-checked transactions
///   Pages through transactions if no buy/sell found in batch
///
/// Pagination options:
///   --max-pages <n>    Maximum pages to check (default: 10)
///   --page-size <n>    Signatures to fetch and parse per page (default: 20)

const _cacheFile = '/tmp/nirvana_price_cache.json';

int _parseIntArg(List<String> args, String flag, int defaultValue) {
  final index = args.indexWhere((a) => a.toLowerCase() == flag);
  if (index >= 0 && index + 1 < args.length) {
    return int.tryParse(args[index + 1]) ?? defaultValue;
  }
  return defaultValue;
}

void main(List<String> args) async {
  // Parse flags
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');
  final maxPages = _parseIntArg(args, '--max-pages', 10);
  final pageSize = _parseIntArg(args, '--page-size', 20);

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  // Create client
  if (verbose) print('RPC: $rpcUrl');
  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  final totalStart = DateTime.now();

  try {
    // Load cache
    Map<String, dynamic>? cache;
    final cacheFileObj = File(_cacheFile);
    if (cacheFileObj.existsSync()) {
      try {
        cache = jsonDecode(cacheFileObj.readAsStringSync()) as Map<String, dynamic>;
        if (verbose) {
          print('Cache: loaded from $_cacheFile');
          print('  cached signature: ${cache['signature']}');
          print('  cached price: \$${cache['price']}');
        }
      } catch (e) {
        if (verbose) print('Cache: failed to load ($e)');
      }
    } else {
      if (verbose) print('Cache: none found');
    }

    if (verbose) print('\nFetching prices...');

    // Fetch floor price (always needed)
    final floorStart = DateTime.now();
    final floor = await client.fetchFloorPrice();
    if (verbose) {
      final elapsed = DateTime.now().difference(floorStart).inMilliseconds;
      print('  fetchFloorPrice: ${elapsed}ms');
    }

    // Fetch ANA price with pagination
    final anaStart = DateTime.now();
    double? anaPrice;
    String? newCachedSignature;
    late TransactionPriceResult result;

    // Start with afterSignature from cache (only fetch newer transactions)
    final cachedSignature = cache?['signature'] as String?;

    if (verbose) {
      // Verbose mode: use single-page method with manual paging loop
      // This demonstrates progress reporting for apps that need it
      String? afterSignature = cachedSignature;
      String? beforeSignature;

      for (var page = 1; page <= maxPages; page++) {
        stdout.write('  page $page/$maxPages: ');

        result = await client.fetchLatestAnaPrice(
          afterSignature: afterSignature,
          beforeSignature: beforeSignature,
          pageSize: pageSize,
        );

        print('${result.status.name}${result.signature != null ? ' (${result.signature!.substring(0, 8)}...)' : ''}');

        if (result.status != PriceResultStatus.limitReached) {
          break;
        }

        // Page deeper
        beforeSignature = result.signature;
        afterSignature = null; // Clear after first page
      }

      final elapsed = DateTime.now().difference(anaStart).inMilliseconds;
      print('  fetchLatestAnaPrice: ${elapsed}ms');
    } else {
      // Non-verbose: use convenience method that handles paging internally
      result = await client.fetchLatestAnaPriceWithPaging(
        afterSignature: cachedSignature,
        maxPages: maxPages,
        pageSize: pageSize,
      );
    }

    switch (result.status) {
      case PriceResultStatus.found:
        anaPrice = result.price;
        newCachedSignature = result.signature;
        break;

      case PriceResultStatus.reachedAfterLimit:
        // No new transactions since cache - cached price is still current
        if (cache != null && cache['price'] != null) {
          anaPrice = cache['price'] as double;
          newCachedSignature = cache['signature'] as String?;
          if (verbose) print('  -> no new transactions, cached price is current');
        }
        break;

      case PriceResultStatus.limitReached:
        // Exhausted all pages - try cached price as fallback
        if (cache != null && cache['price'] != null) {
          anaPrice = cache['price'] as double;
          newCachedSignature = cache['signature'] as String?;
          if (verbose) print('  -> exhausted $maxPages pages, using cached price');
        }
        break;

      case PriceResultStatus.error:
        throw Exception(result.errorMessage ?? 'Unknown error');
    }

    if (anaPrice == null) {
      throw Exception('No price found after $maxPages pages, and no cache available');
    }

    final prana = anaPrice - floor;

    final prices = NirvanaPrices(
      ana: anaPrice,
      floor: floor,
      prana: prana,
      updatedAt: DateTime.now().toUtc(),
    );

    // Save cache (full result object for debugging)
    final newCache = {
      'signature': newCachedSignature,
      'price': anaPrice,
      'floor': floor,
      'prana': prana,
      'status': result.status.name,
      'fee': result.fee,
      'currency': result.currency,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    cacheFileObj.writeAsStringSync(jsonEncode(newCache));
    if (verbose) print('  Cache: saved to $_cacheFile');

    if (verbose) {
      final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
      print('  Total: ${totalElapsed}ms');
      print('');
      print('  Floor: \$${prices.floor.toStringAsFixed(6)}');
      print('  ANA:   \$${prices.ana.toStringAsFixed(6)}');
      print('  prANA: \$${prices.prana.toStringAsFixed(6)}');
      print('');
    }

    // Output JSON result
    print(jsonEncode(prices.toJson()));
  } catch (e) {
    if (verbose) {
      final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
      print('\n❌ Failed to fetch prices! (${totalElapsed}ms)');
      print('  Error: $e');
    }
    print(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }
}
