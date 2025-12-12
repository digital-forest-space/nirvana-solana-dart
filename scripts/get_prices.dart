import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

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
  final solanaClient = SolanaClient(rpcUrl: Uri.parse(rpcUrl), websocketUrl: Uri.parse(rpcUrl.replaceFirst('https', 'wss')));
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: Uri.parse(rpcUrl));
  final client = NirvanaClient(rpcClient: rpcClient);

  try {
    if (verbose) print('\nFetching prices...');

    final prices = await client.fetchPrices();

    if (verbose) {
      print('  Floor: \$${prices.floor.toStringAsFixed(6)}');
      print('  ANA:   \$${prices.ana.toStringAsFixed(6)}');
      print('  prANA: \$${prices.prana.toStringAsFixed(6)}');
      print('');
    }

    // Output JSON result
    print(jsonEncode(prices.toJson()));
  } catch (e) {
    if (verbose) {
      print('\n❌ Failed to fetch prices!');
      print('  Error: $e');
    }
    print(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }
}
