import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a borrow NIRV transaction
///
/// Usage: dart scripts/borrow_nirv.dart <keypair_path> <nirv_amount> [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/borrow_nirv.dart ~/.config/solana/id.json 1.5
///   dart scripts/borrow_nirv.dart ~/.config/solana/id.json 1.5 --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)
///
/// Note: You must have staked ANA to borrow NIRV. Debt limit = stakedANA * floorPrice

void main(List<String> args) async {
  if (args.length < 2) {
    LogService.log('Usage: dart scripts/borrow_nirv.dart <keypair_path> <nirv_amount> [--rpc <url>] [--verbose]');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --rpc <url>  Custom RPC endpoint');
    LogService.log('  --verbose    Show detailed output before JSON result');
    LogService.log('');
    LogService.log('Environment:');
    LogService.log('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    LogService.log('');
    LogService.log('Note: You must have staked ANA to borrow NIRV.');
    exit(1);
  }

  final keypairPath = args[0];
  final nirvAmount = double.tryParse(args[1]);

  // Parse flags
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (nirvAmount == null || nirvAmount <= 0) {
    LogService.log(jsonEncode({'success': false, 'error': 'Invalid amount: ${args[1]}'}));
    exit(1);
  }

  // Load keypair
  final keypairFile = File(keypairPath);
  if (!keypairFile.existsSync()) {
    LogService.log(jsonEncode({'success': false, 'error': 'Keypair file not found: $keypairPath'}));
    exit(1);
  }

  if (verbose) LogService.log('Loading keypair from $keypairPath...');
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  if (verbose) LogService.log('Wallet: $userPubkey');

  // Create client
  if (verbose) LogService.log('RPC: $rpcUrl');
  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  // Show current prices
  if (verbose) LogService.log('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  if (verbose) {
    LogService.log('  Floor price: \$${floorPrice.toStringAsFixed(6)}');
    LogService.log('\nTransaction:');
    LogService.log('  Borrowing: $nirvAmount NIRV');
    LogService.log('\nExecuting borrow transaction...');
  }

  // Execute borrow
  final result = await client.borrowNirv(
    userPubkey: userPubkey,
    keypair: keypair,
    nirvAmount: nirvAmount,
  );

  if (result.success) {
    if (verbose) {
      LogService.log('\n✅ Borrow successful!');
      LogService.log('  Signature: ${result.signature}');
      LogService.log('  Explorer: https://solscan.io/tx/${result.signature}');
      LogService.log('\nParsing transaction...');
    }

    // Parse the transaction
    try {
      final tx = await client.parseTransaction(result.signature);
      if (verbose) {
        LogService.log('  Type: ${tx.type.name.toUpperCase()}');
        for (final r in tx.received) {
          LogService.log('  Borrowed: ${r.amount.toStringAsFixed(6)} ${r.currency}');
        }
        LogService.log('');
      }

      // Output JSON result
      LogService.log(jsonEncode(tx.toJson()));
    } catch (e) {
      LogService.log(jsonEncode({
        'success': true,
        'signature': result.signature,
        'parseError': e.toString(),
        'explorer': 'https://solscan.io/tx/${result.signature}',
      }));
    }
  } else {
    if (verbose) {
      LogService.log('\n❌ Borrow failed!');
      LogService.log('  Error: ${result.error}');
    }
    LogService.log(jsonEncode({'success': false, 'error': result.error}));
    exit(1);
  }
}
