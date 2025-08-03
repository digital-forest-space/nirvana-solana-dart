import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import '../models/config.dart';

/// Builds Solana instructions for Nirvana V2 protocol operations
class NirvanaTransactionBuilder {
  final NirvanaConfig _config;
  
  NirvanaTransactionBuilder({NirvanaConfig? config}) 
    : _config = config ?? NirvanaConfig.mainnet();
  
  static const String tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  
  /// Build buy_exact2 instruction
  Instruction buildBuyExact2Instruction({
    required String userPubkey,
    required String userPaymentAccount,
    required String userAnaAccount,
    required String userNirvAccount,
    required int amountLamports,
    required bool useNirv,
    int minAnaLamports = 0,
  }) {
    // buy_exact2 discriminator
    final discriminator = [109, 5, 199, 243, 164, 233, 19, 152];
    
    // Build instruction data
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, amountLamports, Endian.little);
    final minAnaBytes = Uint8List(8);
    minAnaBytes.buffer.asByteData().setUint64(0, minAnaLamports, Endian.little);
    
    final instructionData = [
      ...discriminator,
      ...amountBytes,
      ...minAnaBytes,
    ];
    
    // Build accounts based on payment type
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.priceCurve), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.usdcMint), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantUsdcVault), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),
      // Position 9 changes based on payment type
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(useNirv ? userAnaAccount : userPaymentAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userNirvAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build sell_exact2 instruction
  Instruction buildSellExact2Instruction({
    required String userPubkey,
    required String userAnaAccount,
    required String userUsdcAccount,
    required String userNirvAccount,
    required int anaLamports,
    int minUsdcLamports = 0,
  }) {
    // sell_exact2 discriminator
    final discriminator = [19, 250, 156, 171, 34, 215, 0, 78];
    
    // Build instruction data
    final anaBytes = Uint8List(8);
    anaBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);
    final minUsdcBytes = Uint8List(8);
    minUsdcBytes.buffer.asByteData().setUint64(0, minUsdcLamports, Endian.little);
    
    final instructionData = [
      ...discriminator,
      ...anaBytes,
      ...minUsdcBytes,
    ];
    
    // Build accounts
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.priceCurve), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.usdcMint), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantUsdcVault), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userUsdcAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userNirvAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build deposit_ana (stake) instruction
  Instruction buildDepositAnaInstruction({
    required String userPubkey,
    required String userAnaAccount,
    required String personalAccount,
    required int anaLamports,
  }) {
    // deposit_ana discriminator
    final discriminator = [54, 176, 103, 174, 10, 63, 188, 186];
    
    // Build instruction data
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);
    
    final instructionData = [
      ...discriminator,
      ...amountBytes,
    ];
    
    // Build accounts
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build init_personal_account instruction
  Instruction buildInitPersonalAccountInstruction({
    required String userPubkey,
    required String personalAccount,
  }) {
    // init_personal_account discriminator
    final discriminator = [161, 176, 40, 213, 71, 95, 78, 42];
    
    // Build accounts
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: false),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58('11111111111111111111111111111111'), isSigner: false, isWriteable: false), // System program
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(discriminator)),
    );
  }
  
  /// Build borrow_nirv instruction
  Instruction buildBorrowNirvInstruction({
    required String userPubkey,
    required String personalAccount,
    required String userNirvAccount,
    required int nirvLamports,
  }) {
    // borrow_nirv discriminator
    final discriminator = [155, 1, 43, 62, 79, 104, 66, 42];
    
    // Build instruction data
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, nirvLamports, Endian.little);
    
    final instructionData = [
      ...discriminator,
      ...amountBytes,
    ];
    
    // Escrow NIRV account - from our testing
    const String escrowNirvAccount = 'v2EeX2VjgsMbwokj6UDmAm691oePzrcvKpK5DT7LwbQ';
    
    // Build accounts
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userNirvAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(escrowNirvAccount), isSigner: false, isWriteable: true),
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
}