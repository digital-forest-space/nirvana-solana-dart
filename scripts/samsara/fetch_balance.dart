import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch navToken balances (wallet + staked) and base token balance for a market.
///
/// Usage: dart scripts/samsara/fetch_balance.dart <keypair_path> --market <name> [--rpc <url>] [--verbose]
///
/// Without --market, lists available market names and exits.
///
/// Examples:
///   dart scripts/samsara/fetch_balance.dart ~/.config/solana/id.json --market navSOL
///   dart scripts/samsara/fetch_balance.dart ~/.config/solana/id.json --market navSOL --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  String? rpcUrl;
  String? marketName;
  String? keypairPath;
  bool verbose = false;

  // Parse positional arg (keypair path) and flags
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--rpc' && i + 1 < args.length) {
      rpcUrl = args[i + 1];
      i++;
    } else if (args[i] == '--market' && i + 1 < args.length) {
      marketName = args[i + 1];
      i++;
    } else if (args[i] == '--verbose') {
      verbose = true;
    } else if (!args[i].startsWith('--') && keypairPath == null) {
      keypairPath = args[i];
    }
  }

  // No market specified: list available markets and exit
  if (marketName == null || keypairPath == null) {
    print('Usage: dart scripts/samsara/fetch_balance.dart <keypair_path> --market <name> [--rpc <url>] [--verbose]');
    print('');
    print('Available markets:');
    for (final name in NavTokenMarket.availableMarkets) {
      print('  $name');
    }
    exit(0);
  }

  final market = NavTokenMarket.byName(marketName);
  if (market == null) {
    print(jsonEncode({'success': false, 'error': 'Unknown market: $marketName'}));
    exit(1);
  }

  // Load keypair (only need the public key)
  final keypairFile = File(keypairPath);
  if (!keypairFile.existsSync()) {
    print(jsonEncode({'success': false, 'error': 'Keypair file not found: $keypairPath'}));
    exit(1);
  }

  if (verbose) print('Loading keypair from $keypairPath...');
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  if (verbose) print('Wallet: $userPubkey');

  // Create SamsaraClient
  rpcUrl ??= Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  if (verbose) print('RPC: $rpcUrl');
  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
  final client = SamsaraClient(rpcClient: rpcClient);

  const batchSize = 30;
  final isNativeSol = market.baseMint == 'So11111111111111111111111111111111111111112';
  final accountCount = isNativeSol ? 3 : 4;
  final batchCount = (accountCount / batchSize).ceil();

  if (verbose) {
    print('\nFetching balances for ${market.name}...');
    print('  Accounts: $accountCount (wallet, navATA, escrow${isNativeSol ? '' : ', baseATA'})');
    print('  Batch size: $batchSize, batches: $batchCount, RPC calls: $batchCount');
  }

  try {
    final balances = await client.fetchMarketBalances(
      userPubkey: userPubkey,
      market: market,
      batchSize: batchSize,
    );

    if (verbose) {
      final navDecimals = market.navDecimals > 6 ? 8 : 6;
      final baseDecimals = market.baseDecimals > 6 ? 8 : 6;
      print('');
      print('${market.name} (wallet): ${balances[market.name]!.toStringAsFixed(navDecimals)}');
      print('${market.name} (staked): ${balances['${market.name}_staked']!.toStringAsFixed(navDecimals)}');
      print('${market.baseName}: ${balances[market.baseName]!.toStringAsFixed(baseDecimals)}');
    }

    print(jsonEncode({
      'success': true,
      'market': market.name,
      'wallet': userPubkey,
      market.name: balances[market.name],
      '${market.name}_staked': balances['${market.name}_staked'],
      market.baseName: balances[market.baseName],
    }));
  } catch (e) {
    if (verbose) {
      print('\nFailed to fetch balances!');
      print('  Error: $e');
    }
    print(jsonEncode({
      'success': false,
      'error': e.toString(),
    }));
    exit(1);
  }

  exit(0);
}
