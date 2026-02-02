import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch navToken balances (wallet + staked) and base token balance for all markets.
///
/// Usage: dart scripts/samsara/fetch_balance.dart <pubkey> [--market <name>] [--rpc <url>] [--verbose]
///
/// Without --market, fetches all markets. With --market, fetches only that market.
///
/// Examples:
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU --market navSOL --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  String? rpcUrl;
  String? marketName;
  String? userPubkey;
  bool verbose = false;

  // Parse positional arg (pubkey) and flags
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--rpc' && i + 1 < args.length) {
      rpcUrl = args[i + 1];
      i++;
    } else if (args[i] == '--market' && i + 1 < args.length) {
      marketName = args[i + 1];
      i++;
    } else if (args[i] == '--verbose') {
      verbose = true;
    } else if (!args[i].startsWith('--') && userPubkey == null) {
      userPubkey = args[i];
    }
  }

  if (userPubkey == null) {
    print('Usage: dart scripts/samsara/fetch_balance.dart <pubkey> [--market <name>] [--rpc <url>] [--verbose]');
    print('');
    print('Available markets:');
    for (final name in NavTokenMarket.availableMarkets) {
      print('  $name');
    }
    exit(0);
  }

  // Resolve which markets to fetch
  List<NavTokenMarket> markets;
  if (marketName != null) {
    final market = NavTokenMarket.byName(marketName);
    if (market == null) {
      print(jsonEncode({'success': false, 'error': 'Unknown market: $marketName'}));
      exit(1);
    }
    markets = [market];
  } else {
    markets = NavTokenMarket.all.values.toList();
  }

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
  const nativeSolMint = 'So11111111111111111111111111111111111111112';
  // 1 (wallet) + per market: 2 (navATA, escrow) + 1 (baseATA) if non-native
  final accountCount = 1 + markets.fold<int>(0, (sum, m) =>
      sum + (m.baseMint == nativeSolMint ? 2 : 3));
  final batchCount = (accountCount / batchSize).ceil();

  if (verbose) {
    print('\nFetching balances for ${markets.length} market(s): ${markets.map((m) => m.name).join(', ')}');
    print('  Accounts: $accountCount, batch size: $batchSize, batches: $batchCount, RPC calls: $batchCount');
  }

  try {
    final allBalances = await client.fetchAllMarketBalances(
      userPubkey: userPubkey,
      markets: markets,
      batchSize: batchSize,
    );

    final resultList = <Map<String, dynamic>>[];
    for (final market in markets) {
      final balances = allBalances[market.name]!;

      if (verbose) {
        final navDecimals = market.navDecimals > 6 ? 8 : 6;
        final baseDecimals = market.baseDecimals > 6 ? 8 : 6;
        print('');
        print('${market.name} (wallet): ${balances[market.name]!.toStringAsFixed(navDecimals)}');
        print('${market.name} (staked): ${balances['${market.name}_staked']!.toStringAsFixed(navDecimals)}');
        print('${market.baseName}: ${balances[market.baseName]!.toStringAsFixed(baseDecimals)}');
      }

      resultList.add({
        'market': market.name,
        market.name: balances[market.name],
        '${market.name}_staked': balances['${market.name}_staked'],
        market.baseName: balances[market.baseName],
      });
    }

    print(jsonEncode({
      'success': true,
      'wallet': userPubkey,
      'accounts': accountCount,
      'batches': batchCount,
      'markets': resultList,
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
