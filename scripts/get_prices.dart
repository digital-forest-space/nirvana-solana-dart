import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';

/// Fetch current Nirvana token prices
///
/// Usage: dart scripts/get_prices.dart [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/get_prices.dart
///   dart scripts/get_prices.dart --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  // Parse flags
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');

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
    if (verbose) print('\nFetching prices...');

    NirvanaPrices prices;

    if (verbose) {
      // Measure individual calls in parallel
      final floorStart = DateTime.now();
      final anaStart = DateTime.now();

      final results = await Future.wait([
        client.fetchFloorPrice().then((r) {
          final elapsed = DateTime.now().difference(floorStart).inMilliseconds;
          print('  fetchFloorPrice: ${elapsed}ms');
          return r;
        }),
        client.fetchLatestAnaPrice().then((r) {
          final elapsed = DateTime.now().difference(anaStart).inMilliseconds;
          print('  fetchLatestAnaPrice: ${elapsed}ms');
          return r;
        }),
      ]);

      final floor = results[0] as double;
      final transactionPrice = results[1] as TransactionPriceResult;
      final ana = transactionPrice.price;
      final prana = ana - floor;

      prices = NirvanaPrices(
        ana: ana,
        floor: floor,
        prana: prana,
        updatedAt: DateTime.now().toUtc(),
      );

      final totalElapsed = DateTime.now().difference(totalStart).inMilliseconds;
      print('  Total: ${totalElapsed}ms');
      print('');
      print('  Floor: \$${prices.floor.toStringAsFixed(6)}');
      print('  ANA:   \$${prices.ana.toStringAsFixed(6)}');
      print('  prANA: \$${prices.prana.toStringAsFixed(6)}');
      print('');
    } else {
      prices = await client.fetchPrices();
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
