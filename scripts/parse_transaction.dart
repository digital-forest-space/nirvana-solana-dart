import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Parse a Nirvana transaction to show type, amounts, and price
///
/// Usage: dart scripts/parse_transaction.dart <signature> [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/parse_transaction.dart 5abc...xyz
///   dart scripts/parse_transaction.dart 5abc...xyz --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart scripts/parse_transaction.dart <signature> [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final signature = args[0];

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

  if (verbose) print('\nParsing transaction: $signature');

  try {
    final tx = await client.parseTransaction(signature);

    if (verbose) {
      print('');
      print('  Type: ${tx.type.name.toUpperCase()}');
      if (tx.sent != null) print('  Sent: ${tx.sent!.amount.toStringAsFixed(6)} ${tx.sent!.currency}');
      if (tx.received != null) print('  Received: ${tx.received!.amount.toStringAsFixed(6)} ${tx.received!.currency}');
      if (tx.fee != null) print('  Fee: ${tx.fee!.amount.toStringAsFixed(6)} ${tx.fee!.currency}');
      if (tx.pricePerAna != null) print('  Price: \$${tx.pricePerAna!.toStringAsFixed(6)} per ANA');
      print('  Timestamp: ${tx.timestamp.toIso8601String()}');
      print('  User: ${tx.userAddress}');
      print('');
    }

    // Output JSON result
    print(jsonEncode(tx.toJson()));
  } catch (e) {
    if (verbose) {
      print('\n❌ Failed to parse transaction!');
      print('  Error: $e');
    }
    print(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }
}
