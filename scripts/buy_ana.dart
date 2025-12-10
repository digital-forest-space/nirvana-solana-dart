import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:nirvana_solana/src/accounts/account_resolver.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

/// Execute a buy ANA transaction
///
/// Usage: dart scripts/buy_ana.dart <keypair_path> <amount> [--usdc|--nirv] [--rpc <url>]
///
/// Examples:
///   dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --nirv
///   dart scripts/buy_ana.dart ~/.config/solana/id.json 5 --usdc --rpc https://my-rpc.com
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/buy_ana.dart <keypair_path> <amount> [--usdc|--nirv] [--rpc <url>]');
    print('');
    print('Options:');
    print('  --nirv       Pay with NIRV (default)');
    print('  --usdc       Pay with USDC');
    print('  --rpc <url>  Custom RPC endpoint');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    print('');
    print('Examples:');
    print('  dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --nirv');
    print('  dart scripts/buy_ana.dart ~/.config/solana/id.json 5 --rpc https://my-rpc.com');
    exit(1);
  }

  final keypairPath = args[0];
  final amount = double.tryParse(args[1]);
  final useNirv = !args.any((a) => a.toLowerCase() == '--usdc');

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (amount == null || amount <= 0) {
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

  // Estimate ANA to receive (buy price is above floor)
  final paymentCurrency = useNirv ? 'NIRV' : 'USDC';
  final estimatedAna = amount / floorPrice;
  print('\nTransaction:');
  print('  Paying: $amount $paymentCurrency');
  print('  Estimated ANA: ${estimatedAna.toStringAsFixed(6)} ANA');

  // Execute buy
  print('\nExecuting buy transaction...');

  try {
    // Resolve user token accounts
    final accountResolver = NirvanaAccountResolver(rpcClient);
    final accounts = await accountResolver.resolveUserAccounts(userPubkey);

    // Validate accounts
    final paymentAccount = useNirv ? accounts.nirvAccount : accounts.usdcAccount;
    if (paymentAccount == null) {
      print('\n❌ Buy failed!');
      print('  Error: User does not have ${useNirv ? "NIRV" : "USDC"} token account');
      exit(1);
    }
    if (accounts.anaAccount == null) {
      print('\n❌ Buy failed!');
      print('  Error: User does not have ANA token account');
      exit(1);
    }
    if (accounts.nirvAccount == null) {
      print('\n❌ Buy failed!');
      print('  Error: User does not have NIRV token account');
      exit(1);
    }

    // Build buy instruction
    final transactionBuilder = NirvanaTransactionBuilder();
    final amountLamports = (amount * 1000000).toInt();
    final instruction = transactionBuilder.buildBuyExact2Instruction(
      userPubkey: userPubkey,
      userPaymentAccount: paymentAccount,
      userAnaAccount: accounts.anaAccount!,
      userNirvAccount: accounts.nirvAccount!,
      amountLamports: amountLamports,
      useNirv: useNirv,
    );

    // Create message and send transaction using SolanaClient directly
    final message = Message(instructions: [instruction]);
    final signature = await solanaClient.sendAndConfirmTransaction(
      message: message,
      signers: [keypair],
      commitment: Commitment.confirmed,
    );

    print('\n✅ Buy successful!');
    print('  Signature: $signature');
    print('  Explorer: https://solscan.io/tx/$signature');
  } catch (e) {
    print('\n❌ Buy failed!');
    print('  Error: $e');
  }
}
