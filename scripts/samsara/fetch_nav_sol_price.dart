import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/samsara/samsara_client.dart';
import 'package:nirvana_solana/src/models/transaction_price_result.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Fetch the latest navSOL price and floor price
///
/// Usage: dart scripts/samsara/fetch_nav_sol_price.dart [--rpc <url>] [--verbose]
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  // Parse args
  String? rpcUrl;
  bool verbose = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--rpc' && i + 1 < args.length) {
      rpcUrl = args[i + 1];
      i++;
    } else if (args[i] == '--verbose') {
      verbose = true;
    }
  }

  rpcUrl ??= Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  if (verbose) {
    print('Fetching navSOL prices...');
    print('RPC: $rpcUrl');
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
  final market = NavTokenMarket.navSol();

  if (verbose) {
    print('Market: ${market.name}');
    print('Querying signatures for market: ${market.mayflowerMarket}');
    print('');
  }

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
    print('Floor price: ${floorPrice.toStringAsFixed(6)} ${market.baseName}');
    if (priceResult.hasPrice) {
      print('Market price: ${priceResult.price!.toStringAsFixed(6)} ${market.baseName}');
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
