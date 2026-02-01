import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Deeply analyze on-chain accounts from the DepositPrana transaction.
///
/// Part 1: Parse Account 3's full 435-byte data layout (32-byte chunks as pubkeys)
/// Part 2: Brute-force discriminator matching via sha256("account:<Name>")
/// Part 3: Query getProgramAccounts with dataSize=435 on Samsara program
///
/// Usage: dart run scripts/samsara/parse_samsara_accounts.dart

const _account3 = 'Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw';
const _account8 = 'G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA';

/// Known addresses to match against decoded pubkeys
const _knownAddresses = <String, String>{
  '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc': 'navSOL samsaraMarket',
  'A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM': 'prANA vault (account 6)',
  'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N': 'prANA mint',
  'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC': 'samsaraTenant',
  'G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA': 'account 8',
  'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo': 'navSOL mint',
  'A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc': 'navSOL mayflowerMarket',
  'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7': 'Samsara program',
  'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v': 'Mayflower program',
  'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA': 'Token program',
  '11111111111111111111111111111111': 'System program',
  'So11111111111111111111111111111111111111112': 'wSOL mint',
  'EKVkmuwDKRKHw85NPTbKSKuS75EY4NLcxe1qzSPixLdy': 'navSOL authorityPda',
  'DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj': 'navSOL marketMetadata',
  'Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC': 'navSOL marketGroup',
  '43vPhZeow3pgYa6zrPXASVQhdXTMfowyfNK87BYizhnL': 'navSOL marketSolVault',
  'BCYzijbWwmqRnsTWjGhHbneST2emQY36WcRAkbkhsQMt': 'navSOL marketNavVault',
  'B8jccpiKZjapgfw1ay6EH3pPnxqTmimsm2KsTZ9LSmjf': 'navSOL feeVault',
  '81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z': 'mayflowerTenant',
};

/// Discriminators to match
final _account3Disc = Uint8List.fromList([37, 169, 199, 114, 141, 109, 9, 167]);
final _account8Disc = Uint8List.fromList([253, 84, 22, 238, 102, 139, 188, 244]);

