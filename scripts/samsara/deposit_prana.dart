import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';
import 'package:solana/base58.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/pda.dart';
import 'package:nirvana_solana/src/samsara/transaction_builder.dart';

/// Deposit prANA to a Samsara market's governance account.
///
/// Usage: dart scripts/samsara/deposit_prana.dart <keypair_path> <prana_amount> [--market <name>] [--rpc <url>] [--verbose] [--dry-run]
///
/// Examples:
///   dart scripts/samsara/deposit_prana.dart ~/.config/solana/id.json 1.0
///   dart scripts/samsara/deposit_prana.dart ~/.config/solana/id.json 0.5 --market navSOL --verbose
///   dart scripts/samsara/deposit_prana.dart ~/.config/solana/id.json 2.0 --dry-run
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/samsara/deposit_prana.dart <keypair_path> <prana_amount> [options]');
    print('');
    print('Options:');
    print('  --market <name>  Market name (default: navSOL). Available: ${NavTokenMarket.availableMarkets.join(", ")}');
    print('  --rpc <url>      Custom RPC endpoint');
    print('  --verbose        Show detailed output before JSON result');
    print('  --dry-run        Build transaction but don\'t send');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final pranaAmount = double.tryParse(args[1]);

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

  if (pranaAmount == null || pranaAmount <= 0) {
    print(jsonEncode({'success': false, 'error': 'Invalid prANA amount: ${args[1]}'}));
    exit(1);
  }

  // Look up market
  final market = NavTokenMarket.byName(marketName);
  if (market == null) {
    print(jsonEncode({
      'success': false,
      'error': 'Unknown market: $marketName',
      'available': NavTokenMarket.availableMarkets,
    }));
    exit(1);
  }

  if (market.samsaraMarket.isEmpty) {
    print(jsonEncode({
      'success': false,
      'error': 'Samsara market address not configured for ${market.name}',
    }));
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
  final keypairBytes = RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList();
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  if (verbose) print('Wallet: $userPubkey');

  // Create Solana client
  if (verbose) print('RPC: $rpcUrl');
  final rpcUri = Uri.parse(rpcUrl);
  final client = SolanaClient(
    rpcUrl: rpcUri,
    websocketUrl: rpcUri.replace(scheme: rpcUri.scheme == 'https' ? 'wss' : 'ws'),
  );

  final config = SamsaraConfig.mainnet();
  final builder = SamsaraTransactionBuilder(config: config);
  final pda = SamsaraPda.mainnet();

  // Convert prANA to lamports (6 decimals)
  final pranaLamports = (pranaAmount * 1e6).round();
  if (verbose) {
    print('\nTransaction:');
    print('  Market: ${market.name}');
    print('  Amount: $pranaAmount prANA ($pranaLamports lamports)');
  }

  // Derive PDAs
  final samsaraMarketKey = Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
  final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
  final govAccount = await pda.personalGovAccount(market: samsaraMarketKey, owner: ownerKey);
  final pranaEscrow = await pda.personalGovPranaEscrow(govAccount: govAccount);
  final logCounter = await pda.logCounter();

  if (verbose) {
    print('  GovAccount PDA: ${govAccount.toBase58()}');
    print('  PranaEscrow PDA: ${pranaEscrow.toBase58()}');
    print('  LogCounter PDA: ${logCounter.toBase58()}');
  }

  // Check if govAccount exists on-chain (raw RPC to avoid parsing issues)
  bool needsInit = false;
  try {
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getAccountInfo',
        'params': [govAccount.toBase58(), {'encoding': 'base64'}],
      }),
    );
    final result = jsonDecode(response.body);
    needsInit = result['result']?['value'] == null;
  } catch (_) {
    needsInit = true;
  }
  if (verbose) print('  GovAccount exists: ${!needsInit}');

  // Find user's prANA ATA
  final pranaMintKey = Ed25519HDPublicKey.fromBase58(config.pranaMint);
  final pranaSrc = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      ownerKey.bytes,
      Ed25519HDPublicKey.fromBase58(config.tokenProgram).bytes,
      pranaMintKey.bytes,
    ],
    programId: Ed25519HDPublicKey.fromBase58(config.associatedTokenProgram),
  );
  if (verbose) print('  User prANA ATA: ${pranaSrc.toBase58()}');

  // Build transaction instructions
  if (verbose) print('\nBuilding transaction...');

  final instructions = <Instruction>[
    builder.buildSetComputeUnitLimitInstruction(200000),
    builder.buildSetComputeUnitPriceInstruction(50000),
  ];

  if (needsInit) {
    if (verbose) print('  Adding initGovAccount instruction');
    instructions.add(builder.buildInitGovAccountInstruction(
      payerPubkey: userPubkey,
      ownerPubkey: userPubkey,
      market: market,
      govAccount: govAccount.toBase58(),
      pranaEscrow: pranaEscrow.toBase58(),
      logCounter: logCounter.toBase58(),
    ));
  }

  instructions.add(builder.buildDepositPranaInstruction(
    depositorPubkey: userPubkey,
    market: market,
    govAccount: govAccount.toBase58(),
    pranaSrc: pranaSrc.toBase58(),
    pranaEscrow: pranaEscrow.toBase58(),
    logCounter: logCounter.toBase58(),
    amount: pranaLamports,
  ));

  if (verbose) print('  Built ${instructions.length} instructions');

  // Get recent blockhash
  final blockhashResponse = await client.rpcClient.getLatestBlockhash();
  final blockhash = blockhashResponse.value.blockhash;
  if (verbose) print('  Blockhash: $blockhash');

  // Build unsigned transaction
  final unsignedTxBytes = _buildUnsignedTransaction(
    instructions: instructions,
    feePayer: userPubkey,
    recentBlockhash: blockhash,
  );

  if (dryRun) {
    if (verbose) print('\nDry run - transaction not sent');
    final txBase64 = base64Encode(unsignedTxBytes);
    print(jsonEncode({
      'success': true,
      'dryRun': true,
      'transaction': txBase64,
      'instructionCount': instructions.length,
      'market': market.name,
      'pranaAmount': pranaAmount,
      'pranaLamports': pranaLamports,
      'govAccount': govAccount.toBase58(),
      'needsInit': needsInit,
    }));
    return;
  }

  // Sign and send transaction
  if (verbose) print('\nSigning and sending transaction...');

  try {
    final signedTxBytes = await _signTransaction(unsignedTxBytes, keypair);

    final signature = await client.rpcClient.sendTransaction(
      base64Encode(signedTxBytes),
      preflightCommitment: Commitment.confirmed,
    );

    if (verbose) {
      print('\nTransaction sent!');
      print('  Signature: $signature');
      print('  Explorer: https://solscan.io/tx/$signature');
    }

    print(jsonEncode({
      'success': true,
      'signature': signature,
      'market': market.name,
      'pranaAmount': pranaAmount,
      'pranaLamports': pranaLamports,
      'explorer': 'https://solscan.io/tx/$signature',
    }));
  } catch (e) {
    if (verbose) {
      print('\nTransaction failed!');
      print('  Error: $e');
    }
    print(jsonEncode({
      'success': false,
      'error': e.toString(),
    }));
    exit(1);
  }
}

