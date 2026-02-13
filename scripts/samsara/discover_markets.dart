import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Discover all Samsara navToken markets from on-chain data.
///
/// Usage: dart scripts/samsara/discover_markets.dart [--verbose] [--health]
///
/// Uses [SamsaraClient.discoverMarkets] for core discovery (3 RPC calls),
/// then enriches with Metaplex token names, config comparison, and optional
/// health signals (navSupply, baseVaultBalance, lastTxTime).

const _metaplexProgramId = 'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s';

void main(List<String> args) async {
  final rpcUrl = Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';
  final verbose = args.contains('--verbose');
  final health = args.contains('--health');

  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
  final client = SamsaraClient(rpcClient: rpcClient);

  if (verbose) LogService.log('Discovering markets via SamsaraClient...\n');

  // Core discovery: 3 batched RPC calls
  final discovered = await client.discoverMarkets();

  if (verbose) LogService.log('Found ${discovered.length} markets\n');

  // Collect all mints for Metaplex name resolution
  final allMints = <String>{};
  for (final m in discovered) {
    allMints.add(m.navMint);
    allMints.add(m.baseMint);
  }

  // Resolve Metaplex token metadata (overrides library well-known names)
  if (verbose) LogService.log('Resolving token names for ${allMints.length} mints...\n');
  final tokenNames = await _resolveTokenNames(rpcClient, allMints.toList());

  // Fetch floor prices in one batched RPC call
  final floorPrices = await client.fetchAllFloorPrices(markets: discovered);

  // Build lookup of configured markets by navMint for comparison
  final configByNavMint = <String, NavTokenMarket>{};
  for (final m in NavTokenMarket.all.values) {
    configByNavMint[m.navMint] = m;
  }

  // Build enriched results
  final results = <Map<String, dynamic>>[];
  for (final m in discovered) {
    final navMeta = tokenNames[m.navMint];
    final baseMeta = tokenNames[m.baseMint];

    final result = <String, dynamic>{
      'mayflowerMarket': m.mayflowerMarket,
      'samsaraMarket': m.samsaraMarket,
      'marketMetadata': m.marketMetadata,
      'baseMint': m.baseMint,
      'navMint': m.navMint,
      'marketGroup': m.marketGroup,
      'baseVault': m.marketSolVault,
      'navVault': m.marketNavVault,
      'feeVault': m.feeVault,
      'authorityPda': m.authorityPda,
      'baseDecimals': m.baseDecimals,
      'navDecimals': m.navDecimals,
      'floorPrice': floorPrices[m.name] ?? 0.0,
    };

    // Attach Metaplex names (override library well-known names when available)
    if (navMeta != null) {
      result['navName'] = navMeta['name'];
      result['navSymbol'] = navMeta['symbol'];
    } else {
      result['navSymbol'] = m.name;
    }
    if (baseMeta != null) {
      result['baseName'] = baseMeta['name'];
      result['baseSymbol'] = baseMeta['symbol'];
    } else {
      result['baseSymbol'] = m.baseName;
    }

    // Config comparison
    final cfg = configByNavMint[m.navMint];
    result['supported'] = cfg != null;

    if (cfg != null) {
      final mismatches = <String>[];
      if (cfg.mayflowerMarket != m.mayflowerMarket) mismatches.add('mayflowerMarket');
      if (cfg.samsaraMarket != m.samsaraMarket) mismatches.add('samsaraMarket');
      if (cfg.marketMetadata != m.marketMetadata) mismatches.add('marketMetadata');
      if (cfg.baseMint != m.baseMint) mismatches.add('baseMint');
      if (cfg.marketGroup != m.marketGroup) mismatches.add('marketGroup');
      if (cfg.marketSolVault != m.marketSolVault) mismatches.add('baseVault');
      if (cfg.marketNavVault != m.marketNavVault) mismatches.add('navVault');
      if (cfg.feeVault != m.feeVault) mismatches.add('feeVault');
      result['configMatch'] = mismatches.isEmpty;
      if (mismatches.isNotEmpty) {
        result['configMismatches'] = mismatches;
      }
    } else {
      result['configMatch'] = null;
    }

    results.add(result);
  }

  // Health signals: nav supply, vault balance, transaction recency
  if (health) {
    if (verbose) LogService.log('Fetching health signals for ${results.length} markets...\n');
    for (final m in results) {
      await _fetchHealthSignals(m, rpcClient, uri, verbose);
    }
  } else {
    for (final m in results) {
      m['navSupply'] = null;
      m['baseVaultBalance'] = null;
      m['lastTxTime'] = null;
    }
  }

  // Sort by floor price descending (most active/valuable first)
  results.sort((a, b) =>
      (b['floorPrice'] as double).compareTo(a['floorPrice'] as double));

  if (verbose) {
    LogService.log('=== Discovered Markets ===\n');
    for (final m in results) {
      final navLabel = m['navSymbol'] ?? m['navMint'];
      final baseLabel = m['baseSymbol'] ?? m['baseMint'];
      LogService.log('$navLabel / $baseLabel  (floor: ${(m['floorPrice'] as double).toStringAsFixed(9)})');
      if (m['navName'] != null) {
        LogService.log('  Nav Token:        ${m['navName']} (${m['navSymbol']})');
      }
      if (m['baseName'] != null) {
        LogService.log('  Base Token:       ${m['baseName']} (${m['baseSymbol']})');
      }
      LogService.log('  Mayflower Market: ${m['mayflowerMarket']}');
      LogService.log('  Samsara Market:   ${m['samsaraMarket']}');
      LogService.log('  Market Metadata:  ${m['marketMetadata']}');
      LogService.log('  Base Mint:        ${m['baseMint']}');
      LogService.log('  Nav Mint:         ${m['navMint']}');
      LogService.log('  Market Group:     ${m['marketGroup']}');
      LogService.log('  Base Vault:       ${m['baseVault']}');
      LogService.log('  Nav Vault:        ${m['navVault']}');
      LogService.log('  Fee Vault:        ${m['feeVault']}');
      LogService.log('  Authority PDA:    ${m['authorityPda']}');
      final supported = m['supported'] as bool;
      final configMatch = m['configMatch'];
      LogService.log('  Supported:        $supported');
      if (supported) {
        if (configMatch == true) {
          LogService.log('  Config Match:     true');
        } else {
          final mismatches = m['configMismatches'] as List<String>? ?? [];
          LogService.log('  Config Match:     FALSE -- mismatches: ${mismatches.join(", ")}');
        }
      }
      if (health) {
        final supply = m['navSupply'];
        final vaultBal = m['baseVaultBalance'];
        final lastTx = m['lastTxTime'] as int?;
        LogService.log('  Nav Supply:       ${supply != null ? supply.toStringAsFixed(4) : 'n/a'}');
        LogService.log('  Vault Balance:    ${vaultBal != null ? vaultBal.toStringAsFixed(8) : 'n/a'}');
        if (lastTx != null) {
          final age = DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastTx * 1000));
          LogService.log('  Last Tx:          ${_formatAge(age)} ago');
        } else {
          LogService.log('  Last Tx:          n/a');
        }
      }
      LogService.log('');
    }
  }

  LogService.log(jsonEncode(results));
  exit(0);
}

