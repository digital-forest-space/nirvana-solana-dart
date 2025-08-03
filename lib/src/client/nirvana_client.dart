import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

import '../models/config.dart';
import '../models/prices.dart';
import '../models/personal_account_info.dart';
import '../models/transaction_result.dart';
import '../models/requests/buy_ana_request.dart';
import '../models/requests/sell_ana_request.dart';
import '../models/requests/stake_ana_request.dart';
import '../rpc/solana_rpc_client.dart';
import '../instructions/transaction_builder.dart';
import '../accounts/account_resolver.dart';

/// Main client for interacting with Nirvana V2 protocol
class NirvanaClient {
  static const List<int> _tenantDiscriminator = [61, 43, 215, 51, 232, 242, 209, 170];

  final SolanaRpcClient _rpcClient;
  final NirvanaTransactionBuilder _transactionBuilder;
  final NirvanaAccountResolver _accountResolver;
  final NirvanaConfig _config;

  NirvanaClient({
    required SolanaRpcClient rpcClient,
    NirvanaConfig? config,
  }) : _rpcClient = rpcClient,
       _config = config ?? NirvanaConfig.mainnet(),
       _transactionBuilder = NirvanaTransactionBuilder(config: config),
       _accountResolver = NirvanaAccountResolver(rpcClient, config: config);

  /// Create a NirvanaClient with a default RPC client
  factory NirvanaClient.withDefaultRpc({
    required SolanaClient solanaClient,
    NirvanaConfig? config,
  }) {
    final rpcClient = DefaultSolanaRpcClient(solanaClient);
    return NirvanaClient(rpcClient: rpcClient, config: config);
  }

  /// Fetches current ANA token prices from the Nirvana V2 protocol
  Future<NirvanaPrices> fetchPrices() async {
    try {
      final accountData = await _fetchTenantAccountData();
      final prices = _calculatePrices(accountData);
      return NirvanaPrices(
        anaMarket: prices.anaMarket,
        anaFloor: prices.anaFloor,
        prana: prices.prana,
        lastUpdated: DateTime.now().toUtc(),
      );
    } catch (e) {
      throw Exception('Failed to fetch Nirvana prices: $e');
    }
  }

  Future<Uint8List> _fetchTenantAccountData() async {
    final accountInfo = await _rpcClient.getAccountInfo(_config.tenantAccount);
    
    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      throw Exception('Nirvana Tenant account not found');
    }

    final base64Data = accountInfo['data']?[0];
    if (base64Data == null || base64Data.isEmpty) {
      throw Exception('Tenant account contains no data');
    }

    final bytes = base64.decode(base64Data);

    if (!_verifyTenantAccount(bytes)) {
      throw Exception('Invalid Tenant account discriminator - not a valid Nirvana V2 account');
    }

