import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a repay NIRV debt transaction (burns ANA to repay debt)
///
/// Usage: dart scripts/repay_ana.dart <keypair_path> <ana_amount> [--rpc <url>]
///
/// Examples:
///   dart scripts/repay_ana.dart ~/.config/solana/id.json 2.0
///   dart scripts/repay_ana.dart ~/.config/solana/id.json 2.0 --rpc https://my-rpc.com
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/repay_ana.dart <keypair_path> <ana_amount> [--rpc <url>]');
    print('');
    print('This burns ANA to repay outstanding NIRV debt on your personal account.');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    print('');
    print('Examples:');
    print('  dart scripts/repay_ana.dart ~/.config/solana/id.json 2.0');
    exit(1);
  }

  final keypairPath = args[0];
  final anaAmount = double.tryParse(args[1]);

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (anaAmount == null || anaAmount <= 0) {
    print('Error: Invalid amount: ${args[1]}');
    exit(1);
  }

  // Load keypair
  final keypairFile = File(keypairPath);
  if (!keypairFile.existsSync()) {
    print('Error: Keypair file not found: $keypairPath');
    exit(1);
  }

  print('Loading keypair from $keypairPath...');
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  print('Wallet: $userPubkey');

  // Create client using rpcUrl from args/env (parsed above)
  print('RPC: $rpcUrl');
  final solanaClient = SolanaClient(rpcUrl: Uri.parse(rpcUrl), websocketUrl: Uri.parse(rpcUrl.replaceFirst('https', 'wss')));
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: Uri.parse(rpcUrl));
  final client = NirvanaClient(rpcClient: rpcClient);

  // Show current prices
  print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Estimate debt repayment value
  final repayValue = anaAmount * floorPrice;
  print('\nTransaction:');
  print('  Burning: $anaAmount ANA');
  print('  Debt repaid: ~\$${repayValue.toStringAsFixed(6)} worth of NIRV');

  // Execute repay
  print('\nExecuting repay transaction...');
  final result = await client.repayNirv(
    userPubkey: userPubkey,
    keypair: keypair,
    anaAmount: anaAmount,
  );

  if (result.success) {
    print('\n✅ Repay successful!');
    print('  Signature: ${result.signature}');
    print('  Explorer: https://solscan.io/tx/${result.signature}');

    // Parse the transaction to show actual amounts (with retry)
    print('\nParsing transaction...');
    try {
      final tx = await client.parseTransaction(result.signature);
      print('  Type: ${tx.type.name.toUpperCase()}');
      if (tx.spent != null) {
        print('  Burned: ${tx.spent!.amount.toStringAsFixed(6)} ${tx.spent!.currency}');
      }
    } catch (e) {
      print('  (Could not parse transaction: $e)');
    }
  } else {
    print('\n❌ Repay failed!');
    print('  Error: ${result.error}');
  }
}
