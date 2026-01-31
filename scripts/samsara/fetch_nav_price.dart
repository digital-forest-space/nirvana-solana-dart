import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/models/transaction_price_result.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch the latest navToken price and floor price for any Samsara market.
///
/// Usage: dart scripts/samsara/fetch_nav_price.dart --market <name> [--rpc <url>] [--verbose]
///
/// Without --market, lists available market names and exits.
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

  // No market specified: list available markets and exit
  if (marketName == null) {
    print('Available markets:');
    for (final name in NavTokenMarket.availableMarkets) {
      print('  $name');
    }
    print('\nUsage: dart scripts/samsara/fetch_nav_price.dart --market <name> [--verbose]');
    exit(0);
  }

  final market = NavTokenMarket.byName(marketName);
  if (market == null) {
    stderr.writeln('Unknown market: $marketName');
    stderr.writeln('Available markets: ${NavTokenMarket.availableMarkets.join(', ')}');
    exit(1);
  }

  rpcUrl ??= Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  if (verbose) {
    print('Fetching ${market.name} prices...');
    print('RPC: $rpcUrl');
    print('');
    print('Market: ${market.name}');
    print('Querying signatures for market: ${market.mayflowerMarket}');
    print('');
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

  // Fetch market price and floor price in parallel
  final results = await Future.wait([
    client.fetchLatestNavTokenPriceWithPaging(
      market,
      pageSize: 10,
      initialDelayMs: 200,
    ),
    client.fetchFloorPrice(market),
  ]);

  final priceResult = results[0] as TransactionPriceResult;
  final floorPrice = results[1] as double;

  if (verbose) {
    final decimals = market.baseDecimals > 6 ? 8 : 6;
    print('Floor price: ${floorPrice.toStringAsFixed(decimals)} ${market.baseName}');
    if (priceResult.hasPrice) {
      print('Market price: ${priceResult.price!.toStringAsFixed(decimals)} ${market.baseName}');
      print('Transaction: ${priceResult.signature}');
    } else if (priceResult.hasError) {
      print('Market price error: ${priceResult.errorMessage}');
    } else {
      print('Market price status: ${priceResult.status}');
    }
  }

  final json = <String, dynamic>{
    'market': market.name,
    'currency': market.baseName,
    'floor': floorPrice,
    'status': priceResult.status.name,
  };

  if (priceResult.hasPrice) {
    json['price'] = priceResult.price;
    json['signature'] = priceResult.signature;
  } else if (priceResult.hasError) {
    json['error'] = priceResult.errorMessage;
  }

  print(jsonEncode(json));
  exit(0);
}
