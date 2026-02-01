import 'dart:convert';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Compute SHA-256 of a string and return the bytes.
List<int> sha256String(String input) {
  final bytes = utf8.encode(input);
  return crypto.sha256.convert(bytes).bytes;
}

void main() async {
  final samsaraProgram = Ed25519HDPublicKey.fromBase58(
    'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7',
  );
  final owner = Ed25519HDPublicKey.fromBase58(
    'YOUR_WALLET_ADDRESS_HERE',
  );
  final market = Ed25519HDPublicKey.fromBase58(
    '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc',
  );
  const targetAccount3 = 'Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw';
  final targetDiscriminator = [37, 169, 199, 114, 141, 109, 9, 167];

  print('=' * 70);
  print('GovAccount PDA Derivation Test');
  print('=' * 70);
  print('Samsara program: SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7');
  print('Owner:           YOUR_WALLET_ADDRESS_HERE');
  print('Market:          4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc');
  print('Target (Acct 3): $targetAccount3');
  print('Target disc:     $targetDiscriminator');
  print('');

  // =========================================================================
  // Part 1: PDA Derivation
  // =========================================================================
  print('=' * 70);
  print('PART 1: PDA DERIVATION ATTEMPTS');
  print('=' * 70);
  print('');

  final seedCombinations = <String, List<List<int>>>{
    '["gov_account", market, owner]': [
      utf8.encode('gov_account'),
      market.bytes,
      owner.bytes,
    ],
    '["gov_account", owner, market]': [
      utf8.encode('gov_account'),
      owner.bytes,
      market.bytes,
    ],
    '["GovAccount", market, owner]': [
      utf8.encode('GovAccount'),
      market.bytes,
      owner.bytes,
    ],
    '["GovAccount", owner, market]': [
      utf8.encode('GovAccount'),
      owner.bytes,
      market.bytes,
    ],
    '["gov", market, owner]': [
      utf8.encode('gov'),
      market.bytes,
      owner.bytes,
    ],
    '["gov", owner, market]': [
      utf8.encode('gov'),
      owner.bytes,
      market.bytes,
    ],
    '["governance", market, owner]': [
      utf8.encode('governance'),
      market.bytes,
      owner.bytes,
    ],
    '["governance", owner, market]': [
      utf8.encode('governance'),
      owner.bytes,
      market.bytes,
    ],
    '[market, owner] (no prefix)': [
      market.bytes,
      owner.bytes,
    ],
    '[owner, market] (no prefix)': [
      owner.bytes,
      market.bytes,
    ],
    '["staker", market, owner]': [
      utf8.encode('staker'),
      market.bytes,
      owner.bytes,
    ],
    '["staker", owner, market]': [
      utf8.encode('staker'),
      owner.bytes,
      market.bytes,
    ],
    '["depositor", market, owner]': [
      utf8.encode('depositor'),
      market.bytes,
      owner.bytes,
    ],
    '["depositor", owner, market]': [
      utf8.encode('depositor'),
      owner.bytes,
      market.bytes,
    ],
    '["prana_staker", market, owner]': [
      utf8.encode('prana_staker'),
      market.bytes,
      owner.bytes,
    ],
    '["prana_depositor", market, owner]': [
      utf8.encode('prana_depositor'),
      market.bytes,
      owner.bytes,
    ],
  };

  bool foundMatch = false;

  for (final entry in seedCombinations.entries) {
    try {
      final seeds = entry.value.map((s) => Uint8List.fromList(s)).toList();
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seeds,
        programId: samsaraProgram,
      );
      final derived = pda.toBase58();
      final matched = derived == targetAccount3;
      if (matched) foundMatch = true;

      final marker = matched ? '  >>> MATCH <<<' : '';
      print('Seeds: ${entry.key}');
      print('  Derived: $derived$marker');
      print('');
    } catch (e) {
      print('Seeds: ${entry.key}');
      print('  ERROR: $e');
      print('');
    }
  }

  if (!foundMatch) {
    print('*** No PDA match found for Account 3 ***');
  }
  print('');

  // =========================================================================
  // Part 2: Anchor Account Discriminator Verification
  // =========================================================================
  print('=' * 70);
  print('PART 2: ANCHOR ACCOUNT DISCRIMINATOR CHECK');
  print('=' * 70);
  print('');
  print('Target discriminator (first 8 bytes of Account 3):');
  print('  $targetDiscriminator');
  final targetHex = targetDiscriminator
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  print('  hex: $targetHex');
  print('');

  final discriminatorCandidates = [
    'account:GovAccount',
    'account:Governance',
    'account:Staker',
    'account:Depositor',
    'account:PranaStaker',
    'account:UserStake',
  ];

  for (final candidate in discriminatorCandidates) {
    final hash = sha256String(candidate);
    final first8 = hash.sublist(0, 8);
    final matched = _listEquals(first8, targetDiscriminator);

    final hexStr = first8
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final marker = matched ? '  >>> MATCH <<<' : '';
    print('sha256("$candidate"):');
    print('  first 8 bytes: $first8');
    print('  hex: $hexStr$marker');
    print('');
  }
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
