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
}

/// Default implementation using solana package
class DefaultSolanaRpcClient implements SolanaRpcClient {
  final SolanaClient _client;
  
  DefaultSolanaRpcClient(this._client);
  
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
    
    return {
      'lamports': account.value!.lamports,
      'owner': account.value!.owner,
      'executable': account.value!.executable,
      'rentEpoch': account.value!.rentEpoch,
      'data': account.value!.data,
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
    final ownerPubkey = Ed25519HDPublicKey.fromBase58(owner);
    final mintPubkey = Ed25519HDPublicKey.fromBase58(mint);
    
    final accounts = await _client.rpcClient.getTokenAccountsByOwner(
      ownerPubkey.toBase58(),
      TokenAccountsFilter.byMint(mintPubkey.toBase58()),
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
    final tx = await _client.rpcClient.getTransaction(
      signature,
      encoding: Encoding.jsonParsed,
    );

    if (tx == null) {
      throw Exception('Transaction not found: $signature');
    }

    return {
      'meta': tx.meta?.toJson(),
      'transaction': tx.transaction.toJson(),
    };
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
}