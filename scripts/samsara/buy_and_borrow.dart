import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Atomic buy navToken + borrow max base token in a single transaction
///
/// Usage: dart scripts/samsara/buy_and_borrow.dart <keypair_path> <buy_amount> [options]
///
/// Automatically borrows the maximum amount based on the estimated navToken
/// output (using floor price as conservative estimate).
///
/// Examples:
///   dart scripts/samsara/buy_and_borrow.dart ~/.config/solana/id.json 1.0
///   dart scripts/samsara/buy_and_borrow.dart ~/.config/solana/id.json 1.0 --market navSOL --verbose
///   dart scripts/samsara/buy_and_borrow.dart ~/.config/solana/id.json 2.0 --dry-run
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    LogService.log('Usage: dart scripts/samsara/buy_and_borrow.dart <keypair_path> <buy_amount> [options]');
    LogService.log('');
    LogService.log('Buys navToken and borrows the maximum base token in a single atomic transaction.');
    LogService.log('Borrow amount is automatically calculated from the estimated navToken output');
    LogService.log('using the floor price (conservative — actual output is typically higher).');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --market <name>  Market (default: navSOL)');
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
  final buyAmount = double.tryParse(args[1]);

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

  if (buyAmount == null || buyAmount <= 0) {
    LogService.log(jsonEncode({'success': false, 'error': 'Invalid buy amount: ${args[1]}'}));
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

  // Fetch floor price and market price
  if (verbose) LogService.log('\nFetching floor price and market price...');
  final floorPrice = await client.fetchFloorPrice(market);

  final priceResult = await client.fetchLatestNavTokenPriceWithPaging(market);
  if (priceResult.price == null) {
    LogService.log(jsonEncode({
      'success': false,
      'error': 'Could not fetch market price for ${market.name}',
    }));
    exit(1);
  }
  final marketPrice = priceResult.price!;

  // Estimate borrow capacity from this purchase
  final estimate = SamsaraClient.estimateBorrowCapacityAfterBuy(
    inputBaseAmount: buyAmount,
    marketPrice: marketPrice,
    floorPrice: floorPrice,
  );

  final borrowAmount = estimate['borrowLimit']!;

  if (verbose) {
    LogService.log('\nPrices:');
    LogService.log('  Market: $marketPrice ${market.baseName}/${market.name}');
    LogService.log('  Floor:  $floorPrice ${market.baseName}/${market.name}');
    LogService.log('\nEstimate for $buyAmount ${market.baseName} buy:');
    LogService.log('  Est. navTokens: ${estimate['estimatedNavTokens']!.toStringAsFixed(6)} ${market.name}');
    LogService.log('  Max borrow:     ${borrowAmount.toStringAsFixed(6)} ${market.baseName}');
  }

  if (borrowAmount <= 0) {
    LogService.log(jsonEncode({
      'success': false,
      'error': 'No borrow capacity (floor price is zero)',
    }));
    exit(1);
  }

  final buyLamports = (buyAmount * _pow10(market.baseDecimals)).toInt();
  final borrowLamports = (borrowAmount * _pow10(market.baseDecimals)).toInt();

  if (verbose) {
    LogService.log('\nTransaction:');
    LogService.log('  Buy:    $buyAmount ${market.baseName} ($buyLamports lamports)');
    LogService.log('  Borrow: ${borrowAmount.toStringAsFixed(market.baseDecimals)} ${market.baseName} ($borrowLamports lamports)');
    LogService.log('  Market: ${market.name}');
  }

  // Get recent blockhash
  final blockhash = await rpcClient.getLatestBlockhash();
  if (verbose) LogService.log('  Blockhash: $blockhash');

  // Build unsigned transaction via SamsaraClient
  if (verbose) LogService.log('\nBuilding transaction...');
  final unsignedTxBytes = await client.buildUnsignedBuyAndBorrowTransaction(
    userPubkey: userPubkey,
    market: market,
    inputLamports: buyLamports,
    borrowLamports: borrowLamports,
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
      'buyAmount': buyAmount,
      'buyLamports': buyLamports,
      'borrowAmount': borrowAmount,
      'borrowLamports': borrowLamports,
      'baseCurrency': market.baseName,
      'marketPrice': marketPrice,
      'floorPrice': floorPrice,
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
      'buyAmount': buyAmount,
      'buyLamports': buyLamports,
      'borrowAmount': borrowAmount,
      'borrowLamports': borrowLamports,
      'baseCurrency': market.baseName,
      'marketPrice': marketPrice,
      'floorPrice': floorPrice,
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