String _formatAge(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

/// Fetches health signals for a single market: nav supply, vault balance,
/// and most recent transaction timestamp.
Future<void> _fetchHealthSignals(
  Map<String, dynamic> market,
  SolanaRpcClient rpcClient,
  Uri rpcUrl,
  bool verbose,
) async {
  final navMint = market['navMint'] as String;
  final baseVault = market['baseVault'] as String;
  final mayflowerMarket = market['mayflowerMarket'] as String;

  // Nav token supply
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    final supplyResult = await _rpcCall(rpcUrl, 'getTokenSupply', [navMint]);
    final uiStr = supplyResult?['value']?['uiAmountString'] as String?;
    market['navSupply'] = uiStr != null ? double.parse(uiStr) : null;
  } catch (_) {
    market['navSupply'] = null;
  }

  // Base vault balance
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    market['baseVaultBalance'] = await rpcClient.getTokenBalance(baseVault);
  } catch (_) {
    market['baseVaultBalance'] = null;
  }

  // Most recent transaction timestamp
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    final sigsResult = await _rpcCall(rpcUrl, 'getSignaturesForAddress', [
      mayflowerMarket,
      {'limit': 1},
    ]);
    final sigs = sigsResult as List?;
    if (sigs != null && sigs.isNotEmpty) {
      market['lastTxTime'] = sigs[0]['blockTime'] as int?;
    } else {
      market['lastTxTime'] = null;
    }
  } catch (_) {
    market['lastTxTime'] = null;
  }

  if (verbose) {
    final label = market['navSymbol'] ?? market['navMint'];
    LogService.log('  $label: supply=${market['navSupply']}, '
        'vault=${market['baseVaultBalance']}, '
        'lastTx=${market['lastTxTime']}');
  }
}

