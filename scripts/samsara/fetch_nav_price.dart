import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch the latest navToken price and floor price for Samsara markets.
///
/// Usage: dart scripts/samsara/fetch_nav_price.dart [--market <name>] [--rpc <url>] [--verbose]
///
/// Without --market, fetches all markets. With --market, fetches only that market.
///
/// Examples:
///   dart scripts/samsara/fetch_nav_price.dart
///   dart scripts/samsara/fetch_nav_price.dart --market navSOL
///   dart scripts/samsara/fetch_nav_price.dart --market navSOL --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  String? rpcUrl;
  String? marketName;
  bool verbose = false;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--rpc' && i + 1 < args.length) {
      rpcUrl = args[i + 1];
      i++;
    } else if (args[i] == '--market' && i + 1 < args.length) {
      marketName = args[i + 1];
      i++;
    } else if (args[i] == '--verbose') {
      verbose = true;
    }
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

  rpcUrl ??= Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  if (verbose) {
    LogService.log('Fetching prices for ${markets.length} market(s): ${markets.map((m) => m.name).join(', ')}');
    LogService.log('RPC: $rpcUrl');
  }

  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
  final client = SamsaraClient(rpcClient: rpcClient);

  try {
    // Fetch floor prices in one batched RPC call, market prices in parallel
    final floorPricesFuture = client.fetchAllFloorPrices(markets: markets);
    final priceFutures = markets.map((market) =>
      client.fetchLatestNavTokenPriceWithPaging(
        market,
        pageSize: 10,
        initialDelayMs: 200,
      )).toList();
    final priceResults = await Future.wait(priceFutures);
    final floorPrices = await floorPricesFuture;

    final resultList = <Map<String, dynamic>>[];
    for (var i = 0; i < markets.length; i++) {
      final market = markets[i];
      final priceResult = priceResults[i];
      final floorPrice = floorPrices[market.name]!;

      if (verbose) {
        final decimals = market.baseDecimals > 6 ? 8 : 6;
        LogService.log('');
        LogService.log('${market.name}:');
        LogService.log('  Floor price: ${floorPrice.toStringAsFixed(decimals)} ${market.baseName}');
        if (priceResult.hasPrice) {
          LogService.log('  Market price: ${priceResult.price!.toStringAsFixed(decimals)} ${market.baseName}');
          LogService.log('  Transaction: ${priceResult.signature}');
        } else if (priceResult.hasError) {
          LogService.log('  Market price error: ${priceResult.errorMessage}');
        } else {
          LogService.log('  Market price status: ${priceResult.status}');
        }
      }

      final entry = <String, dynamic>{
        'market': market.name,
        'marketAddress': market.mayflowerMarket,
        'navMint': market.navMint,
        'base': market.baseName,
        'baseMint': market.baseMint,
        'floor': floorPrice,
        'status': priceResult.status.name,
      };

      if (priceResult.hasPrice) {
        entry['price'] = priceResult.price;
        entry['signature'] = priceResult.signature;
      } else if (priceResult.hasError) {
        entry['error'] = priceResult.errorMessage;
      }

      resultList.add(entry);
    }

    LogService.log(jsonEncode({'markets': resultList}));
  } catch (e) {
    if (verbose) {
      LogService.log('\nFailed to fetch prices!');
      LogService.log('  Error: $e');
    }
    LogService.log(jsonEncode({'success': false, 'error': e.toString()}));
    exit(1);
  }

  exit(0);
}
