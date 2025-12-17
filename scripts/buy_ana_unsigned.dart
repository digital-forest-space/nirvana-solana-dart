import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a buy ANA transaction using buildUnsignedBuyAnaTransaction
/// This exercises the unsigned transaction building flow:
/// 1. Library builds unsigned tx bytes
/// 2. Script signs the bytes
/// 3. Script sends signed tx
///
/// Usage: dart scripts/buy_ana_unsigned.dart <keypair_path> <amount> [--nirv|--usdc] [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/buy_ana_unsigned.dart ~/.config/solana/id.json 10 --nirv
///   dart scripts/buy_ana_unsigned.dart ~/.config/solana/id.json 10 --usdc --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/buy_ana_unsigned.dart <keypair_path> <amount> [--nirv|--usdc] [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --nirv       Pay with NIRV (default)');
    print('  --usdc       Pay with USDC');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
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
    print(jsonEncode({'success': false, 'error': 'Invalid amount: ${args[1]}'}));
    exit(1);
  }

  // Load keypair
  final keypairFile = File(keypairPath);
  if (!keypairFile.existsSync()) {
    print(jsonEncode({'success': false, 'error': 'Keypair file not found: $keypairPath'}));
    exit(1);
  }

  if (verbose) print('Loading keypair from $keypairPath...');
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  if (verbose) print('Wallet: $userPubkey');

  // Create client
  if (verbose) print('RPC: $rpcUrl');
  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  // Show current prices
  if (verbose) print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  if (verbose) print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Estimate ANA to receive
  final estimatedAna = amount / floorPrice * 0.97;
  if (verbose) {
    print('\nTransaction:');
    print('  Spending: $amount $paymentCurrency');
    print('  Estimated ANA: ${estimatedAna.toStringAsFixed(6)} ANA (after ~3% fee)');
    print('\nBuilding unsigned transaction...');
  }

  try {
    // Step 1: Build unsigned transaction using library method
    final unsignedTxBytes = await client.buildUnsignedBuyAnaTransaction(
      userPubkey: userPubkey,
      amount: amount,
      useNirv: useNirv,
    );

    if (verbose) {
      print('  Unsigned tx size: ${unsignedTxBytes.length} bytes');
      print('\nSigning transaction...');
    }

    // Step 2: Parse the unsigned tx, sign it, and rebuild
    // The unsigned tx has a placeholder signature (64 zeros) that we need to replace
    final signedTxBytes = await _signTransaction(unsignedTxBytes, keypair);

    if (verbose) {
      print('  Signed tx size: ${signedTxBytes.length} bytes');
      print('\nSending transaction...');
    }

    // Step 3: Send the signed transaction
    final rpcUri = Uri.parse(rpcUrl);
    final solanaClient = SolanaClient(
      rpcUrl: rpcUri,
      websocketUrl: rpcUri.replace(scheme: rpcUri.scheme == 'https' ? 'wss' : 'ws'),
    );

    final signature = await solanaClient.rpcClient.sendTransaction(
      base64Encode(signedTxBytes),
      preflightCommitment: Commitment.confirmed,
    );

    if (verbose) {
      print('\n✅ Transaction sent!');
      print('  Signature: $signature');
      print('  Explorer: https://solscan.io/tx/$signature');
      print('\nWaiting for confirmation...');
    }

    // Wait for confirmation
    await _waitForConfirmation(solanaClient, signature);

    if (verbose) {
      print('  Confirmed!');
      print('\nParsing transaction...');
    }

    // Parse the transaction
    try {
      final tx = await client.parseTransaction(signature);
      if (verbose) {
        print('  Type: ${tx.type.name.toUpperCase()}');
        for (final s in tx.sent) {
          print('  Sent: ${s.amount.toStringAsFixed(6)} ${s.currency}');
        }
        for (final r in tx.received) {
          print('  Received: ${r.amount.toStringAsFixed(6)} ${r.currency}');
        }
        if (tx.fee != null) print('  Fee: ${tx.fee!.amount.toStringAsFixed(6)} ${tx.fee!.currency}');
        if (tx.pricePerAna != null) print('  Price: \$${tx.pricePerAna!.toStringAsFixed(6)} per ANA');
        print('');
      }

      // Output JSON result
      print(jsonEncode(tx.toJson()));
    } catch (e) {
      print(jsonEncode({
        'success': true,
        'signature': signature,
        'parseError': e.toString(),
        'explorer': 'https://solscan.io/tx/$signature',
      }));
    }
  } catch (e) {
    if (verbose) {
      print('\n❌ Transaction failed!');
      print('  Error: $e');
    }
    print(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }
}

/// Sign an unsigned transaction
/// The unsigned tx has a placeholder signature (64 zeros) at the start
/// We need to compute the real signature and replace it
Future<Uint8List> _signTransaction(Uint8List unsignedTxBytes, Ed25519HDKeyPair keypair) async {
  // Transaction format: [num_signatures, ...signatures, ...message]
  // Each signature is 64 bytes
  // The message starts after all signatures

  final numSignatures = unsignedTxBytes[0];
  final messageOffset = 1 + (numSignatures * 64);
  final messageBytes = unsignedTxBytes.sublist(messageOffset);

  // Sign the message
  final signature = await keypair.sign(messageBytes);

  // Build the signed transaction
  final signedTx = BytesBuilder();
  signedTx.addByte(numSignatures);
  signedTx.add(signature.bytes); // Real signature

  // Add any additional signatures (if multi-sig, but usually just one)
  for (var i = 1; i < numSignatures; i++) {
    signedTx.add(unsignedTxBytes.sublist(1 + (i * 64), 1 + ((i + 1) * 64)));
  }

  signedTx.add(messageBytes);

  return Uint8List.fromList(signedTx.toBytes());
}

/// Wait for transaction confirmation
Future<void> _waitForConfirmation(SolanaClient client, String signature) async {
  for (var i = 0; i < 30; i++) {
    await Future.delayed(const Duration(seconds: 1));
    try {
      final status = await client.rpcClient.getSignatureStatuses([signature]);
      final value = status.value.first;
      if (value != null) {
        final confirmationStatus = value.confirmationStatus;
        if (confirmationStatus == Commitment.confirmed ||
            confirmationStatus == Commitment.finalized) {
          return;
        }
      }
    } catch (_) {
      // Continue polling
    }
  }
  throw Exception('Transaction confirmation timeout');
}
