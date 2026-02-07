import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Investigate unknown accounts from the intercepted DepositPrana transaction.
///
/// Checks on-chain info for:
///   Account 3: Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw
///   Account 6: A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM
///   Account 8: G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA
///
/// Also verifies ATA derivation and samsaraTenant.
///
/// Usage: dart run scripts/samsara/investigate_deposit_prana.dart

const _tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _ataProgramId = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

void main() async {
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
  final config = SamsaraConfig.mainnet();

  // Accounts from the intercepted DepositPrana transaction
  const account3 = 'Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw';
  const account6 = 'A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM';
  const account8 = 'G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA';
  const pranaMint = 'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N';
  const samsaraTenantFromTx = 'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC';
  const expectedUserPubkey = 'YOUR_WALLET_ADDRESS_HERE';

  // ================================================================
  // 1. Account 3: Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw
  // ================================================================
  LogService.log('=' * 70);
  LogService.log('ACCOUNT 3: $account3');
  LogService.log('=' * 70);
  await _inspectAccount(rpcClient, account3);

  // ================================================================
  // 2. Account 6: A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM
  // ================================================================
  LogService.log('\n${'=' * 70}');
  LogService.log('ACCOUNT 6: $account6');
  LogService.log('=' * 70);
  await _inspectAccount(rpcClient, account6);

  // ================================================================
  // 3. Account 8: G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA
  // ================================================================
  LogService.log('\n${'=' * 70}');
  LogService.log('ACCOUNT 8: $account8');
  LogService.log('=' * 70);
  await _inspectAccount(rpcClient, account8);

  // Also try to read discriminator and user pubkey from account 8
  LogService.log('\n  --- User Position Deep Inspection (Account 8) ---');
  await _inspectPositionAccount(rpcClient, account8, expectedUserPubkey);

  // ================================================================
  // 4. ATA derivation check
  // ================================================================
  LogService.log('\n${'=' * 70}');
  LogService.log('ATA DERIVATION CHECK');
  LogService.log('=' * 70);
  LogService.log('  Owner:    $account3');
  LogService.log('  Mint:     $pranaMint (prANA)');
  LogService.log('  Expected: $account6');

  try {
    final derivedAta = await _deriveAta(account3, pranaMint);
    LogService.log('  Derived:  $derivedAta');
    if (derivedAta == account6) {
      LogService.log('  RESULT:   MATCH - Account 6 IS the ATA of Account 3 for prANA');
    } else {
      LogService.log('  RESULT:   NO MATCH - Account 6 is NOT the ATA of Account 3 for prANA');
    }
  } catch (e) {
    LogService.log('  ERROR deriving ATA: $e');
  }

  // ================================================================
  // 5. Samsara Tenant verification
  // ================================================================
  LogService.log('\n${'=' * 70}');
  LogService.log('SAMSARA TENANT VERIFICATION');
  LogService.log('=' * 70);
  LogService.log('  From transaction: $samsaraTenantFromTx');
  LogService.log('  From config:      ${config.samsaraTenant}');
  if (samsaraTenantFromTx == config.samsaraTenant) {
    LogService.log('  RESULT:           MATCH - Tenant matches config');
  } else {
    LogService.log('  RESULT:           MISMATCH - Tenant does NOT match config');
  }

  exit(0);
}

/// Fetch and print account info for a given address.
Future<void> _inspectAccount(SolanaRpcClient rpcClient, String address) async {
  try {
    final info = await rpcClient.getAccountInfo(address);
    if (info.isEmpty) {
      LogService.log('  Account not found (empty response)');
      return;
    }

    final owner = info['owner'] as String?;
    final lamports = info['lamports'];
    final executable = info['executable'];

    LogService.log('  Owner program: $owner');
    LogService.log('  Lamports:      $lamports');
    LogService.log('  Executable:    $executable');

    // Decode data
    final dataArray = info['data'] as List?;
    if (dataArray != null && dataArray.isNotEmpty) {
      final base64Data = dataArray[0] as String;
      final data = base64Decode(base64Data);
      LogService.log('  Data length:   ${data.length} bytes');

      // If token program owns it, parse as token account
      if (owner == _tokenProgram && data.length >= 165) {
        final mint = _bytesToBase58(Uint8List.fromList(data.sublist(0, 32)));
        final tokenOwner =
            _bytesToBase58(Uint8List.fromList(data.sublist(32, 64)));
        final amount = _readUint64LE(data, 64);
        LogService.log('  --- Token Account ---');
        LogService.log('  Mint:          $mint');
        LogService.log('  Token Owner:   $tokenOwner');
        LogService.log('  Amount (raw):  $amount');
      } else {
        // Print first 40 bytes as hex for inspection
        final previewLen = data.length < 40 ? data.length : 40;
        final hex = data
            .sublist(0, previewLen)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        LogService.log('  First $previewLen bytes (hex): $hex');

        // Try to read first 8 bytes as discriminator
        if (data.length >= 8) {
          final disc = data
              .sublist(0, 8)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          LogService.log('  Discriminator: $disc');
        }

        // Try to read bytes 8-40 as a pubkey
        if (data.length >= 40) {
          final pubkey =
              _bytesToBase58(Uint8List.fromList(data.sublist(8, 40)));
          LogService.log('  Bytes 8-40 as pubkey: $pubkey');
        }
      }
    } else {
      LogService.log('  Data:          (no data)');
    }
  } catch (e) {
    LogService.log('  ERROR fetching account: $e');
  }
}

