import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a buy ANA transaction
///
/// Usage: dart scripts/buy_ana.dart <keypair_path> <amount> [--nirv|--usdc] [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --nirv
///   dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --usdc --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    LogService.log('Usage: dart scripts/buy_ana.dart <keypair_path> <amount> [--nirv|--usdc] [--rpc <url>] [--verbose]');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --nirv       Pay with NIRV (default)');
    LogService.log('  --usdc       Pay with USDC');
    LogService.log('  --rpc <url>  Custom RPC endpoint');
    LogService.log('  --verbose    Show detailed output before JSON result');
    LogService.log('');
    LogService.log('Environment:');
    LogService.log('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final amount = double.tryParse(args[1]);

  // Parse flags - default to NIRV if neither specified
  final useUsdc = args.any((a) => a.toLowerCase() == '--usdc');
  final useNirv = !useUsdc;
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');
  final paymentCurrency = useNirv ? 'NIRV' : 'USDC';

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (amount == null || amount <= 0) {
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
  if (verbose) LogService.log('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Estimate ANA to receive
  final estimatedAna = amount / floorPrice * 0.97;
  if (verbose) {
    LogService.log('\nTransaction:');
    LogService.log('  Spending: $amount $paymentCurrency');
    LogService.log('  Estimated ANA: ${estimatedAna.toStringAsFixed(6)} ANA (after ~3% fee)');
    LogService.log('\nExecuting buy transaction...');
  }

  // Execute buy
  final result = await client.buyAna(
    userPubkey: userPubkey,
    keypair: keypair,
    amount: amount,
    useNirv: useNirv,
  );

  if (result.success) {
    if (verbose) {
      LogService.log('\n✅ Buy successful!');
      LogService.log('  Signature: ${result.signature}');
      LogService.log('  Explorer: https://solscan.io/tx/${result.signature}');
      LogService.log('\nParsing transaction...');
    }

    // Parse the transaction
    try {
      final tx = await client.parseTransaction(result.signature);
      if (verbose) {
        LogService.log('  Type: ${tx.type.name.toUpperCase()}');
        for (final s in tx.sent) {
          LogService.log('  Sent: ${s.amount.toStringAsFixed(6)} ${s.currency}');
        }
        for (final r in tx.received) {
          LogService.log('  Received: ${r.amount.toStringAsFixed(6)} ${r.currency}');
        }
        if (tx.fee != null) LogService.log('  Fee: ${tx.fee!.amount.toStringAsFixed(6)} ${tx.fee!.currency}');
        if (tx.pricePerAna != null) LogService.log('  Price: \$${tx.pricePerAna!.toStringAsFixed(6)} per ANA');
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
      LogService.log('\n❌ Buy failed!');
      LogService.log('  Error: ${result.error}');
    }
    LogService.log(jsonEncode({'success': false, 'error': result.error}));
    exit(1);
  }
}
