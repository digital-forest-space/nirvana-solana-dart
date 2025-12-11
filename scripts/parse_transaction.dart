import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Parse a Nirvana transaction and display details
///
/// Usage: dart scripts/parse_transaction.dart <signature> [--rpc <url>]
///
/// Examples:
///   dart scripts/parse_transaction.dart 5Yao821gczjpJSqMdaQhc7h5nHkX1vwHeUAnAQNJZPVHiuAhQievX57Wr378bLQnrTRZqFamFndmcHSAvLQx97J7
///   dart scripts/parse_transaction.dart <signature> --rpc https://my-rpc.com

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart scripts/parse_transaction.dart <signature> [--rpc <url>]');
    print('');
    print('Parse a Nirvana protocol transaction to show:');
    print('  - Transaction type (buy, sell, stake, unstake, borrow, repay, realize)');
    print('  - Amount received');
    print('  - Amount spent');
    print('  - Timestamp');
    print('  - User address');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final signature = args[0];

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  print('Parsing Nirvana transaction...');
  print('  Signature: $signature');
  print('  RPC: $rpcUrl');
  print('');

  // Create client
  final solanaClient = SolanaClient(
    rpcUrl: Uri.parse(rpcUrl),
    websocketUrl: Uri.parse(rpcUrl.replaceFirst('https', 'wss')),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: Uri.parse(rpcUrl));
  final client = NirvanaClient(rpcClient: rpcClient);

  try {
    final tx = await client.parseTransaction(signature);

    print('Transaction Details:');
    print('  Type: ${tx.type.name.toUpperCase()}');
    print('  Timestamp: ${tx.timestamp.toIso8601String()}');
    print('  User: ${tx.userAddress}');
    print('');

    if (tx.spent != null) {
      print('  Spent: ${tx.spent!.amount.toStringAsFixed(6)} ${tx.spent!.currency}');
    }
    if (tx.received != null) {
      print('  Received: ${tx.received!.amount.toStringAsFixed(6)} ${tx.received!.currency}');
    }

    final price = tx.pricePerAna;
    if (price != null) {
      print('');
      print('  Price per ANA: \$${price.toStringAsFixed(6)}');
    }

    print('');
    print('Explorer: https://solscan.io/tx/$signature');
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
