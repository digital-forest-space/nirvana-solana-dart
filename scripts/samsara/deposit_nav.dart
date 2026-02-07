import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Deposit navToken into a Mayflower market's personal position escrow
///
/// Usage: dart scripts/samsara/deposit_nav.dart <keypair_path> <amount> [--market <name>] [--rpc <url>] [--verbose] [--dry-run]
///
/// Examples:
///   dart scripts/samsara/deposit_nav.dart ~/.config/solana/id.json 1.0
///   dart scripts/samsara/deposit_nav.dart ~/.config/solana/id.json 0.5 --market navSOL --verbose
///   dart scripts/samsara/deposit_nav.dart ~/.config/solana/id.json 0.1 --dry-run
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    LogService.log('Usage: dart scripts/samsara/deposit_nav.dart <keypair_path> <amount> [options]');
    LogService.log('');
    LogService.log('Deposits navToken (e.g., navSOL) from your wallet into the market escrow.');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --market <name>  Market to deposit to (default: navSOL)');
    LogService.log('  --rpc <url>      Custom RPC endpoint');
    LogService.log('  --verbose        Show detailed output before JSON result');
    LogService.log('  --dry-run        Build transaction but don\'t send');
    LogService.log('');
    LogService.log('Markets: ${NavTokenMarket.availableMarkets.join(', ')}');
    LogService.log('');
    LogService.log('Environment:');
    LogService.log('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final amount = double.tryParse(args[1]);

  // Parse flags
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');
  final dryRun = args.any((a) => a.toLowerCase() == '--dry-run');

  // Parse market name
  String marketName = 'navSOL';
  final marketIndex = args.indexWhere((a) => a.toLowerCase() == '--market');
  if (marketIndex >= 0 && marketIndex + 1 < args.length) {
    marketName = args[marketIndex + 1];
  }

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

  // Resolve market
  final market = NavTokenMarket.byName(marketName);
  if (market == null) {
    LogService.log(jsonEncode({
      'success': false,
      'error': 'Unknown market: $marketName. Available: ${NavTokenMarket.availableMarkets.join(', ')}',
    }));
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

  // Create SamsaraClient
  if (verbose) LogService.log('RPC: $rpcUrl');
  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
  final client = SamsaraClient(rpcClient: rpcClient);

  final lamports = (amount * _pow10(market.navDecimals)).toInt();

  if (verbose) {
    LogService.log('\nDeposit:');
    LogService.log('  Amount: $amount ${market.name} ($lamports lamports)');
    LogService.log('  Market: ${market.name}');
  }

  // Get recent blockhash
  final blockhash = await rpcClient.getLatestBlockhash();
  if (verbose) LogService.log('  Blockhash: $blockhash');

  // Build unsigned transaction via SamsaraClient
  if (verbose) LogService.log('\nBuilding transaction...');
  final unsignedTxBytes = await client.buildUnsignedDepositNavTokenTransaction(
    userPubkey: userPubkey,
    market: market,
    depositLamports: lamports,
    recentBlockhash: blockhash,
  );

  if (dryRun) {
    if (verbose) LogService.log('\nDry run - transaction not sent');

    final txBase64 = base64Encode(unsignedTxBytes);
    LogService.log(jsonEncode({
      'success': true,
      'dryRun': true,
      'transaction': txBase64,
      'market': market.name,
      'depositAmount': amount,
      'depositLamports': lamports,
      'navToken': market.name,
    }));
    return;
  }

  // Sign and send transaction
  if (verbose) LogService.log('\nSigning and sending transaction...');

  try {
    final signedTxBytes = await _signTransaction(unsignedTxBytes, keypair);

    final signature = await solanaClient.rpcClient.sendTransaction(
      base64Encode(signedTxBytes),
      preflightCommitment: Commitment.confirmed,
    );

    if (verbose) {
      LogService.log('\nTransaction sent!');
      LogService.log('  Signature: $signature');
      LogService.log('  Explorer: https://solscan.io/tx/$signature');
    }

    LogService.log(jsonEncode({
      'success': true,
      'signature': signature,
      'market': market.name,
      'depositAmount': amount,
      'depositLamports': lamports,
      'navToken': market.name,
      'explorer': 'https://solscan.io/tx/$signature',
    }));
  } catch (e) {
    if (verbose) {
      LogService.log('\nTransaction failed!');
      LogService.log('  Error: $e');
    }
    LogService.log(jsonEncode({
      'success': false,
      'error': e.toString(),
    }));
    exit(1);
  }
}

double _pow10(int n) {
  double result = 1.0;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

/// Sign an unsigned transaction
Future<Uint8List> _signTransaction(Uint8List unsignedTxBytes, Ed25519HDKeyPair keypair) async {
  final numSignatures = unsignedTxBytes[0];
  final messageOffset = 1 + (numSignatures * 64);
  final messageBytes = unsignedTxBytes.sublist(messageOffset);

  final signature = await keypair.sign(messageBytes);

  final signedTx = BytesBuilder();
  signedTx.addByte(numSignatures);
  signedTx.add(signature.bytes);

  for (var i = 1; i < numSignatures; i++) {
    signedTx.add(unsignedTxBytes.sublist(1 + (i * 64), 1 + ((i + 1) * 64)));
  }

  signedTx.add(messageBytes);

  return Uint8List.fromList(signedTx.toBytes());
}
