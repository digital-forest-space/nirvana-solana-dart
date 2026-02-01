import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/pda.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Discover all Samsara navToken markets from on-chain data.
///
/// Usage: dart scripts/samsara/discover_markets.dart [--verbose] [--health]
///
/// Queries getProgramAccounts for all Mayflower Market accounts (304 bytes),
/// then fetches each market's Market Metadata to extract mints and vaults,
/// and resolves token names via Metaplex Token Metadata.
///
/// With --health, also fetches per-market health signals (extra RPC calls):
///   - navSupply: total circulating supply of the nav token
///   - baseVaultBalance: base token balance in the market vault
///   - lastTxTime: unix timestamp of the most recent transaction
///
/// Market Metadata layout (488 bytes, discovered from navSOL reference):
///   offset   8: baseMint (32 bytes)
///   offset  40: navMint (32 bytes)
///   offset 104: marketGroup (32 bytes)
///   offset 136: mayflowerMarket (32 bytes)
///   offset 200: baseVault (32 bytes)
///   offset 232: navVault (32 bytes)
///   offset 264: feeVault (32 bytes)
///
/// Mayflower Market layout (304 bytes):
///   offset   8: marketMetadata (32 bytes)
///   offset 104: floorPrice (16 bytes, Rust Decimal)

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
  final config = SamsaraConfig.mainnet();
  final pda = SamsaraPda.mainnet();

  if (verbose) print('Fetching all Mayflower Market accounts...\n');

  final mayflowerMarkets = await rpcClient.getProgramAccounts(
    config.mayflowerProgramId,
    dataSize: 304,
  );

  if (verbose) print('Found ${mayflowerMarkets.length} markets\n');

  // Collect all nav and base mints for batch metadata lookup
  final results = <Map<String, dynamic>>[];
  final allMints = <String>{};

  for (final marketAccount in mayflowerMarkets) {
    final mayflowerPubkey = marketAccount['pubkey'] as String;
    final marketBytes = _decodeAccountData(marketAccount['account']);

    final metadataPubkey = _bytesToBase58(marketBytes.sublist(8, 40));
    final floorPrice = _decodeRustDecimal(marketBytes.sublist(104, 120));

    await Future.delayed(const Duration(milliseconds: 500));
    final mdInfo = await rpcClient.getAccountInfo(metadataPubkey);
    final mdBytes = _decodeAccountData(mdInfo);
    if (mdBytes.length < 296) continue;

    final baseMint = _bytesToBase58(mdBytes.sublist(8, 40));
    final navMint = _bytesToBase58(mdBytes.sublist(40, 72));
    final marketGroup = _bytesToBase58(mdBytes.sublist(104, 136));
    final baseVault = _bytesToBase58(mdBytes.sublist(200, 232));
    final navVault = _bytesToBase58(mdBytes.sublist(232, 264));
    final feeVault = _bytesToBase58(mdBytes.sublist(264, 296));

    allMints.add(navMint);
    allMints.add(baseMint);

    // Derive Samsara market address from marketMetadata PDA
    final samsaraMarket = await pda.market(
      marketMeta: Ed25519HDPublicKey.fromBase58(metadataPubkey),
    );

    results.add({
      'mayflowerMarket': mayflowerPubkey,
      'samsaraMarket': samsaraMarket.toBase58(),
      'marketMetadata': metadataPubkey,
      'baseMint': baseMint,
      'navMint': navMint,
      'marketGroup': marketGroup,
      'baseVault': baseVault,
      'navVault': navVault,
      'feeVault': feeVault,
      'floorPrice': floorPrice,
    });
  }

  // Build lookup of configured markets by navMint for comparison
  final configByNavMint = <String, NavTokenMarket>{};
  for (final m in NavTokenMarket.all.values) {
    configByNavMint[m.navMint] = m;
  }

  // Resolve Metaplex token metadata for all mints
  if (verbose) print('Resolving token names for ${allMints.length} mints...\n');
  final tokenNames = await _resolveTokenNames(rpcClient, allMints.toList());

  // Attach names to results
  for (final m in results) {
    final navMint = m['navMint'] as String;
    final baseMint = m['baseMint'] as String;
    final navMeta = tokenNames[navMint];
    final baseMeta = tokenNames[baseMint];
    if (navMeta != null) {
      m['navName'] = navMeta['name'];
      m['navSymbol'] = navMeta['symbol'];
    }
    if (baseMeta != null) {
      m['baseName'] = baseMeta['name'];
      m['baseSymbol'] = baseMeta['symbol'];
    }
  }

  // Check each market against library config
  for (final m in results) {
    final navMint = m['navMint'] as String;
    final cfg = configByNavMint[navMint];
    m['supported'] = cfg != null;

    if (cfg != null) {
      final mismatches = <String>[];
      if (cfg.mayflowerMarket != m['mayflowerMarket']) mismatches.add('mayflowerMarket');
      if (cfg.samsaraMarket != m['samsaraMarket']) mismatches.add('samsaraMarket');
      if (cfg.marketMetadata != m['marketMetadata']) mismatches.add('marketMetadata');
      if (cfg.baseMint != m['baseMint']) mismatches.add('baseMint');
      if (cfg.marketGroup != m['marketGroup']) mismatches.add('marketGroup');
      if (cfg.marketSolVault != m['baseVault']) mismatches.add('baseVault');
      if (cfg.marketNavVault != m['navVault']) mismatches.add('navVault');
      if (cfg.feeVault != m['feeVault']) mismatches.add('feeVault');
      m['configMatch'] = mismatches.isEmpty;
      if (mismatches.isNotEmpty) {
        m['configMismatches'] = mismatches;
      }
    } else {
      m['configMatch'] = null;
    }
  }

  // Health signals: nav supply, vault balance, transaction recency
  if (health) {
    if (verbose) print('Fetching health signals for ${results.length} markets...\n');
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
    print('=== Discovered Markets ===\n');
    for (final m in results) {
      final navLabel = m['navSymbol'] ?? m['navMint'];
      final baseLabel = m['baseSymbol'] ?? m['baseMint'];
      print('$navLabel / $baseLabel  (floor: ${(m['floorPrice'] as double).toStringAsFixed(9)})');
      if (m['navName'] != null) {
        print('  Nav Token:        ${m['navName']} (${m['navSymbol']})');
      }
      if (m['baseName'] != null) {
        print('  Base Token:       ${m['baseName']} (${m['baseSymbol']})');
      }
      print('  Mayflower Market: ${m['mayflowerMarket']}');
      print('  Samsara Market:   ${m['samsaraMarket']}');
      print('  Market Metadata:  ${m['marketMetadata']}');
      print('  Base Mint:        ${m['baseMint']}');
      print('  Nav Mint:         ${m['navMint']}');
      print('  Market Group:     ${m['marketGroup']}');
      print('  Base Vault:       ${m['baseVault']}');
      print('  Nav Vault:        ${m['navVault']}');
      print('  Fee Vault:        ${m['feeVault']}');
      final supported = m['supported'] as bool;
      final configMatch = m['configMatch'];
      print('  Supported:        $supported');
      if (supported) {
        if (configMatch == true) {
          print('  Config Match:     true');
        } else {
          final mismatches = m['configMismatches'] as List<String>? ?? [];
          print('  Config Match:     FALSE -- mismatches: ${mismatches.join(", ")}');
        }
      }
      if (health) {
        final supply = m['navSupply'];
        final vaultBal = m['baseVaultBalance'];
        final lastTx = m['lastTxTime'] as int?;
        print('  Nav Supply:       ${supply != null ? supply.toStringAsFixed(4) : 'n/a'}');
        print('  Vault Balance:    ${vaultBal != null ? vaultBal.toStringAsFixed(8) : 'n/a'}');
        if (lastTx != null) {
          final age = DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastTx * 1000));
          print('  Last Tx:          ${_formatAge(age)} ago');
        } else {
          print('  Last Tx:          n/a');
        }
      }
      print('');
    }
  }

  print(jsonEncode(results));
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
    print('  $label: supply=${market['navSupply']}, '
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

Uint8List _decodeAccountData(dynamic accountOrInfo) {
  if (accountOrInfo is Map<String, dynamic>) {
    final data = accountOrInfo['data'];
    String? base64Data;
    if (data is List) {
      base64Data = data[0] as String?;
    } else if (data is Map) {
      base64Data = data['data']?[0] as String?;
    }
    if (base64Data == null || base64Data.isEmpty) return Uint8List(0);
    return Uint8List.fromList(base64.decode(base64Data));
  }
  return Uint8List(0);
}

String _bytesToBase58(Uint8List bytes) {
  return Ed25519HDPublicKey(bytes.toList()).toBase58();
}

double _decodeRustDecimal(List<int> bytes) {
  final int scale = bytes[2];
  if (scale < 1 || scale > 28) return 0.0;

  BigInt rawValue = BigInt.zero;
  for (int i = 4; i < 16; i++) {
    rawValue |= BigInt.from(bytes[i]) << (8 * (i - 4));
  }
  if (rawValue == BigInt.zero) return 0.0;

  final BigInt divisor = BigInt.from(10).pow(scale);
  return rawValue.toDouble() / divisor.toDouble();
}
