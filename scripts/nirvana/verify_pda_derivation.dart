import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/nirvana/pda.dart';
import 'package:nirvana_solana/src/models/config.dart';

/// Verify Nirvana PDA derivation against known on-chain accounts.
///
/// Usage: dart scripts/nirvana/verify_pda_derivation.dart [--rpc <url>] [--verbose]
///
/// This script derives all singleton and user-specific PDAs using our NirvanaPda
/// class and compares them against the known accounts from config.dart and
/// on-chain data.

void main(List<String> args) async {
  final verbose = args.contains('--verbose');
  final rpcIdx = args.indexOf('--rpc');
  final rpcUrl = rpcIdx >= 0 && rpcIdx + 1 < args.length
      ? args[rpcIdx + 1]
      : Platform.environment['SOLANA_RPC_URL'] ??
          'https://api.mainnet-beta.solana.com';

  final config = NirvanaConfig.mainnet();
  final pda = NirvanaPda.mainnet();
  final tenantKey = Ed25519HDPublicKey.fromBase58(config.tenantAccount);

  final results = <Map<String, dynamic>>[];
  var allMatch = true;

  // 1. Verify priceCurve PDA
  if (verbose) LogService.log('Deriving priceCurve PDA...');
  final derivedPriceCurve = await pda.priceCurve(tenant: tenantKey);
  final priceCurveMatch = derivedPriceCurve.toBase58() == config.priceCurve;
  if (!priceCurveMatch) allMatch = false;
  results.add({
    'name': 'priceCurve',
    'derived': derivedPriceCurve.toBase58(),
    'expected': config.priceCurve,
    'match': priceCurveMatch,
  });
  if (verbose) {
    LogService.log('  Derived:  ${derivedPriceCurve.toBase58()}');
    LogService.log('  Expected: ${config.priceCurve}');
    LogService.log('  Match:    $priceCurveMatch');
  }

  // 2. Verify curveBallot PDA (no known address, just check it derives)
  if (verbose) LogService.log('\nDeriving curveBallot PDA...');
  final derivedCurveBallot = await pda.curveBallot(tenant: tenantKey);
  results.add({
    'name': 'curveBallot',
    'derived': derivedCurveBallot.toBase58(),
    'note': 'No known address to compare - checking on-chain existence',
  });
  if (verbose) {
    LogService.log('  Derived: ${derivedCurveBallot.toBase58()}');
  }

  // 3. Check on-chain existence of derived accounts
  if (verbose) LogService.log('\nChecking on-chain existence of derived accounts...');
  final accountsToCheck = {
    'priceCurve': derivedPriceCurve.toBase58(),
    'curveBallot': derivedCurveBallot.toBase58(),
  };

  for (final entry in accountsToCheck.entries) {
    final info = await _getAccountInfo(rpcUrl, entry.value);
    final exists = info != null;
    if (verbose) {
      LogService.log('  ${entry.key} (${entry.value}): ${exists ? "EXISTS" : "NOT FOUND"}');
      if (exists) {
        final owner = info['owner'];
        final dataLen = (info['data'] as List?)?.isNotEmpty == true
            ? (info['data'][0] as String).length
            : 0;
        LogService.log('    Owner: $owner');
        LogService.log('    Data length: ~${dataLen ~/ 2} bytes (base64)');
      }
    }
  }

  // 4. Find a known user's personalAccount via getProgramAccounts
  // and verify it matches our NirvanaPda.personalAccount() derivation
  if (verbose) LogService.log('\nSearching for a user personalAccount to verify derivation...');
  final programAccounts = await _getProgramAccounts(rpcUrl, config.programId, 272);

  if (programAccounts.isNotEmpty) {
    final account = programAccounts.first;
    final accountPubkey = account['pubkey'] as String;
    final data = account['data'] as String;

    final bytes = base64Decode(data);
    if (bytes.length >= 72) {
      final ownerBytes = bytes.sublist(8, 40);
      final ownerKey = Ed25519HDPublicKey(ownerBytes.toList());
      final userPubkey = ownerKey.toBase58();

      final onChainTenantBytes = bytes.sublist(40, 72);
      final onChainTenantKey = Ed25519HDPublicKey(onChainTenantBytes.toList());

      if (verbose) {
        LogService.log('  Found account: $accountPubkey');
        LogService.log('  Owner (offset 8):  $userPubkey');
        LogService.log('  Tenant (offset 40): ${onChainTenantKey.toBase58()}');
        if (onChainTenantKey.toBase58() != config.tenantAccount) {
          LogService.log('  WARNING: on-chain tenant differs from config tenant (${config.tenantAccount})');
        }
      }

      // Derive using the tenant stored in the account (not config)
      final derivedPersonal = await pda.personalAccount(
        tenant: onChainTenantKey,
        owner: ownerKey,
      );

      final personalMatch = derivedPersonal.toBase58() == accountPubkey;
      if (!personalMatch) allMatch = false;
      results.add({
        'name': 'personalAccount',
        'user': userPubkey,
        'derived': derivedPersonal.toBase58(),
        'expected': accountPubkey,
        'match': personalMatch,
      });
      if (verbose) {
        LogService.log('  Derived:  ${derivedPersonal.toBase58()}');
        LogService.log('  Expected: $accountPubkey');
        LogService.log('  Match:    $personalMatch');
      }
    }
  } else {
    if (verbose) LogService.log('  No personalAccount found via getProgramAccounts');
  }

  // Summary
  if (verbose) {
    LogService.log('\n=== Results ===');
    for (final r in results) {
      final match = r['match'];
      final status = match == null ? '?' : (match ? 'OK' : 'FAIL');
      LogService.log('  [$status] ${r['name']}: ${r['derived']}');
    }
    LogService.log('');
    LogService.log(allMatch ? 'All verifiable PDAs match.' : 'WARNING: Some PDAs do not match!');
  }

  final output = {
    'success': true,
    'allMatch': allMatch,
    'results': results,
  };

  LogService.log(jsonEncode(output));
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
    String rpcUrl, String programId, int dataSize) async {
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
          'filters': [
            {'dataSize': dataSize},
          ],
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
