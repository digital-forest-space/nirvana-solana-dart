import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Unstake (withdraw) ANA tokens from staking position
///
/// Usage: dart scripts/unstake_ana.dart <keypair_path> <ana_amount> [--rpc <url>]
///
/// Examples:
///   dart scripts/unstake_ana.dart ~/.config/solana/id.json 1.0
///   dart scripts/unstake_ana.dart ~/.config/solana/id.json 1.0 --rpc https://my-rpc.com
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/unstake_ana.dart <keypair_path> <ana_amount> [--rpc <url>]');
    print('');
    print('Withdraw ANA tokens from your staking position.');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    print('');
    print('Examples:');
    print('  dart scripts/unstake_ana.dart ~/.config/solana/id.json 1.0');
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
  final rpcClient = DefaultSolanaRpcClient(solanaClient);
  final client = NirvanaClient(rpcClient: rpcClient);

  // Show current prices
  print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Show transaction details
  final unstakeValue = anaAmount * floorPrice;
  print('\nTransaction:');
  print('  Unstaking: $anaAmount ANA');
  print('  Value: ~\$${unstakeValue.toStringAsFixed(2)} (at floor price)');

  // Execute unstake
  print('\nExecuting unstake transaction...');
  final result = await client.unstakeAna(
    userPubkey: userPubkey,
    keypair: keypair,
    anaAmount: anaAmount,
  );

  if (result.success) {
    print('\n✅ Unstake successful!');
    print('  Signature: ${result.signature}');
    print('  Explorer: https://solscan.io/tx/${result.signature}');
  } else {
    print('\n❌ Unstake failed!');
    print('  Error: ${result.error}');
  }
}
