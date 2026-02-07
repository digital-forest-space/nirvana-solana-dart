import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Auto-fetch Samsara/Mayflower PDA seeds from the web app's JS bundles
/// and compare against our local definitions.
///
/// Usage: dart scripts/samsara/check_pda_seeds.dart [--verbose] [--json]
///
/// This script:
/// 1. Fetches the Samsara earn page HTML
/// 2. Extracts JS chunk URLs from script tags
/// 3. Downloads chunks until it finds the one containing PDA class definitions
/// 4. Extracts all seed strings from findProgramAddress calls
/// 5. Compares against our known seeds (from pda.dart / pda_seeds.md)
/// 6. Reports matches, mismatches, and new seeds
///
/// See docs/samsara/pda_seeds.md for background on the discovery method.

const _baseUrl = 'https://samsara.nirvana.finance';
const _earnPage = '/solana/markets/SOL/earn';

/// Our known Samsara PDA seed strings (from lib/src/samsara/pda.dart).
/// Only the string literal seeds are listed (not the pubkey parameters).
const _knownSamsaraSeeds = {
  'logCounter': ['log_counter'],
  'tenant': ['tenant'],
  'market': ['market'],
  'marketCashEscrow': ['cash_escrow'],
  'personalGovAccount': ['personal_gov_account'],
  'personalGovPranaEscrow': ['prana_escrow'],
  'personalZenEscrow': ['zen_escrow'],
};

/// Our known Mayflower PDA seed strings (from docs/samsara/pda_seeds.md).
/// Only the string literal seeds are listed (not the pubkey parameters).
const _knownMayflowerSeeds = {
  'logAccount': ['log'],
  'tenant': ['tenant'],
  'marketGroup': ['market_group'],
  'market': ['market'],
  'marketMeta': ['market_meta'],
  'marketLinear': ['market_linear'],
  'marketMulti': ['market_multi_curve'],
  'mintOptions': ['mint_options'],
  'liqVaultMain': ['liq_vault_main'],
  'revEscrowGroup': ['rev_escrow_group'],
  'revEscrowTenant': ['rev_escrow_tenant'],
  'personalPosition': ['personal_position'],
  'personalPositionEscrow': ['personal_position_escrow'],
};

void main(List<String> args) async {
  final verbose = args.contains('--verbose');
  final jsonOutput = args.contains('--json');

  if (verbose) LogService.log('Fetching earn page to discover JS chunks...');

  // 1. Fetch the earn page HTML
  final pageResponse = await http.get(Uri.parse('$_baseUrl$_earnPage'));
  if (pageResponse.statusCode != 200) {
    _fail(jsonOutput, 'Failed to fetch earn page: HTTP ${pageResponse.statusCode}');
  }

  // 2. Extract JS chunk URLs
  final chunkPattern = RegExp(r'_next/static/chunks/[^"]+\.js');
  final chunkUrls = chunkPattern
      .allMatches(pageResponse.body)
      .map((m) => m.group(0)!)
      .toSet()
      .toList();

  if (verbose) LogService.log('Found ${chunkUrls.length} JS chunks');

  // 3. Download chunks until we find the PDA one
  String? pdaChunkUrl;
  String? pdaChunkContent;
  String? idlVersion;

  for (final chunkPath in chunkUrls) {
    final url = '$_baseUrl/$chunkPath';
    if (verbose) LogService.log('  Checking $chunkPath ...');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) continue;

    final body = response.body;
    if (body.contains('SamsaraPda') && body.contains('MayflowerPda')) {
      pdaChunkUrl = chunkPath;
      pdaChunkContent = body;
      if (verbose) LogService.log('  -> Found PDA chunk: $chunkPath (${body.length} bytes)');

      // Extract IDL version
      final idlMatch = RegExp(r't\.IDL=\{version:"([^"]+)"').firstMatch(body);
      idlVersion = idlMatch?.group(1);
      break;
    }
  }

  if (pdaChunkContent == null) {
    _fail(jsonOutput, 'Could not find JS chunk containing PDA definitions');
  }

  // 4. Split on semicolons and extract seed definitions
  final lines = pdaChunkContent.split(';');

  // Find the MayflowerPda class block and SamsaraPda class block
  final remoteSamsara = _extractSeeds(lines, 'SamsaraPda');
  final remoteMayflower = _extractSeeds(lines, 'MayflowerPda');

  if (verbose) {
    LogService.log('\nExtracted from JS bundle:');
    LogService.log('  IDL version: ${idlVersion ?? "unknown"}');
    LogService.log('  Samsara seeds: ${remoteSamsara.length} methods');
    for (final e in remoteSamsara.entries) {
      LogService.log('    ${e.key}: ${e.value}');
    }
    LogService.log('  Mayflower seeds: ${remoteMayflower.length} methods');
    for (final e in remoteMayflower.entries) {
      LogService.log('    ${e.key}: ${e.value}');
    }
  }

  // 5. Compare
  final samsaraResult = _compare('Samsara', _knownSamsaraSeeds, remoteSamsara);
  final mayflowerResult = _compare('Mayflower', _knownMayflowerSeeds, remoteMayflower);

  final allMatch = samsaraResult['match'] == true && mayflowerResult['match'] == true;

  if (verbose) {
    LogService.log('\n=== Comparison Results ===');
    _printComparison('Samsara', samsaraResult);
    _printComparison('Mayflower', mayflowerResult);
    LogService.log('');
    if (allMatch) {
      LogService.log('All PDA seeds match.');
    } else {
      LogService.log('WARNING: PDA seed mismatches detected! Update pda.dart and pda_seeds.md.');
    }
  }

  final output = {
    'success': true,
    'allMatch': allMatch,
    'idlVersion': idlVersion,
    'chunkUrl': pdaChunkUrl,
    'samsara': samsaraResult,
    'mayflower': mayflowerResult,
  };

  LogService.log(jsonEncode(output));
  exit(allMatch ? 0 : 1);
}

