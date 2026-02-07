import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';

import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/pda.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch navToken balances (wallet + staked), base token balance, deposited
/// prANA, unclaimed rewards, and debt for all markets.
///
/// Usage: dart scripts/samsara/fetch_balance.dart <pubkey> [--market <name>] [--active] [--raw] [--rpc <url>] [--verbose]
///
/// Without --market, fetches all markets. With --market, fetches only that market.
/// With --active, only includes markets where the user has any non-zero balance.
/// With --raw, dumps u64 fields from govAccount and personalPosition for offset discovery.
///
/// Examples:
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU --active
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU --market navSOL --verbose
///   dart scripts/samsara/fetch_balance.dart 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU --market navSOL --raw
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  String? rpcUrl;
  String? marketName;
  String? userPubkey;
  bool verbose = false;
  bool activeOnly = false;
  bool rawDump = false;

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
    } else if (args[i] == '--active') {
      activeOnly = true;
    } else if (args[i] == '--raw') {
      rawDump = true;
    } else if (!args[i].startsWith('--') && userPubkey == null) {
      userPubkey = args[i];
    }
  }

  if (userPubkey == null) {
    LogService.log('Usage: dart scripts/samsara/fetch_balance.dart <pubkey> [--market <name>] [--active] [--raw] [--rpc <url>] [--verbose]');
    LogService.log('');
    LogService.log('Available markets:');
    for (final name in NavTokenMarket.availableMarkets) {
      LogService.log('  $name');
    }
    exit(0);
  }

  // Resolve which markets to fetch
  List<NavTokenMarket> markets;
  if (marketName != null) {
    final market = NavTokenMarket.byName(marketName);
    if (market == null) {
      LogService.log(jsonEncode({'success': false, 'error': 'Unknown market: $marketName'}));
      exit(1);
    }
    markets = [market];
  } else {
    markets = NavTokenMarket.all.values.toList();
  }

  if (verbose) LogService.log('Wallet: $userPubkey');

  // Create SamsaraClient
  rpcUrl ??= Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  if (verbose) LogService.log('RPC: $rpcUrl');
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
  // 1 (wallet) + per market: 5 (navATA, escrow, pranaEscrow, govAccount, personalPosition) + 1 (baseATA) if non-native
  final accountCount = 1 + markets.fold<int>(0, (sum, m) =>
      sum + (m.baseMint == nativeSolMint ? 5 : 6));
  final batchCount = (accountCount / batchSize).ceil();

  if (verbose) {
    LogService.log('\nFetching balances for ${markets.length} market(s): ${markets.map((m) => m.name).join(', ')}');
    LogService.log('  Accounts: $accountCount, batch size: $batchSize, batches: $batchCount, RPC calls: $batchCount');
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
      final liquid = balances[market.name]!;
      final deposited = balances['${market.name}_deposited']!;
      final pranaDeposited = balances['prANA_deposited']!;
      final rewards = balances['rewards_unclaimed']!;
      final debt = balances['debt']!;

      if (activeOnly &&
          liquid == 0.0 &&
          deposited == 0.0 &&
          pranaDeposited == 0.0 &&
          debt == 0.0) {
        continue;
      }

      if (verbose) {
        final navDecimals = market.navDecimals > 6 ? 8 : 6;
        final baseDecimals = market.baseDecimals > 6 ? 8 : 6;
        LogService.log('');
        LogService.log('${market.name} (liquid): ${liquid.toStringAsFixed(navDecimals)}');
        LogService.log('${market.name} (deposited): ${deposited.toStringAsFixed(navDecimals)}');
        LogService.log('${market.baseName}: ${balances[market.baseName]!.toStringAsFixed(baseDecimals)}');
        LogService.log('prANA deposited: ${pranaDeposited.toStringAsFixed(6)}');
        LogService.log('Rewards unclaimed (${market.baseName}): ${rewards.toStringAsFixed(baseDecimals)}');
        LogService.log('Debt (${market.baseName}): ${debt.toStringAsFixed(baseDecimals)}');
      }

      resultList.add({
        'market': market.name,
        'marketAddress': market.mayflowerMarket,
        'navMint': market.navMint,
        'baseMint': market.baseMint,
        'liquid': {
          'currency': market.name,
          'amount': liquid,
        },
        'deposited': {
          'currency': market.name,
          'amount': deposited,
        },
        'base': {
          'currency': market.baseName,
          'amount': balances[market.baseName],
        },
        'pranaDeposited': {
          'currency': 'prANA',
          'amount': pranaDeposited,
        },
        'rewards': {
          'currency': market.baseName,
          'amount': rewards,
        },
        'debt': {
          'currency': market.baseName,
          'amount': debt,
        },
      });
    }

    LogService.log(jsonEncode({
      'wallet': userPubkey,
      'markets': resultList,
    }));

    // Raw dump mode: print u64 fields from govAccount and personalPosition
    // for offset discovery. Requires a separate fetch since the batched
    // response doesn't expose raw accounts to the script layer.
    if (rawDump) {
      LogService.log('\n--- Raw account field dump (offset discovery) ---');
      for (final market in markets) {
        await _dumpRawFields(
          rpcClient: rpcClient,
          userPubkey: userPubkey,
          market: market,
        );
      }
    }
  } catch (e) {
    if (verbose) {
      LogService.log('\nFailed to fetch balances!');
      LogService.log('  Error: $e');
    }
    LogService.log(jsonEncode({
      'success': false,
      'error': e.toString(),
    }));
    exit(1);
  }

  exit(0);
}

