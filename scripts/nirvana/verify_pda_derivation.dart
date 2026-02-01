import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';

/// Verify Nirvana PDA derivation against known on-chain accounts.
///
/// Usage: dart scripts/nirvana/verify_pda_derivation.dart [--rpc <url>] [--verbose]
///
/// This script derives all singleton PDAs using our NirvanaPda seeds and
/// compares them against the known accounts from config.dart and on-chain data.
/// For user-specific PDAs, it uses a known user to verify derivation works.

const _programId = 'NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb';
const _tenantAccount = 'BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV';
const _priceCurve = 'Fx5u5BCTwpckbB6jBbs13nDsRabHb5bq2t2hBDszhSbd';

void main(List<String> args) async {
  final verbose = args.contains('--verbose');
  final rpcIdx = args.indexOf('--rpc');
  final rpcUrl = rpcIdx >= 0 && rpcIdx + 1 < args.length
      ? args[rpcIdx + 1]
      : Platform.environment['SOLANA_RPC_URL'] ??
          'https://api.mainnet-beta.solana.com';

  final programKey = Ed25519HDPublicKey.fromBase58(_programId);
  final tenantKey = Ed25519HDPublicKey.fromBase58(_tenantAccount);

  final results = <Map<String, dynamic>>[];
  var allMatch = true;

  // 1. Verify priceCurve PDA
  if (verbose) print('Deriving priceCurve PDA...');
  final derivedPriceCurve = await Ed25519HDPublicKey.findProgramAddress(
    seeds: ['price_curve'.codeUnits, tenantKey.bytes],
    programId: programKey,
  );
  final priceCurveMatch = derivedPriceCurve.toBase58() == _priceCurve;
  if (!priceCurveMatch) allMatch = false;
  results.add({
    'name': 'priceCurve',
    'seeds': ['price_curve', _tenantAccount],
    'derived': derivedPriceCurve.toBase58(),
    'expected': _priceCurve,
    'match': priceCurveMatch,
  });
  if (verbose) {
    print('  Derived:  ${derivedPriceCurve.toBase58()}');
    print('  Expected: $_priceCurve');
    print('  Match:    $priceCurveMatch');
  }

  // 2. Verify curveBallot PDA (no known address, just check it derives)
  if (verbose) print('\nDeriving curveBallot PDA...');
  final derivedCurveBallot = await Ed25519HDPublicKey.findProgramAddress(
    seeds: ['curve_ballot'.codeUnits, tenantKey.bytes],
    programId: programKey,
  );
  results.add({
    'name': 'curveBallot',
    'seeds': ['curve_ballot', _tenantAccount],
    'derived': derivedCurveBallot.toBase58(),
    'note': 'No known address to compare - checking on-chain existence',
  });
  if (verbose) {
    print('  Derived: ${derivedCurveBallot.toBase58()}');
  }

  // 3. Check on-chain existence of derived accounts
  if (verbose) print('\nChecking on-chain existence of derived accounts...');
  final accountsToCheck = {
    'priceCurve': derivedPriceCurve.toBase58(),
    'curveBallot': derivedCurveBallot.toBase58(),
  };

  for (final entry in accountsToCheck.entries) {
    final info = await _getAccountInfo(rpcUrl, entry.value);
    final exists = info != null;
    if (verbose) {
      print('  ${entry.key} (${entry.value}): ${exists ? "EXISTS" : "NOT FOUND"}');
      if (exists) {
        final owner = info['owner'];
        final dataLen = (info['data'] as List?)?.isNotEmpty == true
            ? (info['data'][0] as String).length
            : 0;
        print('    Owner: $owner');
        print('    Data length: ~${dataLen ~/ 2} bytes (base64)');
      }
    }
  }

  // 4. Try to find a known user's personalAccount via getProgramAccounts
  // and verify it matches our PDA derivation
  if (verbose) print('\nSearching for a user personalAccount to verify derivation...');
  final programAccounts = await _getProgramAccounts(rpcUrl, _programId, 272, 8);

  if (programAccounts.isNotEmpty) {
    // Take the first account and verify PDA derivation
    final account = programAccounts.first;
    final accountPubkey = account['pubkey'] as String;
    final data = account['data'] as String; // base64

    // Decode to get user pubkey (at offset 8, 32 bytes after discriminator)
    final bytes = base64Decode(data);
    if (bytes.length >= 40) {
      final userBytes = bytes.sublist(8, 40);
      final userKey = Ed25519HDPublicKey(userBytes.toList());
      final userPubkey = userKey.toBase58();

      if (verbose) {
        print('  Found account: $accountPubkey');
        print('  User pubkey (from data): $userPubkey');
      }

      // Derive personalAccount PDA for this user
      final derivedPersonal = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_position'.codeUnits,
          tenantKey.bytes,
          userKey.bytes,
        ],
        programId: programKey,
      );

      final personalMatch = derivedPersonal.toBase58() == accountPubkey;
      if (!personalMatch) allMatch = false;
      results.add({
        'name': 'personalAccount',
        'seeds': ['personal_position', _tenantAccount, userPubkey],
        'derived': derivedPersonal.toBase58(),
        'expected': accountPubkey,
        'match': personalMatch,
      });
      if (verbose) {
        print('  Derived:  ${derivedPersonal.toBase58()}');
        print('  Expected: $accountPubkey');
        print('  Match:    $personalMatch');
      }
    }
  } else {
    if (verbose) print('  No personalAccount found via getProgramAccounts');
  }

  // Summary
  if (verbose) {
    print('\n=== Results ===');
    for (final r in results) {
      final match = r['match'];
      final status = match == null ? '?' : (match ? 'OK' : 'FAIL');
      print('  [$status] ${r['name']}: ${r['derived']}');
    }
    print('');
    print(allMatch ? 'All verifiable PDAs match.' : 'WARNING: Some PDAs do not match!');
  }

  final output = {
    'success': true,
    'allMatch': allMatch,
    'results': results,
  };

  print(jsonEncode(output));
  exit(allMatch ? 0 : 1);
}

Future<Map<String, dynamic>?> _getAccountInfo(String rpcUrl, String pubkey) async {
  final response = await http.post(
    Uri.parse(rpcUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getAccountInfo',
      'params': [
        pubkey,
        {'encoding': 'base64'}
      ],
    }),
  );
  final result = jsonDecode(response.body);
  return result['result']?['value'] as Map<String, dynamic>?;
}

Future<List<Map<String, dynamic>>> _getProgramAccounts(
    String rpcUrl, String programId, int dataSize, int? memcmpOffset) async {
  final filters = <Map<String, dynamic>>[
    {'dataSize': dataSize},
  ];

  final response = await http.post(
    Uri.parse(rpcUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getProgramAccounts',
      'params': [
        programId,
        {
          'encoding': 'base64',
          'filters': filters,
        },
      ],
    }),
  );
  final result = jsonDecode(response.body);
  final accounts = result['result'] as List?;
  if (accounts == null || accounts.isEmpty) return [];

  return accounts.map((a) {
    final account = a['account'] as Map<String, dynamic>;
    return {
      'pubkey': a['pubkey'] as String,
      'data': (account['data'] as List)[0] as String,
      'owner': account['owner'] as String,
    };
  }).toList();
}