/// Build unsigned transaction bytes (same pattern as buy_nav_sol.dart)
Uint8List _buildUnsignedTransaction({
  required List<Instruction> instructions,
  required String feePayer,
  required String recentBlockhash,
}) {
  final accountsMap = <String, _AccountMeta>{};

  accountsMap[feePayer] = _AccountMeta(
    pubkey: feePayer,
    isSigner: true,
    isWriteable: true,
  );

  for (final ix in instructions) {
    for (final acc in ix.accounts) {
      final pubkey = acc.pubKey.toBase58();
      final existing = accountsMap[pubkey];
      if (existing != null) {
        accountsMap[pubkey] = _AccountMeta(
          pubkey: pubkey,
          isSigner: existing.isSigner || acc.isSigner,
          isWriteable: existing.isWriteable || acc.isWriteable,
        );
      } else {
        accountsMap[pubkey] = _AccountMeta(
          pubkey: pubkey,
          isSigner: acc.isSigner,
          isWriteable: acc.isWriteable,
        );
      }
    }

    final programId = ix.programId.toBase58();
    if (!accountsMap.containsKey(programId)) {
      accountsMap[programId] = _AccountMeta(
        pubkey: programId,
        isSigner: false,
        isWriteable: false,
      );
    }
  }

  final accounts = accountsMap.values.toList();
  accounts.sort((a, b) {
    if (a.isSigner != b.isSigner) return a.isSigner ? -1 : 1;
    if (a.isWriteable != b.isWriteable) return a.isWriteable ? -1 : 1;
    return 0;
  });

  final feePayerIndex = accounts.indexWhere((a) => a.pubkey == feePayer);
  if (feePayerIndex > 0) {
    final fp = accounts.removeAt(feePayerIndex);
    accounts.insert(0, fp);
  }

  final accountIndexMap = <String, int>{};
  for (var i = 0; i < accounts.length; i++) {
    accountIndexMap[accounts[i].pubkey] = i;
  }

  var numRequiredSignatures = 0;
  var numReadonlySignedAccounts = 0;
  var numReadonlyUnsignedAccounts = 0;

  for (final acc in accounts) {
    if (acc.isSigner) {
      numRequiredSignatures++;
      if (!acc.isWriteable) numReadonlySignedAccounts++;
    } else {
      if (!acc.isWriteable) numReadonlyUnsignedAccounts++;
    }
  }

  final messageBuilder = BytesBuilder();
  messageBuilder.addByte(numRequiredSignatures);
  messageBuilder.addByte(numReadonlySignedAccounts);
  messageBuilder.addByte(numReadonlyUnsignedAccounts);

  messageBuilder.add(_encodeCompactU16(accounts.length));
  for (final acc in accounts) {
    messageBuilder.add(Ed25519HDPublicKey.fromBase58(acc.pubkey).bytes);
  }

  messageBuilder.add(base58decode(recentBlockhash));

  messageBuilder.add(_encodeCompactU16(instructions.length));
  for (final ix in instructions) {
    messageBuilder.addByte(accountIndexMap[ix.programId.toBase58()]!);
    messageBuilder.add(_encodeCompactU16(ix.accounts.length));
    for (final acc in ix.accounts) {
      messageBuilder.addByte(accountIndexMap[acc.pubKey.toBase58()]!);
    }
    messageBuilder.add(_encodeCompactU16(ix.data.length));
    messageBuilder.add(ix.data.toList());
  }

  final messageBytes = Uint8List.fromList(messageBuilder.toBytes());

  final txBuilder = BytesBuilder();
  txBuilder.addByte(1);
  txBuilder.add(Uint8List(64));
  txBuilder.add(messageBytes);

  return Uint8List.fromList(txBuilder.toBytes());
}

List<int> _encodeCompactU16(int value) {
  if (value < 0x80) {
    return [value];
  } else if (value < 0x4000) {
    return [
      (value & 0x7f) | 0x80,
      (value >> 7) & 0x7f,
    ];
  } else {
    return [
      (value & 0x7f) | 0x80,
      ((value >> 7) & 0x7f) | 0x80,
      (value >> 14) & 0x3,
    ];
  }
}

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

class _AccountMeta {
  final String pubkey;
  final bool isSigner;
  final bool isWriteable;

  _AccountMeta({
    required this.pubkey,
    required this.isSigner,
    required this.isWriteable,
  });
}
