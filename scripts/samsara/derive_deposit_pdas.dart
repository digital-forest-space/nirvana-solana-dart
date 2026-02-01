import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Derive PDAs for DepositPrana accounts (Account 3, 6, 8).
///
/// Usage: dart run scripts/samsara/derive_deposit_pdas.dart

const _tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _ataProgramId = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

void main() async {
  final samsaraProgram = Ed25519HDPublicKey.fromBase58(
      'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7');
  final user = Ed25519HDPublicKey.fromBase58(
      'YOUR_WALLET_ADDRESS_HERE');
  final samsaraMarket = Ed25519HDPublicKey.fromBase58(
      '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc');
  final pranaMint = Ed25519HDPublicKey.fromBase58(
      'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N');
  final samsaraTenant = Ed25519HDPublicKey.fromBase58(
      'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC');
  final tokenProgram = Ed25519HDPublicKey.fromBase58(_tokenProgram);
  final ataProgram = Ed25519HDPublicKey.fromBase58(_ataProgramId);

  const targetAccount3 = 'Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw';
  const targetAccount6 = 'A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM';
  const targetAccount8 = 'G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA';

  String? foundAccount3Derivation;
  Ed25519HDPublicKey? foundAccount3Key;

  // ================================================================
  // ACCOUNT 3: User stake/deposit record
  // ================================================================
  print('=' * 70);
  print('ACCOUNT 3 (target: $targetAccount3)');
  print('=' * 70);

  final account3Seeds = <String, List<Uint8List>>{
    '[samsaraMarket, user]': [
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '[user, samsaraMarket]': [
      Uint8List.fromList(user.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["stake", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('stake')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["deposit", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('deposit')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["prana", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('prana')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["earn", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('earn')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["position", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('position')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["personal", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('personal')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '[user, samsaraMarket, pranaMint]': [
      Uint8List.fromList(user.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(pranaMint.bytes),
    ],
    '[samsaraMarket, user, pranaMint]': [
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
      Uint8List.fromList(pranaMint.bytes),
    ],
    '["prana_deposit", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('prana_deposit')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["deposit_prana", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('deposit_prana')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["staker", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('staker')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["user_stake", samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('user_stake')),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    // Also try with samsaraTenant instead of samsaraMarket
    '["deposit", samsaraTenant, user]': [
      Uint8List.fromList(utf8.encode('deposit')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["prana", samsaraTenant, user]': [
      Uint8List.fromList(utf8.encode('prana')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["stake", samsaraTenant, user]': [
      Uint8List.fromList(utf8.encode('stake')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["earn", samsaraTenant, user]': [
      Uint8List.fromList(utf8.encode('earn')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '[samsaraTenant, user]': [
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '[user, samsaraTenant]': [
      Uint8List.fromList(user.bytes),
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    // Try with tenant + market combos
    '["deposit", samsaraTenant, samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('deposit')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
    '["prana", samsaraTenant, samsaraMarket, user]': [
      Uint8List.fromList(utf8.encode('prana')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
      Uint8List.fromList(user.bytes),
    ],
  };

  for (final entry in account3Seeds.entries) {
    try {
      final result = await Ed25519HDPublicKey.findProgramAddress(
        seeds: entry.value,
        programId: samsaraProgram,
      );
      final derived = result.toBase58();
      final match = derived == targetAccount3;
      final marker = match ? ' *** MATCH ***' : '';
      print('  ${entry.key} => $derived$marker');
      if (match) {
        foundAccount3Derivation = entry.key;
        foundAccount3Key = result;
      }
    } catch (e) {
      print('  ${entry.key} => ERROR: $e');
    }
  }

  if (foundAccount3Key != null) {
    print('\n>>> FOUND Account 3 derivation: $foundAccount3Derivation');
  } else {
    print('\n>>> Account 3 derivation NOT FOUND with any combination.');
    // Use the known key for Account 6 derivation attempts
    foundAccount3Key =
        Ed25519HDPublicKey.fromBase58(targetAccount3);
  }

  // ================================================================
  // ACCOUNT 6: prANA escrow token account
  // ================================================================
  print('\n${'=' * 70}');
  print('ACCOUNT 6 (target: $targetAccount6)');
  print('=' * 70);

  final account6Seeds = <String, _PdaAttempt>{
    // Standard ATA: [owner, tokenProgram, mint] with ATA program
    'ATA [account3, tokenProgram, pranaMint] via ATA program': _PdaAttempt(
      seeds: [
        Uint8List.fromList(foundAccount3Key!.bytes),
        Uint8List.fromList(tokenProgram.bytes),
        Uint8List.fromList(pranaMint.bytes),
      ],
      programId: ataProgram,
    ),
    '[account3, pranaMint] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(foundAccount3Key!.bytes),
        Uint8List.fromList(pranaMint.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["vault", account3, pranaMint] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('vault')),
        Uint8List.fromList(foundAccount3Key!.bytes),
        Uint8List.fromList(pranaMint.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["prana_vault", samsaraMarket, user] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('prana_vault')),
        Uint8List.fromList(samsaraMarket.bytes),
        Uint8List.fromList(user.bytes),
      ],
      programId: samsaraProgram,
    ),
    // Additional combos
    '["escrow", samsaraMarket, user] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('escrow')),
        Uint8List.fromList(samsaraMarket.bytes),
        Uint8List.fromList(user.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["token", account3] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('token')),
        Uint8List.fromList(foundAccount3Key!.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["vault", samsaraMarket, user] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('vault')),
        Uint8List.fromList(samsaraMarket.bytes),
        Uint8List.fromList(user.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["deposit", account3, pranaMint] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('deposit')),
        Uint8List.fromList(foundAccount3Key!.bytes),
        Uint8List.fromList(pranaMint.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["prana", account3] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('prana')),
        Uint8List.fromList(foundAccount3Key!.bytes),
      ],
      programId: samsaraProgram,
    ),
    '["escrow", account3, pranaMint] via Samsara': _PdaAttempt(
      seeds: [
        Uint8List.fromList(utf8.encode('escrow')),
        Uint8List.fromList(foundAccount3Key!.bytes),
        Uint8List.fromList(pranaMint.bytes),
      ],
      programId: samsaraProgram,
    ),
  };

  for (final entry in account6Seeds.entries) {
    try {
      final attempt = entry.value;
      final result = await Ed25519HDPublicKey.findProgramAddress(
        seeds: attempt.seeds,
        programId: attempt.programId,
      );
      final derived = result.toBase58();
      final match = derived == targetAccount6;
      final marker = match ? ' *** MATCH ***' : '';
      print('  ${entry.key} => $derived$marker');
    } catch (e) {
      print('  ${entry.key} => ERROR: $e');
    }
  }

  // ================================================================
  // ACCOUNT 8: 17-byte account
  // ================================================================
  print('\n${'=' * 70}');
  print('ACCOUNT 8 (target: $targetAccount8)');
  print('=' * 70);

  final account8Seeds = <String, List<Uint8List>>{
    '["epoch", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('epoch')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["counter", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('counter')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["state", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('state')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["prana_state", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('prana_state')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["deposit_state", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('deposit_state')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["earn_state", samsaraMarket]': [
      Uint8List.fromList(utf8.encode('earn_state')),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    // Also try with samsaraTenant
    '["epoch", samsaraTenant]': [
      Uint8List.fromList(utf8.encode('epoch')),
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    '["counter", samsaraTenant]': [
      Uint8List.fromList(utf8.encode('counter')),
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    '["state", samsaraTenant]': [
      Uint8List.fromList(utf8.encode('state')),
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    '["prana_state", samsaraTenant]': [
      Uint8List.fromList(utf8.encode('prana_state')),
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    // Try with market + tenant
    '["epoch", samsaraTenant, samsaraMarket]': [
      Uint8List.fromList(utf8.encode('epoch')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '["state", samsaraTenant, samsaraMarket]': [
      Uint8List.fromList(utf8.encode('state')),
      Uint8List.fromList(samsaraTenant.bytes),
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    // Try just the market or tenant alone
    '[samsaraMarket]': [
      Uint8List.fromList(samsaraMarket.bytes),
    ],
    '[samsaraTenant]': [
      Uint8List.fromList(samsaraTenant.bytes),
    ],
    // Single prefix seeds
    '["epoch"]': [
      Uint8List.fromList(utf8.encode('epoch')),
    ],
    '["counter"]': [
      Uint8List.fromList(utf8.encode('counter')),
    ],
  };

  for (final entry in account8Seeds.entries) {
    try {
      final result = await Ed25519HDPublicKey.findProgramAddress(
        seeds: entry.value,
        programId: samsaraProgram,
      );
      final derived = result.toBase58();
      final match = derived == targetAccount8;
      final marker = match ? ' *** MATCH ***' : '';
      print('  ${entry.key} => $derived$marker');
    } catch (e) {
      print('  ${entry.key} => ERROR: $e');
    }
  }

  // ================================================================
  // Query getProgramAccounts with dataSize=17
  // ================================================================
  print('\n${'=' * 70}');
  print('getProgramAccounts(Samsara, dataSize=17)');
  print('=' * 70);

  final rpcUrl = Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';
  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);

  try {
    print('  Querying accounts with dataSize=17 owned by Samsara program...');
    final accounts = await rpcClient.getProgramAccounts(
      'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7',
      dataSize: 17,
    );
    print('  Found ${accounts.length} accounts with dataSize=17');
    for (final acct in accounts) {
      final pubkey = acct['pubkey'] ?? 'unknown';
      final data = acct['account']?['data'];
      final dataStr = data is List ? data[0] : data?.toString() ?? '';
      final isTarget = pubkey == targetAccount8 ? ' *** TARGET ***' : '';
      print('    $pubkey$isTarget');
      if (dataStr.isNotEmpty) {
        print('      data: $dataStr');
      }
    }
  } catch (e) {
    print('  ERROR querying getProgramAccounts: $e');
  }

  print('\nDone.');
}

class _PdaAttempt {
  final List<Uint8List> seeds;
  final Ed25519HDPublicKey programId;
  _PdaAttempt({required this.seeds, required this.programId});
}