/// Candidate account type names for discriminator brute-force
const _candidateNames = [
  'StakePool', 'StakeConfig', 'MarketStake', 'EarnPool', 'PranaPool',
  'PranaVault', 'EarnConfig', 'DepositConfig', 'MarketConfig',
  'StakeAuthority', 'MarketAuthority', 'VaultAuthority',
  'EpochState', 'EpochCounter', 'Counter', 'DepositCounter', 'StakeCounter',
  'PranaDeposit', 'UserDeposit', 'DepositState', 'EarnState',
  'MarketEarn', 'MarketPrana', 'PranaState', 'PranaConfig',
  'Market', 'Pool', 'Vault', 'Authority', 'Config', 'State', 'Epoch',
  'Reward', 'RewardState',
  'UserStake', 'UserPosition', 'Position', 'PersonalPosition', 'PersonalStake',
  'StakeState', 'StakeRecord', 'Record',
  // Additional candidates
  'Earn', 'Stake', 'Deposit', 'Prana', 'Samsara',
  'MarketPool', 'MarketVault', 'MarketState', 'MarketAccount',
  'PoolConfig', 'PoolState', 'PoolAccount',
  'EarnAccount', 'EarnVault',
  'StakeAccount', 'StakeVault',
  'DepositAccount', 'DepositVault', 'DepositPool',
  'TokenPool', 'TokenVault', 'TokenConfig',
  'UserAccount', 'UserConfig', 'UserState',
  'PersonalAccount', 'PersonalConfig', 'PersonalState',
  'SamsaraMarket', 'SamsaraPool', 'SamsaraVault', 'SamsaraConfig',
  'SamsaraState', 'SamsaraAccount',
  'PranaAccount', 'PranaMarket',
  'EpochConfig', 'EpochAccount', 'EpochPool',
  'RewardConfig', 'RewardAccount', 'RewardPool', 'RewardVault',
  'Tenant', 'TenantConfig', 'TenantState',
  'GlobalState', 'GlobalConfig', 'GlobalAccount',
];

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

  // ================================================================
  // PART 1: Parse Account 3's full data layout
  // ================================================================
  print('=' * 78);
  print('PART 1: Parse Account 3 data layout');
  print('Account: $_account3 (435 bytes, Samsara-owned)');
  print('=' * 78);
  print('');

  final acct3Info = await rpcClient.getAccountInfo(_account3);
  if (acct3Info.isEmpty) {
    print('ERROR: Account 3 not found on-chain!');
    exit(1);
  }

  print('Owner: ${acct3Info['owner']}');
  print('Lamports: ${acct3Info['lamports']}');

  final acct3Data = acct3Info['data'] as List<dynamic>;
  final acct3Bytes = base64.decode(acct3Data[0] as String);
  print('Data length: ${acct3Bytes.length} bytes');
  print('');

  // Print discriminator (first 8 bytes)
  final disc3 = acct3Bytes.sublist(0, 8);
  print('Discriminator (bytes 0-7): ${_hexString(disc3)}');
  print('Discriminator (decimal):   ${disc3.toList()}');
  print('');

  // Parse 32-byte chunks starting at offset 8
  print('--- 32-byte chunks decoded as base58 public keys ---');
  print('${'Offset'.padRight(8)} ${'Hex (first 8 bytes)'.padRight(26)} ${'Hex (last 8 bytes)'.padRight(26)} ${'Base58 Public Key'.padRight(48)} Known?');
  print('-' * 160);

  int offset = 8;
  int chunkIndex = 0;
  while (offset + 32 <= acct3Bytes.length) {
    final chunk = acct3Bytes.sublist(offset, offset + 32);
    final hexFirst8 = _hexString(chunk.sublist(0, 8));
    final hexLast8 = _hexString(chunk.sublist(24, 32));

    String base58Key;
    try {
      base58Key = Ed25519HDPublicKey(chunk.toList()).toBase58();
    } catch (e) {
      base58Key = '(decode error)';
    }

    final knownLabel = _knownAddresses[base58Key];
    final marker = knownLabel != null ? ' <-- $knownLabel' : '';

    print(
      '${offset.toString().padRight(8)} '
      '${hexFirst8.padRight(26)} '
      '${hexLast8.padRight(26)} '
      '${base58Key.padRight(48)}'
      '$marker',
    );

    offset += 32;
    chunkIndex++;
  }

  // Print any remaining bytes after the last full 32-byte chunk
  if (offset < acct3Bytes.length) {
    final remaining = acct3Bytes.sublist(offset);
    print('');
    print('Remaining ${remaining.length} bytes at offset $offset:');
    print('  Hex: ${_hexString(remaining)}');

    // Try to interpret as integers
    if (remaining.length >= 8) {
      final bd = ByteData.sublistView(Uint8List.fromList(remaining.toList()));
      print('  As u64 (little-endian): ${bd.getUint64(0, Endian.little)}');
      if (remaining.length >= 16) {
        print('  Next u64 (offset +8):   ${bd.getUint64(8, Endian.little)}');
      }
    }
    // Also try interpreting individual bytes
    print('  As u8 values: ${remaining.toList()}');

    // Try interpreting as various small int types
    if (remaining.length >= 2) {
      final bd = ByteData.sublistView(Uint8List.fromList(remaining.toList()));
      print('  As u16 (little-endian): ${bd.getUint16(0, Endian.little)}');
    }
    if (remaining.length >= 4) {
      final bd = ByteData.sublistView(Uint8List.fromList(remaining.toList()));
      print('  As u32 (little-endian): ${bd.getUint32(0, Endian.little)}');
    }
  }

  print('');
  print('Total 32-byte chunks after discriminator: $chunkIndex');
  print('Total bytes accounted for: 8 (disc) + ${chunkIndex * 32} (chunks) + ${acct3Bytes.length - 8 - chunkIndex * 32} (remaining) = ${acct3Bytes.length}');

  // ================================================================
  // PART 2: Discriminator discovery via sha256("account:<Name>")
  // ================================================================
  print('');
  print('=' * 78);
  print('PART 2: Discover account types via sha256("account:<Name>")');
  print('=' * 78);
  print('');

  print('Target discriminators:');
  print('  Account 3: ${_hexString(disc3)} = ${disc3.toList()}');
  print('  Account 8: ${_hexString(_account8Disc)} = ${_account8Disc.toList()}');
  print('');

  // Fetch account 8 discriminator from chain for verification
  final acct8Info = await rpcClient.getAccountInfo(_account8);
  if (acct8Info.isNotEmpty) {
    final acct8Data = acct8Info['data'] as List<dynamic>;
    final acct8Bytes = base64.decode(acct8Data[0] as String);
    final disc8 = acct8Bytes.sublist(0, 8);
    print('Account 8 on-chain discriminator: ${_hexString(disc8)} = ${disc8.toList()}');
    print('Account 8 data length: ${acct8Bytes.length} bytes');
    print('Account 8 owner: ${acct8Info['owner']}');
    print('');
  }

  final uniqueNames = _candidateNames.toSet().toList();
  int matchCount = 0;

  print('Searching ${uniqueNames.length} candidate names...');
  print('');
  print('${'Name'.padRight(25)} ${'sha256 first 8 bytes'.padRight(30)} Match?');
  print('-' * 70);

  for (final name in uniqueNames) {
    final preimage = 'account:$name';
    final hashBytes = sha256.convert(utf8.encode(preimage)).bytes;
    final first8 = Uint8List.fromList(hashBytes.sublist(0, 8));

    bool matchesAcct3 = _bytesEqual(first8, _account3Disc);
    bool matchesAcct8 = _bytesEqual(first8, _account8Disc);

    String matchLabel = '';
    if (matchesAcct3) matchLabel = ' *** MATCHES ACCOUNT 3 ***';
    if (matchesAcct8) matchLabel = ' *** MATCHES ACCOUNT 8 ***';

    if (matchesAcct3 || matchesAcct8) {
      matchCount++;
      print(
        '${name.padRight(25)} '
        '${_hexString(first8).padRight(30)} '
        '$matchLabel',
      );
    }
  }

  if (matchCount == 0) {
    print('');
    print('No matches found among ${uniqueNames.length} candidate names.');
    print('');
    print('Printing ALL computed hashes for reference:');
    print('');
    for (final name in uniqueNames) {
      final preimage = 'account:$name';
      final hashBytes = sha256.convert(utf8.encode(preimage)).bytes;
      final first8 = Uint8List.fromList(hashBytes.sublist(0, 8));
      print('  ${name.padRight(25)} ${_hexString(first8)}');
    }
  } else {
    print('');
    print('Found $matchCount match(es)!');
  }

  // ================================================================
  // PART 3: getProgramAccounts with dataSize=435
  // ================================================================
  print('');
  print('=' * 78);
  print('PART 3: getProgramAccounts on Samsara with dataSize=435');
  print('Program: ${config.samsaraProgramId}');
  print('=' * 78);
  print('');

  try {
    final programAccounts = await rpcClient.getProgramAccounts(
      config.samsaraProgramId,
      dataSize: 435,
    );

    print('Found ${programAccounts.length} account(s) with dataSize=435:');
    print('');

    for (int i = 0; i < programAccounts.length; i++) {
      final entry = programAccounts[i];
      final pubkey = entry['pubkey'] as String;
      final account = entry['account'] as Map<String, dynamic>;
      final data = account['data'] as List<dynamic>;
      final bytes = base64.decode(data[0] as String);
      final disc = bytes.sublist(0, 8);

      print('  [$i] Pubkey: $pubkey');
      print('      Owner:  ${account['owner']}');
      print('      Lamports: ${account['lamports']}');
      print('      Data length: ${bytes.length}');
      print('      Discriminator: ${_hexString(disc)} = ${disc.toList()}');

      // Check if discriminator matches account 3
      if (_bytesEqual(Uint8List.fromList(disc.toList()), _account3Disc)) {
        print('      --> Same discriminator as Account 3!');
      }

      // Decode first few 32-byte fields for comparison
      if (bytes.length >= 8 + 64) {
        final field1 = bytes.sublist(8, 40);
        final field2 = bytes.sublist(40, 72);
        String key1, key2;
        try {
          key1 = Ed25519HDPublicKey(field1.toList()).toBase58();
        } catch (_) {
          key1 = '(error)';
        }
        try {
          key2 = Ed25519HDPublicKey(field2.toList()).toBase58();
        } catch (_) {
          key2 = '(error)';
        }
        final label1 = _knownAddresses[key1];
        final label2 = _knownAddresses[key2];
        print('      Field 1 (offset 8):  $key1${label1 != null ? '  <-- $label1' : ''}');
        print('      Field 2 (offset 40): $key2${label2 != null ? '  <-- $label2' : ''}');
      }

      // Is this our target Account 3?
      if (pubkey == _account3) {
        print('      --> THIS IS ACCOUNT 3 from DepositPrana tx');
      }

      print('');
    }

    // Summary
    final found = programAccounts.any((e) => e['pubkey'] == _account3);
    print(found
        ? 'Account 3 ($_account3) IS present in the results.'
        : 'Account 3 ($_account3) is NOT in the results.');
    print('');
    if (programAccounts.length > 1) {
      print('Multiple accounts found -- likely one per market.');
    }
  } catch (e) {
    print('Error querying getProgramAccounts: $e');
    print('');
    print('This may fail on public RPC nodes due to query size limits.');
    print('Try setting SOLANA_RPC_URL to a dedicated RPC endpoint.');
  }

  print('');
  print('Done.');
  exit(0);
}

/// Format bytes as hex string with spaces
String _hexString(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Compare two byte arrays for equality
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
