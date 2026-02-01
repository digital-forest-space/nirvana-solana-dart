import 'package:solana/solana.dart';

import '../rpc/solana_rpc_client.dart';
import '../models/config.dart';
import '../nirvana/pda.dart';

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
  
  /// Derive user's personal account PDA address (for staking/borrowing).
  /// Always returns a valid address — the PDA is deterministic regardless of
  /// whether the account exists on-chain.
  Future<String> derivePersonalAccount(String userPubkey) async {
    final pda = NirvanaPda.mainnet();
    final tenantKey = Ed25519HDPublicKey.fromBase58(_config.tenantAccount);
    final ownerKey = Ed25519HDPublicKey.fromBase58(userPubkey);
    final personalKey = await pda.personalAccount(
      tenant: tenantKey,
      owner: ownerKey,
    );
    return personalKey.toBase58();
  }

  /// Find user's personal account if it exists on-chain.
  /// Uses deterministic PDA derivation + getAccountInfo existence check.
  Future<String?> findPersonalAccount(String userPubkey) async {
    final address = await derivePersonalAccount(userPubkey);
    final accountInfo = await _rpcClient.getAccountInfo(address);
    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      return null;
    }
    return address;
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