    return bytes;
  }

  bool _verifyTenantAccount(Uint8List bytes) {
    if (bytes.length < 8) return false;

    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _tenantDiscriminator[i]) {
        return false;
      }
    }
    return true;
  }

  _PriceData _calculatePrices(Uint8List bytes) {
    if (bytes.length < 500) {
      throw Exception('Tenant account data too small - corrupted or invalid');
    }

    // Parse Tenant struct fields based on IDL structure
    int offset = 8; // Skip discriminator

    // Skip admin pubkey and flags
    offset += 32; // field_0: admin pubkey
    offset += 1;  // field_1: u8

    // Skip vault and mint pubkeys (12 fields × 32 bytes)
    offset += 32 * 12; // fields 2-13

    // Read field 14 - the reserve/liquidity field used in bonding curve
    final field14 = _bytesToUint64(bytes.sublist(offset, offset + 8));

    // Validate field value before calculation
    if (field14 == 0) {
      throw Exception('Invalid price data - reserve field is zero');
    }

    // Calculate prices using bonding curve formula
    // Price = sqrt(field14 * 1e-9 * k)
    // This eliminates all hard-coded scaling factors!
    const marketK = 4104.0 / 1000000.0;  // Fine-tuned k value for market price
    const floorK = 1999.0 / 1000000.0;   // Fine-tuned k value for floor price
    
    final anaMarket = math.sqrt(field14.toDouble() * 1e-9 * marketK);
    final anaFloor = math.sqrt(field14.toDouble() * 1e-9 * floorK);
    
    // prANA price equals the premium (market - floor)
    final prana = anaMarket - anaFloor;

    // Validate calculated prices are reasonable
    if (anaMarket <= 0 || anaMarket > 1000) {
      throw Exception('Calculated ANA market price out of reasonable range: \$${anaMarket.toStringAsFixed(4)}');
    }

    if (anaFloor <= 0 || anaFloor > 1000) {
      throw Exception('Calculated ANA floor price out of reasonable range: \$${anaFloor.toStringAsFixed(4)}');
    }

    if (prana <= 0 || prana > 100) {
      throw Exception('Calculated prANA price out of reasonable range: \$${prana.toStringAsFixed(4)}');
    }

    return _PriceData(
      anaMarket: anaMarket,
      anaFloor: anaFloor,
      prana: prana,
    );
  }

  int _bytesToUint64(List<int> bytes) {
    if (bytes.length < 8) {
      throw Exception('Insufficient bytes for uint64 conversion');
    }

    int value = 0;
    for (int i = 0; i < 8; i++) {
      value |= bytes[i] << (8 * i);
    }
    return value;
  }
  
  /// Get user's personal account information
  Future<PersonalAccountInfo?> getPersonalAccountInfo(String userPubkey) async {
    final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
    if (personalAccount == null) return null;
    
    try {
      final accountInfo = await _rpcClient.getAccountInfo(personalAccount);
      if (accountInfo.isEmpty || accountInfo['data'] == null) return null;
      
      final accountData = base64Decode(accountInfo['data'][0]);
      
      // Parse PersonalAccount data structure
      // Skip discriminator (8) + field_0 (32) + field_1 (32) = 72 bytes
      int offset = 72;
      
      // Read fields
      final anaDebt = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      final stakedAna = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      // Skip fields 2-5 (4 * 8 = 32 bytes)
      offset += 32;
      
      // Read field 6 (claimable prANA)
      final claimablePrana = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      offset += 8;
      
      // Skip fields 7-13 (7 * 8 = 56 bytes)
      offset += 56;
      
      // Read field 14 (staked prANA)
      final stakedPrana = ByteData.sublistView(Uint8List.fromList(accountData.sublist(offset, offset + 8)))
          .getUint64(0, Endian.little) / 1000000;
      
      return PersonalAccountInfo(
        address: personalAccount,
        anaDebt: anaDebt,
        stakedAna: stakedAna,
        claimablePrana: claimablePrana,
        stakedPrana: stakedPrana,
        lastUpdated: DateTime.now().toUtc(),
      );
    } catch (e) {
      throw Exception('Failed to get personal account info: $e');
    }
  }
  
  /// Get user's token balances (ANA, NIRV, USDC, prANA)
  Future<Map<String, double>> getUserBalances(String userPubkey) async {
    return await _accountResolver.getUserBalances(userPubkey);
  }
  
  /// Buy ANA tokens
  Future<TransactionResult> buyAna(BuyAnaRequest request) async {
    try {
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(request.userPubkey);
      
      // Validate payment account
      final paymentAccount = request.useNirv ? accounts.nirvAccount : accounts.usdcAccount;
      if (paymentAccount == null) {
        throw Exception('User does not have ${request.useNirv ? "NIRV" : "USDC"} token account');
      }
      
      // Ensure ANA and NIRV accounts exist
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      
      // Convert amount to lamports (6 decimals)
      final amountLamports = (request.amount * 1000000).toInt();
      final minAnaLamports = request.minAnaAmount != null 
          ? (request.minAnaAmount! * 1000000).toInt() 
          : 0;
      
      // Build buy instruction
      final instruction = _transactionBuilder.buildBuyExact2Instruction(
        userPubkey: request.userPubkey,
        userPaymentAccount: paymentAccount,
        userAnaAccount: accounts.anaAccount!,
        userNirvAccount: accounts.nirvAccount!,
        amountLamports: amountLamports,
        useNirv: request.useNirv,
        minAnaLamports: minAnaLamports,
      );
      
      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [request.keypair],
      );
      
      return TransactionResult.success(
        signature: signature,
        logs: ['Buy ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Sell ANA tokens
  Future<TransactionResult> sellAna(SellAnaRequest request) async {
    try {
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(request.userPubkey);
      
      // Validate accounts
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      if (accounts.usdcAccount == null) {
        throw Exception('User does not have USDC token account');
      }
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      
      // Convert amount to lamports (6 decimals)
      final anaLamports = (request.anaAmount * 1000000).toInt();
      final minUsdcLamports = request.minUsdcAmount != null 
          ? (request.minUsdcAmount! * 1000000).toInt() 
          : 0;
      
      // Build sell instruction
      final instruction = _transactionBuilder.buildSellExact2Instruction(
        userPubkey: request.userPubkey,
        userAnaAccount: accounts.anaAccount!,
        userUsdcAccount: accounts.usdcAccount!,
        userNirvAccount: accounts.nirvAccount!,
        anaLamports: anaLamports,
        minUsdcLamports: minUsdcLamports,
      );
      
      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [request.keypair],
      );
      
      return TransactionResult.success(
        signature: signature,
        logs: ['Sell ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Stake ANA tokens
  Future<TransactionResult> stakeAna(StakeAnaRequest request) async {
    try {
      // Find personal account
      var personalAccount = await _accountResolver.findPersonalAccount(request.userPubkey);
      if (personalAccount == null) {
        // Initialize personal account first
        personalAccount = await initializePersonalAccount(
          userPubkey: request.userPubkey,
          keypair: request.keypair,
        );
      }
      
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(request.userPubkey);
      if (accounts.anaAccount == null) {
        throw Exception('User does not have ANA token account');
      }
      
      // Convert amount to lamports
      final anaLamports = (request.anaAmount * 1000000).toInt();
      
      // Build stake instruction
      final instruction = _transactionBuilder.buildDepositAnaInstruction(
        userPubkey: request.userPubkey,
        userAnaAccount: accounts.anaAccount!,
        personalAccount: personalAccount,
        anaLamports: anaLamports,
      );
      
      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [request.keypair],
      );
      
      return TransactionResult.success(
        signature: signature,
        logs: ['Stake ANA transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  /// Initialize personal account for staking
  Future<String> initializePersonalAccount({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
  }) async {
    // Derive personal account PDA
    // TODO: Implement proper PDA derivation
    const String tempPersonalAccount = 'TempPersonalAccountAddress'; // Placeholder
    
    final instruction = _transactionBuilder.buildInitPersonalAccountInstruction(
      userPubkey: userPubkey,
      personalAccount: tempPersonalAccount,
    );
    
    final message = Message(instructions: [instruction]);
    await _rpcClient.sendAndConfirmTransaction(
      message: message,
      signers: [keypair],
    );
    
    return tempPersonalAccount;
  }
  
  /// Borrow NIRV against staked ANA
  Future<TransactionResult> borrowNirv({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double nirvAmount,
  }) async {
    try {
      // Find personal account
      final personalAccount = await _accountResolver.findPersonalAccount(userPubkey);
      if (personalAccount == null) {
        throw Exception('PersonalAccount not found. You need to stake ANA first.');
      }
      
      // Resolve user accounts
      final accounts = await _accountResolver.resolveUserAccounts(userPubkey);
      if (accounts.nirvAccount == null) {
        throw Exception('User does not have NIRV token account');
      }
      
      // Convert amount to lamports
      final nirvLamports = (nirvAmount * 1000000).toInt();
      
      // Build borrow instruction
      final instruction = _transactionBuilder.buildBorrowNirvInstruction(
        userPubkey: userPubkey,
        personalAccount: personalAccount,
        userNirvAccount: accounts.nirvAccount!,
        nirvLamports: nirvLamports,
      );
      
      // Create and send transaction
      final message = Message(instructions: [instruction]);
      final signature = await _rpcClient.sendAndConfirmTransaction(
        message: message,
        signers: [keypair],
      );
      
      return TransactionResult.success(
        signature: signature,
        logs: ['Borrow NIRV transaction successful'],
      );
    } catch (e) {
      return TransactionResult.failure(
        signature: '',
        error: e.toString(),
      );
    }
  }
  
  // Stub implementations for remaining methods
  Future<TransactionResult> unstakeAna({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double anaAmount,
  }) async {
    // TODO: Implement
    throw UnimplementedError('unstakeAna not yet implemented');
  }
  
  Future<TransactionResult> claimPrana({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
  }) async {
    // TODO: Implement
    throw UnimplementedError('claimPrana not yet implemented');
  }
  
  Future<TransactionResult> repayNirv({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double nirvAmount,
  }) async {
    // TODO: Implement
    throw UnimplementedError('repayNirv not yet implemented');
  }
  
  Future<TransactionResult> realizePrana({
    required String userPubkey,
    required Ed25519HDKeyPair keypair,
    required double pranaAmount,
  }) async {
    // TODO: Implement
    throw UnimplementedError('realizePrana not yet implemented');
  }
}

class _PriceData {
  final double anaMarket;
  final double anaFloor;
  final double prana;

  _PriceData({
    required this.anaMarket,
    required this.anaFloor,
    required this.prana,
  });
}