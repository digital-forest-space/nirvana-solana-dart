import 'dart:io';
import 'dart:convert';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:nirvana_solana/src/accounts/account_resolver.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

/// Debug script to compare instruction building

void main() async {
  final keypairPath = 'PATH_TO_YOUR_KEYPAIR_FILE';

  // Load keypair
  final keypairFile = File(keypairPath);
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  print('Wallet: $userPubkey');

  // Create client
  const rpcUrl = 'https://api.mainnet-beta.solana.com';
  final solanaClient = SolanaClient(rpcUrl: Uri.parse(rpcUrl), websocketUrl: Uri.parse(rpcUrl.replaceFirst('https', 'wss')));
  final rpcClient = DefaultSolanaRpcClient(solanaClient);

  // Resolve accounts
  final accountResolver = NirvanaAccountResolver(rpcClient);
  final accounts = await accountResolver.resolveUserAccounts(userPubkey);

  print('Accounts:');
  print('  ANA: ${accounts.anaAccount}');
  print('  NIRV: ${accounts.nirvAccount}');
  print('  USDC: ${accounts.usdcAccount}');

  // Build instruction using library
  final transactionBuilder = NirvanaTransactionBuilder();
  final instruction = transactionBuilder.buildBuyExact2Instruction(
    userPubkey: userPubkey,
    userPaymentAccount: accounts.nirvAccount!,
    userAnaAccount: accounts.anaAccount!,
    userNirvAccount: accounts.nirvAccount!,
    amountLamports: 100000, // 0.1 NIRV
    useNirv: true,
  );

  print('\nInstruction details:');
  print('  Program ID: ${instruction.programId.toBase58()}');
  print('  Accounts (${instruction.accounts.length}):');
  for (int i = 0; i < instruction.accounts.length; i++) {
    final acc = instruction.accounts[i];
    print('    [$i] ${acc.pubKey.toBase58()} (signer: ${acc.isSigner}, writable: ${acc.isWriteable})');
  }
  print('  Data length: ${instruction.data.length} bytes');
  print('  Data (hex): ${instruction.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Create message
  final message = Message(instructions: [instruction]);
  print('\nMessage created with ${message.instructions.length} instruction(s)');

  // Try to send
  print('\nAttempting to send transaction...');
  try {
    final signature = await solanaClient.sendAndConfirmTransaction(
      message: message,
      signers: [keypair],
      commitment: Commitment.confirmed,
    );
    print('Success! Signature: $signature');
  } catch (e) {
    print('Error: $e');

    // Try with simulation first
    print('\nTrying simulation...');
    try {
      // We can't easily simulate here, but let's see if the error gives more info
    } catch (e2) {
      print('Simulation error: $e2');
    }
  }
}