/// Deep inspection of a position account: check discriminator and user pubkey.
Future<void> _inspectPositionAccount(
  SolanaRpcClient rpcClient,
  String address,
  String expectedUserPubkey,
) async {
  try {
    final info = await rpcClient.getAccountInfo(address);
    if (info.isEmpty) {
      LogService.log('  Account not found');
      return;
    }

    final dataArray = info['data'] as List?;
    if (dataArray == null || dataArray.isEmpty) {
      LogService.log('  No data');
      return;
    }

    final base64Data = dataArray[0] as String;
    final data = base64Decode(base64Data);

    if (data.length < 40) {
      LogService.log('  Data too short (${data.length} bytes) for position account');
      return;
    }

    final discriminator = data.sublist(0, 8);
    final discHex = discriminator
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    LogService.log('  Discriminator (8 bytes): $discHex');

    final userPubkey =
        _bytesToBase58(Uint8List.fromList(data.sublist(8, 40)));
    LogService.log('  User pubkey (bytes 8-40): $userPubkey');

    if (userPubkey == expectedUserPubkey) {
      LogService.log('  RESULT: MATCH - User pubkey matches expected ($expectedUserPubkey)');
    } else {
      LogService.log('  RESULT: NO MATCH - expected $expectedUserPubkey');
    }

    // Print additional fields if present
    if (data.length >= 72) {
      final field2 =
          _bytesToBase58(Uint8List.fromList(data.sublist(40, 72)));
      LogService.log('  Bytes 40-72 as pubkey: $field2');
    }
    if (data.length >= 104) {
      final field3 =
          _bytesToBase58(Uint8List.fromList(data.sublist(72, 104)));
      LogService.log('  Bytes 72-104 as pubkey: $field3');
    }

    // Print remaining data as u64 values
    const structEnd = 104; // After 3 pubkeys + discriminator
    if (data.length > structEnd) {
      LogService.log('  Remaining ${data.length - structEnd} bytes after 3 pubkey fields:');
      final remaining = data.sublist(structEnd);
      final remHex = remaining
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      LogService.log('    Hex: $remHex');

      // Interpret as u64 values
      for (int i = 0; i + 8 <= remaining.length; i += 8) {
        final val = _readUint64LE(remaining, i);
        LogService.log('    Offset ${structEnd + i}: $val');
      }
    }
  } catch (e) {
    LogService.log('  ERROR: $e');
  }
}

/// Derive the Associated Token Address for a given owner and mint.
Future<String> _deriveAta(String owner, String mint) async {
  final ownerPubkey = Ed25519HDPublicKey.fromBase58(owner);
  final mintPubkey = Ed25519HDPublicKey.fromBase58(mint);
  final ataProgramPubkey = Ed25519HDPublicKey.fromBase58(_ataProgramId);
  final tokenProgramPubkey = Ed25519HDPublicKey.fromBase58(_tokenProgram);

  final pda = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      Uint8List.fromList(ownerPubkey.bytes),
      Uint8List.fromList(tokenProgramPubkey.bytes),
      Uint8List.fromList(mintPubkey.bytes),
    ],
    programId: ataProgramPubkey,
  );

  return pda.toBase58();
}

String _bytesToBase58(Uint8List bytes) {
  return Ed25519HDPublicKey(bytes.toList()).toBase58();
}

int _readUint64LE(List<int> data, int offset) {
  final bd = ByteData.sublistView(Uint8List.fromList(data));
  return bd.getUint64(offset, Endian.little);
}
