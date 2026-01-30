import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';
import 'package:solana/base58.dart';

// Import samsara modules using package imports
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/transaction_builder.dart';

/// Execute a buy navSOL transaction (SOL → navSOL)
///
/// Usage: dart scripts/samsara/buy_nav_sol.dart <keypair_path> <sol_amount> [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/samsara/buy_nav_sol.dart ~/.config/solana/id.json 0.01
///   dart scripts/samsara/buy_nav_sol.dart ~/.config/solana/id.json 0.1 --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/samsara/buy_nav_sol.dart <keypair_path> <sol_amount> [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('  --dry-run    Build transaction but don\'t send');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final solAmount = double.tryParse(args[1]);

  // Parse flags
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');
  final dryRun = args.any((a) => a.toLowerCase() == '--dry-run');

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (solAmount == null || solAmount <= 0) {
    print(jsonEncode({'success': false, 'error': 'Invalid SOL amount: ${args[1]}'}));
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

  // Create Solana client
  if (verbose) print('RPC: $rpcUrl');
  final rpcUri = Uri.parse(rpcUrl);
  final client = SolanaClient(
    rpcUrl: rpcUri,
    websocketUrl: rpcUri.replace(scheme: rpcUri.scheme == 'https' ? 'wss' : 'ws'),
  );

  // Get market config
  final market = NavTokenMarket.navSol();
  final config = SamsaraConfig.mainnet();
  final builder = SamsaraTransactionBuilder(config: config);

  // Convert SOL to lamports
  final lamports = (solAmount * 1e9).toInt();
  if (verbose) {
    print('\nTransaction:');
    print('  Input: $solAmount SOL ($lamports lamports)');
    print('  Market: ${market.name}');
  }

  // Derive user token accounts
  final userWsolAta = await _getAssociatedTokenAddress(userPubkey, market.baseMint);
  final userNavSolAta = await _getAssociatedTokenAddress(userPubkey, market.navMint);

  // Find user's personal_position by querying program accounts
  // This is more robust than PDA derivation - same approach as Nirvana
  final positionInfo = await _findUserPosition(rpcUrl, userPubkey);

  if (positionInfo == null) {
    // For new users, try PDA derivation as fallback
    final derivedPosition = await _derivePersonalPosition(userPubkey, market.marketMetadata);
    print(jsonEncode({
      'success': false,
      'error': 'Personal position not found. Please use the Samsara web UI to make your first transaction, then this script will work for subsequent transactions.',
      'derivedPosition': derivedPosition,
      'note': 'The user_shares PDA derivation is proprietary to Mayflower and cannot be derived client-side.',
    }));
    exit(1);
  }

  final personalPosition = positionInfo['personalPosition']!;
  final userShares = positionInfo['userShares']!;
  if (verbose) {
    print('  Found existing position via getProgramAccounts');
    print('  Personal Position: $personalPosition');
    print('  User Shares: $userShares');
  }

  if (verbose) {
    print('  User wSOL ATA: $userWsolAta');
    print('  User navSOL ATA: $userNavSolAta');
  }

  // Build transaction instructions
  if (verbose) print('\nBuilding transaction...');

  final instructions = <Instruction>[
    // 1. Set compute unit limit
    builder.buildSetComputeUnitLimitInstruction(400000),

    // 2. Set compute unit price (for priority)
    builder.buildSetComputeUnitPriceInstruction(280000),

    // 3. Create wSOL ATA (idempotent)
    builder.buildCreateAtaIdempotentInstruction(
      payer: userPubkey,
      associatedTokenAccount: userWsolAta,
      owner: userPubkey,
      mint: market.baseMint,
    ),

    // 4. Transfer SOL to wSOL ATA
    builder.buildTransferInstruction(
      from: userPubkey,
      to: userWsolAta,
      lamports: lamports,
    ),

    // 5. Sync native (wrap SOL)
    builder.buildSyncNativeInstruction(userWsolAta),

    // 6. Create navSOL ATA (idempotent)
    builder.buildCreateAtaIdempotentInstruction(
      payer: userPubkey,
      associatedTokenAccount: userNavSolAta,
      owner: userPubkey,
      mint: market.navMint,
    ),
  ];

  // 7. Mayflower buy navSOL (position must already exist)
  instructions.add(
    builder.buildBuyNavSolInstruction(
      userPubkey: userPubkey,
      userWsolAccount: userWsolAta,
      userNavSolAccount: userNavSolAta,
      personalPosition: personalPosition,
      userShares: userShares,
      market: market,
      inputLamports: lamports,
      minOutputLamports: 0, // No slippage protection for now
    ),
  );

  // 8. Close wSOL account (return dust to user)
  instructions.add(
    builder.buildCloseAccountInstruction(
      account: userWsolAta,
      destination: userPubkey,
      owner: userPubkey,
    ),
  );

  if (verbose) print('  Built ${instructions.length} instructions');

  // Get recent blockhash
  final blockhashResponse = await client.rpcClient.getLatestBlockhash();
  final blockhash = blockhashResponse.value.blockhash;
  if (verbose) print('  Blockhash: $blockhash');

  // Build unsigned transaction bytes
  final unsignedTxBytes = _buildUnsignedTransaction(
    instructions: instructions,
    feePayer: userPubkey,
    recentBlockhash: blockhash,
  );

  if (dryRun) {
    if (verbose) print('\n🔍 Dry run - transaction not sent');

    // Output transaction details
    final txBase64 = base64Encode(unsignedTxBytes);
    print(jsonEncode({
      'success': true,
      'dryRun': true,
      'transaction': txBase64,
      'instructionCount': instructions.length,
      'userWsolAta': userWsolAta,
      'userNavSolAta': userNavSolAta,
      'inputLamports': lamports,
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
      print('\n✅ Transaction sent!');
      print('  Signature: $signature');
      print('  Explorer: https://solscan.io/tx/$signature');
    }

    print(jsonEncode({
      'success': true,
      'signature': signature,
      'inputSol': solAmount,
      'inputLamports': lamports,
      'explorer': 'https://solscan.io/tx/$signature',
    }));
  } catch (e) {
    if (verbose) {
      print('\n❌ Transaction failed!');
      print('  Error: $e');
    }
    print(jsonEncode({
      'success': false,
      'error': e.toString(),
    }));
    exit(1);
  }
}

/// Derive associated token address
Future<String> _getAssociatedTokenAddress(String owner, String mint) async {
  final ownerPubkey = Ed25519HDPublicKey.fromBase58(owner);
  final mintPubkey = Ed25519HDPublicKey.fromBase58(mint);
  const tokenProgramId = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  const ataProgramId = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

  final seeds = [
    ownerPubkey.bytes,
    Ed25519HDPublicKey.fromBase58(tokenProgramId).bytes,
    mintPubkey.bytes,
  ];

  final pda = await Ed25519HDPublicKey.findProgramAddress(
    seeds: seeds,
    programId: Ed25519HDPublicKey.fromBase58(ataProgramId),
  );

  return pda.toBase58();
}

/// Build unsigned transaction bytes
Uint8List _buildUnsignedTransaction({
  required List<Instruction> instructions,
  required String feePayer,
  required String recentBlockhash,
}) {
  // Collect all unique accounts
  final accountsMap = <String, _AccountMeta>{};

  // Fee payer is first, always signer and writable
  accountsMap[feePayer] = _AccountMeta(
    pubkey: feePayer,
    isSigner: true,
    isWriteable: true,
  );

  // Collect accounts from all instructions
  for (final ix in instructions) {
    for (final acc in ix.accounts) {
      final pubkey = acc.pubKey.toBase58();
      final existing = accountsMap[pubkey];
      if (existing != null) {
        // Merge flags (more permissive wins)
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

    // Add program ID (not signer, not writable)
    final programId = ix.programId.toBase58();
    if (!accountsMap.containsKey(programId)) {
      accountsMap[programId] = _AccountMeta(
        pubkey: programId,
        isSigner: false,
        isWriteable: false,
      );
    }
  }

  // Sort accounts: signers first, then writable, then readonly
  final accounts = accountsMap.values.toList();
  accounts.sort((a, b) {
    if (a.isSigner != b.isSigner) return a.isSigner ? -1 : 1;
    if (a.isWriteable != b.isWriteable) return a.isWriteable ? -1 : 1;
    return 0;
  });

  // Ensure fee payer is first
  final feePayerIndex = accounts.indexWhere((a) => a.pubkey == feePayer);
  if (feePayerIndex > 0) {
    final fp = accounts.removeAt(feePayerIndex);
    accounts.insert(0, fp);
  }

  // Build account index map
  final accountIndexMap = <String, int>{};
  for (var i = 0; i < accounts.length; i++) {
    accountIndexMap[accounts[i].pubkey] = i;
  }

  // Count signers and writable accounts
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

  // Build message
  final messageBuilder = BytesBuilder();

  // Header
  messageBuilder.addByte(numRequiredSignatures);
  messageBuilder.addByte(numReadonlySignedAccounts);
  messageBuilder.addByte(numReadonlyUnsignedAccounts);

  // Account addresses (compact-u16 length + addresses)
  messageBuilder.add(_encodeCompactU16(accounts.length));
  for (final acc in accounts) {
    messageBuilder.add(Ed25519HDPublicKey.fromBase58(acc.pubkey).bytes);
  }

  // Recent blockhash
  messageBuilder.add(base58decode(recentBlockhash));

  // Instructions (compact-u16 length + instructions)
  messageBuilder.add(_encodeCompactU16(instructions.length));
  for (final ix in instructions) {
    // Program ID index
    messageBuilder.addByte(accountIndexMap[ix.programId.toBase58()]!);

    // Account indices (compact-u16 length + indices)
    messageBuilder.add(_encodeCompactU16(ix.accounts.length));
    for (final acc in ix.accounts) {
      messageBuilder.addByte(accountIndexMap[acc.pubKey.toBase58()]!);
    }

    // Instruction data (compact-u16 length + data)
    messageBuilder.add(_encodeCompactU16(ix.data.length));
    messageBuilder.add(ix.data.toList());
  }

  final messageBytes = Uint8List.fromList(messageBuilder.toBytes());

  // Build transaction with placeholder signature
  final txBuilder = BytesBuilder();
  txBuilder.addByte(1); // 1 signature required
  txBuilder.add(Uint8List(64)); // Placeholder signature (64 zeros)
  txBuilder.add(messageBytes);

  return Uint8List.fromList(txBuilder.toBytes());
}

/// Encode a number as compact-u16
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

/// Sign an unsigned transaction
Future<Uint8List> _signTransaction(Uint8List unsignedTxBytes, Ed25519HDKeyPair keypair) async {
  final numSignatures = unsignedTxBytes[0];
  final messageOffset = 1 + (numSignatures * 64);
  final messageBytes = unsignedTxBytes.sublist(messageOffset);

  // Sign the message
  final signature = await keypair.sign(messageBytes);

  // Build signed transaction
  final signedTx = BytesBuilder();
  signedTx.addByte(numSignatures);
  signedTx.add(signature.bytes);

  // Add any additional signatures (for multi-sig)
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

/// Find user's personal_position by querying Mayflower program accounts
/// This uses getProgramAccounts with filters - same approach as Nirvana
/// Returns both personalPosition and userShares addresses, or null if not found
Future<Map<String, String>?> _findUserPosition(String rpcUrl, String userPubkey) async {
  const mayflowerProgram = 'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v';

  try {
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getProgramAccounts',
        'params': [
          mayflowerProgram,
          {
            'encoding': 'base64',
            'filters': [
              {'dataSize': 121}, // personal_position account size
              {
                'memcmp': {
                  'offset': 40, // user pubkey is at byte 40 in the account data
                  'bytes': userPubkey,
                }
              }
            ]
          }
        ]
      }),
    );

    final result = jsonDecode(response.body);

    if (result['error'] != null) {
      return null;
    }

    final accounts = result['result'] as List;
    if (accounts.isEmpty) {
      return null;
    }

    // Get the first matching account
    final account = accounts.first;
    final personalPosition = account['pubkey'] as String;

    // Extract user_shares from account data (bytes 72-103)
    final dataBase64 = account['account']['data'][0] as String;
    final data = base64Decode(dataBase64);

    if (data.length < 104) {
      return null;
    }

    final userSharesBytes = data.sublist(72, 104);
    final userShares = Ed25519HDPublicKey(userSharesBytes).toBase58();

    return {
      'personalPosition': personalPosition,
      'userShares': userShares,
    };
  } catch (e) {
    return null;
  }
}

/// Derive personal_position PDA (fallback method)
/// Seeds: ["personal_position", market_metadata, user_pubkey]
/// Note: The seed order is [prefix, marketMetadata, user] NOT [prefix, user, marketMetadata]
Future<String> _derivePersonalPosition(String userPubkey, String marketMetadata) async {
  final programId = Ed25519HDPublicKey.fromBase58('AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v');
  final seeds = [
    'personal_position'.codeUnits,
    Ed25519HDPublicKey.fromBase58(marketMetadata).bytes,
    Ed25519HDPublicKey.fromBase58(userPubkey).bytes,
  ];

  final pda = await Ed25519HDPublicKey.findProgramAddress(
    seeds: seeds,
    programId: programId,
  );

  return pda.toBase58();
}