/// Makes a raw JSON-RPC call to the Solana RPC endpoint.
Future<dynamic> _rpcCall(Uri rpcUrl, String method, List<dynamic> params) async {
  final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await httpClient.postUrl(rpcUrl);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    }));
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw Exception('RPC error: ${data['error']}');
    }
    return data['result'];
  } finally {
    httpClient.close();
  }
}

/// Resolves Metaplex Token Metadata for a list of mint addresses.
///
/// Returns a map of mint → {name, symbol} for mints that have metadata.
Future<Map<String, Map<String, String>>> _resolveTokenNames(
  SolanaRpcClient rpcClient,
  List<String> mints,
) async {
  final metaplexProgram = Ed25519HDPublicKey.fromBase58(_metaplexProgramId);
  final result = <String, Map<String, String>>{};

  // Derive all metadata PDAs
  final pdaToMint = <String, String>{};
  final pdaAddresses = <String>[];

  for (final mint in mints) {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [
        Uint8List.fromList(utf8.encode('metadata')),
        Uint8List.fromList(metaplexProgram.bytes),
        Uint8List.fromList(Ed25519HDPublicKey.fromBase58(mint).bytes),
      ],
      programId: metaplexProgram,
    );
    final pdaStr = pda.toBase58();
    pdaToMint[pdaStr] = mint;
    pdaAddresses.add(pdaStr);
  }

  // Fetch metadata accounts individually
  for (final pdaAddress in pdaAddresses) {
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      final account = await rpcClient.getAccountInfo(pdaAddress);
      if (account.isEmpty || account['data'] == null) continue;

      final base64Data = account['data']?[0] as String?;
      if (base64Data == null || base64Data.isEmpty) continue;

      final data = Uint8List.fromList(base64Decode(base64Data));
      final parsed = _parseMetaplexMetadata(data);
      if (parsed != null) {
        final mint = pdaToMint[pdaAddress]!;
        result[mint] = parsed;
      }
    } catch (_) {
      // Skip mints without metadata
    }
  }

  return result;
}

/// Parses Metaplex Token Metadata account data.
///
/// Layout:
///   0: key (1 byte)
///   1: update authority (32 bytes)
///   33: mint (32 bytes)
///   65: name length (4 bytes LE) + name string
///   ...: symbol length (4 bytes LE) + symbol string
Map<String, String>? _parseMetaplexMetadata(Uint8List data) {
  if (data.length < 70) return null;

  final bd = data.buffer.asByteData(data.offsetInBytes);
  final nameLen = bd.getUint32(65, Endian.little);
  if (nameLen == 0 || nameLen > 100) return null;

  final name = utf8
      .decode(data.sublist(69, 69 + nameLen), allowMalformed: true)
      .replaceAll('\x00', '')
      .trim();

  final symbolOffset = 69 + nameLen;
  if (symbolOffset + 4 > data.length) return {'name': name, 'symbol': ''};

  final symbolLen = bd.getUint32(symbolOffset, Endian.little);
  if (symbolLen == 0 || symbolLen > 50) return {'name': name, 'symbol': ''};

  final symbol = utf8
      .decode(data.sublist(symbolOffset + 4, symbolOffset + 4 + symbolLen),
          allowMalformed: true)
      .replaceAll('\x00', '')
      .trim();

  return {'name': name, 'symbol': symbol};
}
