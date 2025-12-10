import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Borrow NIRV against staked ANA collateral
///
/// Usage: dart scripts/borrow_nirv.dart <keypair_path> <nirv_amount> [--rpc <url>]
///
/// Examples:
///   dart scripts/borrow_nirv.dart ~/.config/solana/id.json 1.0
///   dart scripts/borrow_nirv.dart ~/.config/solana/id.json 1.0 --rpc https://my-rpc.com
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/borrow_nirv.dart <keypair_path> <nirv_amount> [--rpc <url>]');
    print('');
    print('Borrow NIRV tokens against your staked ANA collateral.');
    print('Requires an existing PersonalAccount with staked ANA.');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    print('');
    print('Examples:');
    print('  dart scripts/borrow_nirv.dart ~/.config/solana/id.json 1.0');
    exit(1);
  }

  final keypairPath = args[0];
  final nirvAmount = double.tryParse(args[1]);

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (nirvAmount == null || nirvAmount <= 0) {
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
  final rpcClient = DefaultSolanaRpcClient(solanaClient);
  final client = NirvanaClient(rpcClient: rpcClient);

  // Show current prices
  print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Show transaction details
  print('\nTransaction:');
  print('  Borrowing: $nirvAmount NIRV');
  print('  Collateral required: ~${(nirvAmount / floorPrice).toStringAsFixed(6)} ANA (at floor price)');

  // Confirm
  print('\nProceed with borrow? (y/n): ');
  final confirm = stdin.readLineSync()?.toLowerCase();
  if (confirm != 'y' && confirm != 'yes') {
    print('Cancelled.');
    exit(0);
  }

  // Execute borrow
  print('\nExecuting borrow transaction...');
  final result = await client.borrowNirv(
    userPubkey: userPubkey,
    keypair: keypair,
    nirvAmount: nirvAmount,
  );

  if (result.success) {
    print('\n✅ Borrow successful!');
    print('  Signature: ${result.signature}');
    print('  Explorer: https://solscan.io/tx/${result.signature}');
  } else {
    print('\n❌ Borrow failed!');
    print('  Error: ${result.error}');
  }
}
