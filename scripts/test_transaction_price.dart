import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nirvana_solana/nirvana_solana.dart';

/// Test script for transaction-based price fetching using the library
/// Compare output with companion's get_price_from_transaction.dart
///
/// Usage: dart scripts/test_transaction_price.dart

void main(List<String> args) async {
  final httpClient = http.Client();

  try {
    print('Testing Transaction Price Fetching via Library\n');

    final rpcClient = ScriptRpcClient(httpClient);
    final nirvanaClient = NirvanaClient(rpcClient: rpcClient);

    // Fetch latest ANA price - default params with 2s delay and rate limit retry
    print('Fetching latest ANA price (with rate limit retry handling)...\n');

    final priceResult = await nirvanaClient.fetchLatestAnaPrice();

    print('Library Results:');
    print('  Price per ANA: \$${priceResult.price.toStringAsFixed(6)}');
    print('  Transaction: ${priceResult.transaction}');
    print('  Fee: ${priceResult.fee.toStringAsFixed(6)} ANA');
    print('  Currency: ${priceResult.currency}');

    // Also fetch full prices
    print('\nFetching full prices (floor + transaction)...');
    final prices = await nirvanaClient.fetchPrices();

    print('\nFull Price Results:');
    print('  ANA price: \$${prices.ana.toStringAsFixed(6)}');
    print('  Floor price: \$${prices.floor.toStringAsFixed(6)}');
    print('  prANA price: \$${prices.prana.toStringAsFixed(6)}');

    // Output JSON for easy comparison with companion
    print('\nJSON Output:');
    print(jsonEncode({
      'transactionPrice': priceResult.price,
      'transaction': priceResult.transaction,
      'fee': priceResult.fee,
      'currency': priceResult.currency,
      'floorPrice': prices.floor,
      'ana': prices.ana,
      'prana': prices.prana,
    }));

  } catch (e, stack) {
    print('Error: $e');
    print('\nStack trace:\n$stack');
  } finally {
    httpClient.close();
  }
}

/// RPC client implementation for script usage
class ScriptRpcClient implements SolanaRpcClient {
  final http.Client _httpClient;
  final String _rpcUrl;

  ScriptRpcClient(
    this._httpClient, {
    String rpcUrl = 'https://api.mainnet-beta.solana.com',
  }) : _rpcUrl = rpcUrl;

  @override
  Future<Map<String, dynamic>> getAccountInfo(String address) async {
    final payload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getAccountInfo',
      'params': [
        address,
        {'encoding': 'base64'},
      ],
    };

    final response = await _httpClient.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP request failed with status: ${response.statusCode}');
    }

    final responseJson = jsonDecode(response.body);
    final resultValue = responseJson['result']?['value'];
    if (resultValue == null) {
      return {};
    }

    return resultValue;
  }

  @override
  Future<List<String>> getSignaturesForAddress(String address, {int limit = 100}) async {
    final payload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getSignaturesForAddress',
      'params': [
        address,
        {'limit': limit, 'commitment': 'confirmed'},
      ],
    };

    final response = await _httpClient.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP request failed with status: ${response.statusCode}');
    }

    final responseJson = jsonDecode(response.body);

    if (responseJson['error'] != null) {
      throw Exception('RPC error: ${responseJson['error']}');
    }

    final signatures = responseJson['result'] ?? [];
    return (signatures as List)
        .where((sig) => sig['err'] == null)
        .map((sig) => sig['signature'] as String)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getTransaction(String signature) async {
    final payload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getTransaction',
      'params': [
        signature,
        {
          'encoding': 'jsonParsed',
          'maxSupportedTransactionVersion': 0,
          'commitment': 'confirmed',
        },
      ],
    };

    final response = await _httpClient.post(
      Uri.parse(_rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP request failed with status: ${response.statusCode}');
    }

    final responseJson = jsonDecode(response.body);

    if (responseJson['error'] != null) {
      throw Exception('RPC error: ${responseJson['error']}');
    }

    final result = responseJson['result'];
    if (result == null) {
      throw Exception('Transaction not found: $signature');
    }

    return {
      'meta': result['meta'],
      'transaction': result['transaction'],
    };
  }

  @override
  Future<double> getTokenBalance(String tokenAccount) async {
    throw UnimplementedError('getTokenBalance not needed for price fetching');
  }

  @override
  Future<String?> findTokenAccount(String owner, String mint) async {
    throw UnimplementedError('findTokenAccount not needed for price fetching');
  }

  @override
  Future<String> getAssociatedTokenAddress(String owner, String mint) async {
    throw UnimplementedError('getAssociatedTokenAddress not needed for price fetching');
  }

  @override
  Future<String> sendAndConfirmTransaction({
    required dynamic message,
    required List<dynamic> signers,
    dynamic commitment,
  }) async {
    throw UnimplementedError('sendAndConfirmTransaction not needed for price fetching');
  }
}
