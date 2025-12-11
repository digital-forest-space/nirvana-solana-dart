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
    
    // Build accounts in exact order from browser-intercepted transaction
    // Position 3 = 5DkzT65... (ANA), Position 4 = 3eamaYJ... (NIRV)
    // Position 9 is payment source, position 10 is user ANA destination
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),        // 0: payer (signer)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),  // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.priceCurve), isSigner: false, isWriteable: false),    // 2: price curve PDA
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),        // 3: ANA mint (5DkzT65...)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),       // 4: NIRV mint (3eamaYJ...)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.usdcMint), isSigner: false, isWriteable: false),      // 5: USDC mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantUsdcVault), isSigner: false, isWriteable: true), // 6: tenant USDC vault
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true),  // 7: tenant ANA vault
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),   // 8: escrow revenue NIRV
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(useNirv ? userNirvAccount : userPaymentAccount), isSigner: false, isWriteable: true), // 9: payment source
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),          // 10: user ANA destination
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),           // 11: token program
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),           // 12: token program (duplicate)
    ];
    
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build sell2 instruction (sells ANA for USDC or NIRV)
  /// Based on Chrome injection analysis of actual sell transactions
  /// Set useNirv=true to receive NIRV instead of USDC
  Instruction buildSellInstruction({
    required String userPubkey,
    required String userAnaAccount,
    required String userDestinationAccount, // USDC account or NIRV account depending on useNirv
    required int anaLamports,
    int minOutputLamports = 0,
    bool useNirv = false,
  }) {
    // sell2 discriminator (confirmed from Chrome injection analysis)
    final discriminator = [47, 191, 120, 1, 28, 35, 253, 79];

    // Build instruction data
    final anaBytes = Uint8List(8);
    anaBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);
    final minOutputBytes = Uint8List(8);
    minOutputBytes.buffer.asByteData().setUint64(0, minOutputLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...anaBytes,
      ...minOutputBytes,
    ];

    // Build accounts in exact order from Chrome injection analysis
    // Account 4 is the destination - either user's USDC or NIRV account
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),           // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true), // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.priceCurve), isSigner: false, isWriteable: true),    // 2: price curve (must be writable!)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),       // 3: ANA mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userDestinationAccount), isSigner: false, isWriteable: true), // 4: user destination account (USDC or NIRV)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true), // 5: escrow ANA (same as escrowRevNirv)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantUsdcVault), isSigner: false, isWriteable: true), // 6: tenant USDC vault (source)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true),  // 7: tenant ANA/NIRV vault
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),        // 8: user ANA account (source)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: false),     // 9: NIRV mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.usdcMint), isSigner: false, isWriteable: false),     // 10: USDC mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),         // 11: token program
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),         // 12: token program (duplicate)
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build deposit_ana (stake) instruction
  /// Based on Chrome injection analysis from companion stake_ana.dart
  Instruction buildDepositAnaInstruction({
    required String userPubkey,
    required String userAnaAccount,
    required String personalAccount,
    required int anaLamports,
  }) {
    // deposit_ana discriminator (from Chrome injection analysis)
    final discriminator = [68, 100, 197, 87, 22, 85, 190, 78];

    // Vault ANA account discovered from Chrome injection
    const String vaultAnaAccount = 'GUEs3s1j1gvQ2F7xMXh6vHnB5t1bQG4zev1qEfWJKEea';

    // Build instruction data
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...amountBytes,
    ];

    // Build accounts in exact order from Chrome injection analysis (6 accounts)
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),           // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true), // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),       // 2: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),        // 3: user ANA account (source)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(vaultAnaAccount), isSigner: false, isWriteable: true),       // 4: vault ANA account (destination)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),         // 5: token program
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
  
  /// Build withdraw_ana (unstake) instruction
  /// Based on browser injection log app.nirvana.finance-1749498461606_unstake_ana.log
  Instruction buildWithdrawAnaInstruction({
    required String userPubkey,
    required String userAnaAccount,
    required String personalAccount,
    required int anaLamports,
  }) {
    // withdraw_ana discriminator (from browser injection log)
    final discriminator = [93, 87, 203, 252, 78, 187, 97, 82];

    // Vault ANA account (source for withdrawn tokens)
    const String vaultAnaAccount = 'GUEs3s1j1gvQ2F7xMXh6vHnB5t1bQG4zev1qEfWJKEea';

    // Build instruction data
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...amountBytes,
    ];

    // Build accounts in exact order from browser injection log (7 accounts)
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),              // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),  // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),        // 2: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),         // 3: user ANA account (destination)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),  // 4: escrow rev NIRV (42rJYSmY...)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(vaultAnaAccount), isSigner: false, isWriteable: true),        // 5: vault ANA account (source)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),          // 6: token program
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

  /// Build repay instruction (repays NIRV debt by burning ANA)
  /// Based on Chrome injection analysis of actual repay transactions
  Instruction buildRepayInstruction({
    required String userPubkey,
    required String personalAccount,
    required String userAnaAccount,
    required int anaLamports,
  }) {
    // repay discriminator (confirmed from Chrome injection analysis)
    final discriminator = [28, 158, 130, 191, 125, 127, 195, 94];

    // Build instruction data
    final anaBytes = Uint8List(8);
    anaBytes.buffer.asByteData().setUint64(0, anaLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...anaBytes,
    ];

    // Build accounts in exact order from Chrome injection analysis (6 accounts)
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),           // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true), // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),       // 2: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),        // 3: user ANA account (burns ANA)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),       // 4: ANA mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),         // 5: token program
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
}