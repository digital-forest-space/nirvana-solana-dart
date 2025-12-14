import 'dart:convert';
import 'dart:io';
import 'package:solana/solana.dart';
import 'package:solana/dto.dart';
import 'package:solana/encoder.dart';

/// Minimal RPC client interface for Nirvana operations
abstract class SolanaRpcClient {
  /// Get account information
  Future<Map<String, dynamic>> getAccountInfo(String address);

  /// Get token account balance
  Future<double> getTokenBalance(String tokenAccount);

  /// Find token account for owner and mint
  Future<String?> findTokenAccount(String owner, String mint);

  /// Get associated token address
  Future<String> getAssociatedTokenAddress(String owner, String mint);

  /// Get recent transaction signatures for an address
  Future<List<String>> getSignaturesForAddress(String address, {int limit = 100});

  /// Get transaction details (returns jsonParsed format)
  Future<Map<String, dynamic>> getTransaction(String signature);

  /// Send and confirm transaction
  Future<String> sendAndConfirmTransaction({
    required Message message,
    required List<Ed25519HDKeyPair> signers,
    Commitment commitment = Commitment.confirmed,
  });

  /// Find program accounts with filters (for PersonalAccount lookup)
  /// If memcmpOffset and memcmpBytes are omitted, only filters by dataSize.
  Future<List<Map<String, dynamic>>> getProgramAccounts(
    String programId, {
    required int dataSize,
    int? memcmpOffset,
    String? memcmpBytes,
  });

  /// Simulate a transaction (for getting return data without signing)
  Future<Map<String, dynamic>> simulateTransaction(String txBase64);

  /// Simulate a transaction and return post-state of specified accounts
  Future<Map<String, dynamic>> simulateTransactionWithAccounts(
    String txBase64,
    List<String> accountAddresses,
  );

  /// Get recent blockhash
  Future<String> getLatestBlockhash();
}

/// Default implementation using solana package
class DefaultSolanaRpcClient implements SolanaRpcClient {
  final SolanaClient _client;
  final Uri _rpcUrl;
  final Duration _timeout;

  /// Creates a DefaultSolanaRpcClient with an explicit RPC URL.
  /// The URL is needed for raw HTTP requests (e.g., getTransaction)
  /// since the SolanaClient doesn't expose its URL.
  ///
  /// [timeout] sets the timeout for HTTP requests (default: 30 seconds)
  DefaultSolanaRpcClient(SolanaClient client, {Uri? rpcUrl, Duration? timeout})
      : _client = client,
        _rpcUrl = rpcUrl ?? Uri.parse('https://api.mainnet-beta.solana.com'),
        _timeout = timeout ?? const Duration(seconds: 30);
  
  @override
  Future<Map<String, dynamic>> getAccountInfo(String address) async {
    final pubKey = Ed25519HDPublicKey.fromBase58(address);
    final account = await _client.rpcClient.getAccountInfo(
      pubKey.toBase58(),
      encoding: Encoding.base64,
    );

    if (account == null || account.value == null) {
      return {};
    }

    // Handle BinaryAccountData - extract base64 string
    final data = account.value!.data;
    List<dynamic>? dataArray;
    if (data is BinaryAccountData) {
      // BinaryAccountData has a data property containing base64 string
      dataArray = [base64.encode(data.data), 'base64'];
    }

    return {
      'lamports': account.value!.lamports,
      'owner': account.value!.owner,
      'executable': account.value!.executable,
      'rentEpoch': account.value!.rentEpoch,
      'data': dataArray,
    };
  }

  @override
  Future<double> getTokenBalance(String tokenAccount) async {
    final pubKey = Ed25519HDPublicKey.fromBase58(tokenAccount);
    final balance = await _client.rpcClient.getTokenAccountBalance(pubKey.toBase58());
    return double.parse(balance.value.uiAmountString ?? '0');
  }
  
  @override
  Future<String?> findTokenAccount(String owner, String mint) async {
    final accounts = await _client.rpcClient.getTokenAccountsByOwner(
      owner,
      TokenAccountsFilter.byMint(mint),
      encoding: Encoding.jsonParsed,
    );

    if (accounts.value.isEmpty) {
      return null;
    }

    return accounts.value.first.pubkey;
  }
  