/// Extracts PDA seed definitions from split JS lines for a given class name.
///
/// The minified class spans multiple ;-separated lines:
///   line N:   class X{findProgramAddress(e){...}method1(e){...
///   line N+1: return this.findProgramAddress([n.from("seed"),...
///   ...
///   line N+K: ...}constructor(e){...}}t.ClassName=X},...
///
/// We collect all lines from the class start to the t.ClassName= assignment,
/// concatenate them, then extract method name + seed pairs.
Map<String, List<String>> _extractSeeds(List<String> lines, String className) {
  final seeds = <String, List<String>>{};

  // Find the range of lines containing this class
  int startLine = -1;
  int endLine = -1;

  for (var i = 0; i < lines.length; i++) {
    // Class starts with: class <var>{findProgramAddress
    if (startLine == -1 &&
        lines[i].contains('findProgramAddress') &&
        lines[i].contains(RegExp(r'class \w+\{'))) {
      // Check that this class ends with t.ClassName= (might be on a later line)
      for (var j = i; j < lines.length && j < i + 30; j++) {
        if (lines[j].contains('t.$className=')) {
          startLine = i;
          endLine = j;
          break;
        }
      }
    }
  }

  if (startLine == -1) return seeds;

  // Concatenate all lines in the class block
  final classBlock = lines.sublist(startLine, endLine + 1).join(';');

  // Extract method -> seed pairs
  // The class block looks like:
  //   logCounter(){return this.findProgramAddress([n.from("log_counter")])}
  //   tenant(e){let{seedAddress:t}=e;return this.findProgramAddress([n.from("tenant"),t.toBuffer()])}
  //
  // Strategy: find each `this.findProgramAddress([...])` call, then look
  // backwards for the method name.
  final fpPattern = RegExp(r'this\.findProgramAddress\(\[([^\]]+)\]');

  for (final match in fpPattern.allMatches(classBlock)) {
    final seedsStr = match.group(1)!;

    // Extract seed strings
    final seedPattern = RegExp(r'n\.from\("([^"]+)"\)');
    final seedList = seedPattern
        .allMatches(seedsStr)
        .map((m) => m.group(1)!)
        .toList();
    if (seedList.isEmpty) continue;

    // Look backwards from the match start to find the method name.
    // Pattern: methodName(args){ ... potentially with nested {}'s from
    // destructuring like let{seedAddress:t}=e;
    final before = classBlock.substring(0, match.start);
    // Find the last method declaration: word( before our match
    final methodMatch = RegExp(r'(\w+)\([^)]*\)\{').allMatches(before).lastOrNull;
    if (methodMatch == null) continue;

    final methodName = methodMatch.group(1)!;
    if (methodName == 'findProgramAddress') continue;

    seeds[methodName] = seedList;
  }

  return seeds;
}

/// Compares known seeds against remote seeds.
Map<String, dynamic> _compare(
  String program,
  Map<String, List<String>> known,
  Map<String, List<String>> remote,
) {
  final matching = <String>[];
  final mismatched = <String, Map<String, dynamic>>{};
  final missing = <String>[]; // in known but not remote
  final added = <String, List<String>>{}; // in remote but not known

  for (final entry in known.entries) {
    final name = entry.key;
    if (!remote.containsKey(name)) {
      missing.add(name);
      continue;
    }
    final remoteSeeds = remote[name]!;
    if (_listEquals(entry.value, remoteSeeds)) {
      matching.add(name);
    } else {
      mismatched[name] = {
        'known': entry.value,
        'remote': remoteSeeds,
      };
    }
  }

  for (final entry in remote.entries) {
    if (!known.containsKey(entry.key)) {
      added[entry.key] = entry.value;
    }
  }

  return {
    'match': mismatched.isEmpty && missing.isEmpty,
    'matching': matching,
    'mismatched': mismatched.isEmpty ? null : mismatched,
    'missing': missing.isEmpty ? null : missing,
    'added': added.isEmpty ? null : added,
  };
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _printComparison(String program, Map<String, dynamic> result) {
  LogService.log('\n$program:');
  final matching = result['matching'] as List;
  LogService.log('  Matching: ${matching.length} (${matching.join(", ")})');

  final mismatched = result['mismatched'] as Map<String, dynamic>?;
  if (mismatched != null) {
    LogService.log('  MISMATCHED: ${mismatched.length}');
    for (final e in mismatched.entries) {
      final info = e.value as Map<String, dynamic>;
      LogService.log('    ${e.key}: known=${info["known"]} remote=${info["remote"]}');
    }
  }

  final missing = result['missing'] as List?;
  if (missing != null) {
    LogService.log('  MISSING from remote: ${missing.join(", ")}');
  }

  final added = result['added'] as Map<String, dynamic>?;
  if (added != null) {
    LogService.log('  NEW in remote: ${added.length}');
    for (final e in added.entries) {
      LogService.log('    ${e.key}: ${e.value}');
    }
  }
}

Never _fail(bool jsonOutput, String message) {
  if (jsonOutput) {
    LogService.log(jsonEncode({'success': false, 'error': message}));
  } else {
    LogService.log('ERROR: $message');
  }
  exit(1);
}
