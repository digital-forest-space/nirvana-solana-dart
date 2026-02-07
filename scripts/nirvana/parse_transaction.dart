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
    LogService.log('Usage: dart scripts/parse_transaction.dart <signature> [--rpc <url>] [--verbose]');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --rpc <url>  Custom RPC endpoint');
    LogService.log('  --verbose    Show detailed output before JSON result');
    LogService.log('');
    LogService.log('Environment:');
    LogService.log('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
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
  if (verbose) LogService.log('RPC: $rpcUrl');
  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  if (verbose) LogService.log('\nParsing transaction: $signature');

  try {
    final tx = await client.parseTransaction(signature);

    if (verbose) {
      LogService.log('');
      LogService.log('  Type: ${tx.type.name.toUpperCase()}');
      for (final s in tx.sent) {
        LogService.log('  Sent: ${s.amount.toStringAsFixed(6)} ${s.currency}');
      }
      for (final r in tx.received) {
        LogService.log('  Received: ${r.amount.toStringAsFixed(6)} ${r.currency}');
      }
      if (tx.fee != null) LogService.log('  Fee: ${tx.fee!.amount.toStringAsFixed(6)} ${tx.fee!.currency}');
      if (tx.pricePerAna != null) LogService.log('  Price: \$${tx.pricePerAna!.toStringAsFixed(6)} per ANA');
      LogService.log('  Timestamp: ${tx.timestamp.toIso8601String()}');
      LogService.log('  User: ${tx.userAddress}');
      LogService.log('');
    }

    // Output JSON result
    LogService.log(jsonEncode(tx.toJson()));
  } catch (e) {
    if (verbose) {
      LogService.log('\n❌ Failed to parse transaction!');
      LogService.log('  Error: $e');
    }
    LogService.log(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }
}