/// Fetches govAccount and personalPosition separately and dumps their
/// u64 fields for offset discovery.
Future<void> _dumpRawFields({
  required SolanaRpcClient rpcClient,
  required String userPubkey,
  required NavTokenMarket market,
}) async {
  final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
  final samsaraPda = SamsaraPda(Ed25519HDPublicKey.fromBase58(
      SamsaraConfig.mainnet().samsaraProgramId));
  final mayflowerPda = MayflowerPda(Ed25519HDPublicKey.fromBase58(
      SamsaraConfig.mainnet().mayflowerProgramId));

  final samsaraMarketKey =
      Ed25519HDPublicKey.fromBase58(market.samsaraMarket);
  final govAccountKey = await samsaraPda.personalGovAccount(
      market: samsaraMarketKey, owner: ownerKey);

  final marketMetaKey =
      Ed25519HDPublicKey.fromBase58(market.marketMetadata);
  final personalPositionKey = await mayflowerPda.personalPosition(
      marketMeta: marketMetaKey, owner: ownerKey);

  final accounts = await rpcClient.getMultipleAccounts(
      [govAccountKey.toBase58(), personalPositionKey.toBase58()]);

  final govAccount = accounts[0];
  final personalPosition = accounts[1];

  LogService.log('\n${market.name} GovAccount (${govAccountKey.toBase58()}):');
  final govFields = SamsaraClient.dumpGovAccountFields(govAccount);
  if (govFields.isEmpty) {
    LogService.log('  (not found or empty)');
  } else {
    for (final entry in govFields.entries) {
      final humanBase = entry.value / _pow10(market.baseDecimals);
      final humanPrana = entry.value / 1e6;
      LogService.log('  offset ${entry.key}: ${entry.value}'
          '  (/${market.baseName}: ${humanBase.toStringAsFixed(8)})'
          '  (/prANA: ${humanPrana.toStringAsFixed(6)})');
    }
  }

  LogService.log('\n${market.name} PersonalPosition (${personalPositionKey.toBase58()}):');
  final posFields = SamsaraClient.dumpPersonalPositionFields(personalPosition);
  if (posFields.isEmpty) {
    LogService.log('  (not found or empty)');
  } else {
    for (final entry in posFields.entries) {
      final humanBase = entry.value / _pow10(market.baseDecimals);
      LogService.log('  offset ${entry.key}: ${entry.value}'
          '  (/${market.baseName}: ${humanBase.toStringAsFixed(8)})');
    }
  }
}

double _pow10(int n) {
  double result = 1.0;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}
