import '../rpc/solana_rpc_client.dart';
import '../models/config.dart';

/// Resolves and manages Nirvana-related accounts
class NirvanaAccountResolver {
  final SolanaRpcClient _rpcClient;
  final NirvanaConfig _config;
  
  NirvanaAccountResolver(this._rpcClient, {NirvanaConfig? config})
    : _config = config ?? NirvanaConfig.mainnet();
  
  /// Finds all user token accounts for Nirvana tokens
  Future<NirvanaUserAccounts> resolveUserAccounts(String userPubkey) async {
    // Find or derive token accounts
    final anaAccount = await _findOrDeriveTokenAccount(userPubkey, _config.anaMint);
    final nirvAccount = await _findOrDeriveTokenAccount(userPubkey, _config.nirvMint);
    final usdcAccount = await _findOrDeriveTokenAccount(userPubkey, _config.usdcMint);
    final pranaAccount = await _findOrDeriveTokenAccount(userPubkey, _config.pranaMint);
    
    return NirvanaUserAccounts(
      userPubkey: userPubkey,
      anaAccount: anaAccount,
      nirvAccount: nirvAccount,
      usdcAccount: usdcAccount,
      pranaAccount: pranaAccount,
    );
  }
  
  /// Find user's personal account (for staking/borrowing)
  /// Queries program accounts with dataSize=272 and memcmp filter for user pubkey at offset 8
  Future<String?> findPersonalAccount(String userPubkey) async {
    try {
      final accounts = await _rpcClient.getProgramAccounts(
        _config.programId,
        dataSize: 272,  // PersonalAccount size
        memcmpOffset: 8,  // Skip discriminator, match user pubkey at field 0
        memcmpBytes: userPubkey,
      );

      if (accounts.isEmpty) {
        return null;
      }

      return accounts.first['pubkey'] as String;
    } catch (e) {
      // Fallback to null if RPC call fails
      return null;
    }
  }
  
  /// Get user's token balances
  Future<Map<String, double>> getUserBalances(String userPubkey) async {
    final accounts = await resolveUserAccounts(userPubkey);
    final balances = <String, double>{};
    
    // Get balance for each token
    if (accounts.anaAccount != null) {
      balances['ANA'] = await _rpcClient.getTokenBalance(accounts.anaAccount!);
    } else {
      balances['ANA'] = 0.0;
    }
    
    if (accounts.nirvAccount != null) {
      balances['NIRV'] = await _rpcClient.getTokenBalance(accounts.nirvAccount!);
    } else {
      balances['NIRV'] = 0.0;
    }
    
    if (accounts.usdcAccount != null) {
      balances['USDC'] = await _rpcClient.getTokenBalance(accounts.usdcAccount!);
    } else {
      balances['USDC'] = 0.0;
    }
    
    if (accounts.pranaAccount != null) {
      balances['prANA'] = await _rpcClient.getTokenBalance(accounts.pranaAccount!);
    } else {
      balances['prANA'] = 0.0;
    }
    
    return balances;
  }
  
  Future<String?> _findOrDeriveTokenAccount(String owner, String mint) async {
    // First try to find existing account
    final existing = await _rpcClient.findTokenAccount(owner, mint);
    if (existing != null) {
      return existing;
    }
    
    // If not found, derive the associated token account address
    return await _rpcClient.getAssociatedTokenAddress(owner, mint);
  }
}

/// Container for user's Nirvana-related accounts
class NirvanaUserAccounts {
  final String userPubkey;
  final String? anaAccount;
  final String? nirvAccount;
  final String? usdcAccount;
  final String? pranaAccount;
  
  const NirvanaUserAccounts({
    required this.userPubkey,
    this.anaAccount,
    this.nirvAccount,
    this.usdcAccount,
    this.pranaAccount,
  });
}