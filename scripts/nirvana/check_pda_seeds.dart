import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Auto-fetch Nirvana V2 PDA seeds from the web app's JS bundles
/// and compare against our local definitions.
///
/// Usage: dart scripts/nirvana/check_pda_seeds.dart [--verbose] [--json]
///
/// This script:
/// 1. Fetches the Nirvana app HTML
/// 2. Extracts JS chunk URLs from script tags
/// 3. Downloads chunks until it finds the one containing NvanaPda
/// 4. Extracts all seed strings from findAddress/findProgramAddress calls
/// 5. Compares against our known seeds (from lib/src/nirvana/pda.dart)
/// 6. Reports matches, mismatches, and new seeds
///
/// See docs/nirvana/pda_seeds.md for background on the discovery method.

const _baseUrl = 'https://app.nirvana.finance';

/// Our known Nirvana PDA seed strings (from lib/src/nirvana/pda.dart).
/// Only the string literal seeds are listed (not the pubkey parameters).
const _knownNirvanaSeeds = {
  'tenant': ['tenant'],
  'personalAccount': ['personal_position'],
  'priceCurve': ['price_curve'],
  'curveBallot': ['curve_ballot'],
  'personalCurveBallot': ['personal_curve_ballot'],
  'almsRewarder': ['alms_rewarder'],
  'mettaRewarder': ['metta_rewarder'],
};

void main(List<String> args) async {
  final verbose = args.contains('--verbose');
  final jsonOutput = args.contains('--json');

  if (verbose) print('Fetching Nirvana app page to discover JS chunks...');

  // 1. Fetch the app HTML
  final pageResponse = await http.get(Uri.parse(_baseUrl));
  if (pageResponse.statusCode != 200) {
    _fail(jsonOutput, 'Failed to fetch app page: HTTP ${pageResponse.statusCode}');
  }

  // 2. Extract JS chunk URLs
  final chunkPattern = RegExp(r'_next/static/chunks/[^"]+\.js');
  final chunkUrls = chunkPattern
      .allMatches(pageResponse.body)
      .map((m) => m.group(0)!)
      .toSet()
      .toList();

  if (verbose) print('Found ${chunkUrls.length} JS chunks');

  // 3. Download chunks until we find the NvanaPda one
  String? pdaChunkUrl;
  String? pdaChunkContent;

  for (final chunkPath in chunkUrls) {
    final url = '$_baseUrl/$chunkPath';
    if (verbose) print('  Checking $chunkPath ...');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) continue;

    final body = response.body;
    if (body.contains('NvanaPda') && body.contains('findAddress')) {
      pdaChunkUrl = chunkPath;
      pdaChunkContent = body;
      if (verbose) print('  -> Found PDA chunk: $chunkPath (${body.length} bytes)');
      break;
    }
  }

  if (pdaChunkContent == null) {
    _fail(jsonOutput, 'Could not find JS chunk containing NvanaPda definitions');
  }

  // 4. Split on semicolons and extract seed definitions
  final lines = pdaChunkContent.split(';');
  final remoteNirvana = _extractSeeds(lines);

  if (verbose) {
    print('\nExtracted from JS bundle:');
    print('  Nirvana seeds: ${remoteNirvana.length} methods');
    for (final e in remoteNirvana.entries) {
      print('    ${e.key}: ${e.value}');
    }
  }

  // 5. Compare
  final nirvanaResult = _compare('Nirvana', _knownNirvanaSeeds, remoteNirvana);

  final allMatch = nirvanaResult['match'] == true;

  if (verbose) {
    print('\n=== Comparison Results ===');
    _printComparison('Nirvana', nirvanaResult);
    print('');
    if (allMatch) {
      print('All PDA seeds match.');
    } else {
      print('WARNING: PDA seed mismatches detected! Update pda.dart and pda_seeds.md.');
    }
  }

  final output = {
    'success': true,
    'allMatch': allMatch,
    'chunkUrl': pdaChunkUrl,
    'nirvana': nirvanaResult,
  };

  print(jsonEncode(output));
  exit(allMatch ? 0 : 1);
}

/// Extracts PDA seed definitions from split JS lines for the NvanaPda class.
///
/// The NvanaPda class uses `this.findAddress([r.from("seed"), ...])` instead of
/// `this.findProgramAddress(...)` like the Samsara/Mayflower classes.
///
/// The minified class looks like:
///   class s{findAddress(e){return a.web3.PublicKey.findProgramAddressSync(e,this.programId)[0]}
///   tenant(e){return this.findAddress([r.from("tenant"),e.toBuffer()])}
///   personalAccount(e){let{owner:t,tenant:n}=e;return this.findAddress([r.from("personal_position"),n.toBuffer(),t.toBuffer()])}
///   ...
///   constructor(e=i.PROGRAM_ID){this.programId=e}}
Map<String, List<String>> _extractSeeds(List<String> lines) {
  final seeds = <String, List<String>>{};

  // Find the range of lines containing the NvanaPda class
  // The class contains findProgramAddressSync and is exported as NvanaPda
  int startLine = -1;
  int endLine = -1;

  for (var i = 0; i < lines.length; i++) {
    if (startLine == -1 &&
        lines[i].contains('findProgramAddressSync') &&
        lines[i].contains(RegExp(r'class \w+\{'))) {
      // Check that this class ends with NvanaPda export (might be on a later line)
      for (var j = i; j < lines.length && j < i + 30; j++) {
        if (lines[j].contains('NvanaPda')) {
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
  // NvanaPda uses `this.findAddress([...])` not `this.findProgramAddress([...])`
  final fpPattern = RegExp(r'this\.findAddress\(\[([^\]]+)\]');

  for (final match in fpPattern.allMatches(classBlock)) {
    final seedsStr = match.group(1)!;

    // Extract seed strings (r.from("...") pattern)
    final seedPattern = RegExp(r'r\.from\("([^"]+)"\)');
    final seedList = seedPattern
        .allMatches(seedsStr)
        .map((m) => m.group(1)!)
        .toList();
    if (seedList.isEmpty) continue;

    // Look backwards from the match start to find the method name
    final before = classBlock.substring(0, match.start);
    final methodMatch = RegExp(r'(\w+)\([^)]*\)\{').allMatches(before).lastOrNull;
    if (methodMatch == null) continue;

    final methodName = methodMatch.group(1)!;
    if (methodName == 'findAddress') continue;

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
  print('\n$program:');
  final matching = result['matching'] as List;
  print('  Matching: ${matching.length} (${matching.join(", ")})');

  final mismatched = result['mismatched'] as Map<String, dynamic>?;
  if (mismatched != null) {
    print('  MISMATCHED: ${mismatched.length}');
    for (final e in mismatched.entries) {
      final info = e.value as Map<String, dynamic>;
      print('    ${e.key}: known=${info["known"]} remote=${info["remote"]}');
    }
  }

  final missing = result['missing'] as List?;
  if (missing != null) {
    print('  MISSING from remote: ${missing.join(", ")}');
  }

  final added = result['added'] as Map<String, dynamic>?;
  if (added != null) {
    print('  NEW in remote: ${added.length}');
    for (final e in added.entries) {
      print('    ${e.key}: ${e.value}');
    }
  }
}

Never _fail(bool jsonOutput, String message) {
  if (jsonOutput) {
    print(jsonEncode({'success': false, 'error': message}));
  } else {
    print('ERROR: $message');
  }
  exit(1);
}