  @override
  Future<String> getAssociatedTokenAddress(String owner, String mint) async {
    final ownerPubkey = Ed25519HDPublicKey.fromBase58(owner);
    final mintPubkey = Ed25519HDPublicKey.fromBase58(mint);
    
    final associatedTokenAddress = await findAssociatedTokenAddress(
      owner: ownerPubkey,
      mint: mintPubkey,
    );
    
    return associatedTokenAddress.toBase58();
  }
  
  @override
  Future<List<String>> getSignaturesForAddress(String address, {int limit = 100}) async {
    final signatures = await _client.rpcClient.getSignaturesForAddress(
      address,
      limit: limit,
    );

    return signatures
        .where((sig) => sig.err == null)
        .map((sig) => sig.signature)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getTransaction(String signature) async {
    // Use raw HTTP request because the Solana package's toJson()
    // loses the 'owner' field from preTokenBalances/postTokenBalances
    final httpClient = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await httpClient.postUrl(_rpcUrl);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getTransaction',
        'params': [
          signature,
          {'encoding': 'jsonParsed', 'maxSupportedTransactionVersion': 0}
        ],
      }));
      final response = await request.close().timeout(_timeout);
      final responseBody = await response.transform(utf8.decoder).join().timeout(_timeout);
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (data.containsKey('error')) {
        throw Exception('RPC error: ${data['error']}');
      }

      final result = data['result'];
      if (result == null) {
        throw Exception('Transaction not found: $signature');
      }

      return result as Map<String, dynamic>;
    } finally {
      httpClient.close();
    }
  }

  @override
  Future<String> sendAndConfirmTransaction({
    required Message message,
    required List<Ed25519HDKeyPair> signers,
    Commitment commitment = Commitment.confirmed,
  }) async {
    final signature = await _client.sendAndConfirmTransaction(
      message: message,
      signers: signers,
      commitment: commitment,
    );

    return signature;
  }

  @override
  Future<List<Map<String, dynamic>>> getProgramAccounts(
    String programId, {
    required int dataSize,
    int? memcmpOffset,
    String? memcmpBytes,
  }) async {
    final filters = <ProgramDataFilter>[
      ProgramDataFilter.dataSize(dataSize),
    ];

    // Add memcmp filter if both offset and bytes are provided
    if (memcmpOffset != null && memcmpBytes != null) {
      final pubkeyBytes = Ed25519HDPublicKey.fromBase58(memcmpBytes).bytes;
      filters.add(ProgramDataFilter.memcmp(offset: memcmpOffset, bytes: pubkeyBytes));
    }

    final accounts = await _client.rpcClient.getProgramAccounts(
      programId,
      encoding: Encoding.base64,
      filters: filters,
    );

    return accounts.map((account) {
      return {
        'pubkey': account.pubkey,
        'account': {
          'data': account.account.data is BinaryAccountData
              ? [base64.encode((account.account.data as BinaryAccountData).data), 'base64']
              : account.account.data,
          'lamports': account.account.lamports,
          'owner': account.account.owner,
        },
      };
    }).toList();
  }

  @override
  Future<Map<String, dynamic>> simulateTransaction(String txBase64) async {
    // Use raw HTTP since the solana package doesn't expose simulation return data
    final client = HttpClient();
    try {
      final request = await client.postUrl(_rpcUrl).timeout(_timeout);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'simulateTransaction',
        'params': [
          txBase64,
          {
            'encoding': 'base64',
            'commitment': 'confirmed',
            'sigVerify': false,
            'replaceRecentBlockhash': true,
          }
        ]
      }));

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body);

      if (json['error'] != null) {
        throw Exception('RPC error: ${json['error']}');
      }

      return json['result']?['value'] as Map<String, dynamic>? ?? {};
    } finally {
      client.close();
    }
  }

  @override
  Future<String> getLatestBlockhash() async {
    final result = await _client.rpcClient.getLatestBlockhash();
    return result.value.blockhash;
  }

  @override
  Future<Map<String, dynamic>> simulateTransactionWithAccounts(
    String txBase64,
    List<String> accountAddresses,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(_rpcUrl);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'simulateTransaction',
        'params': [
          txBase64,
          {
            'encoding': 'base64',
            'commitment': 'confirmed',
            'sigVerify': false,
            'replaceRecentBlockhash': true,
            'accounts': {
              'encoding': 'base64',
              'addresses': accountAddresses,
            },
          },
        ],
      }));

      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body);

      if (json['error'] != null) {
        throw Exception('RPC error: ${json['error']}');
      }

      return json['result']?['value'] as Map<String, dynamic>? ?? {};
    } finally {
      client.close();
    }
  }
}