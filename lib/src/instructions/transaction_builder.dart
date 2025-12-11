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

  /// Build realize prANA instruction (converts prANA to ANA by paying USDC or NIRV)
  /// Based on Chrome injection analysis of actual realize transactions
  Instruction buildRealizeInstruction({
    required String userPubkey,
    required String userPranaAccount,
    required String userNirvAccount,
    required String userUsdcAccount, // USDC account (used when NOT useNirv)
    required String userAnaAccount,
    required int pranaLamports,
    required bool useNirv,
  }) {
    // realize discriminator (confirmed from Chrome injection analysis)
    final discriminator = [64, 34, 113, 17, 141, 79, 61, 38];

    // Build instruction data
    final pranaBytes = Uint8List(8);
    pranaBytes.buffer.asByteData().setUint64(0, pranaLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...pranaBytes,
    ];

    // Build accounts in exact order from Chrome injection analysis (15 accounts)
    // Comparing realize_prANA.log (USDC) vs realize_ana_with_nirv.log (NIRV):
    // 0: user, 1: tenant, 2: priceCurve, 3: ANA mint, 4: USDC mint, 5: NIRV mint
    // 6: prANA mint, 7: CONDITIONAL (USDC: userUsdcAccount, NIRV: userNirvAccount)
    // 8: userPranaAccount (burn source), 9: userAnaAccount (destination)
    // 10: escrowRevNirv, 11: tenantUsdcVault, 12: tenantAnaVault, 13-14: tokenProgram
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),              // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),  // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.priceCurve), isSigner: false, isWriteable: true),     // 2: price curve
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.anaMint), isSigner: false, isWriteable: true),        // 3: ANA mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.usdcMint), isSigner: false, isWriteable: false),      // 4: USDC mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),       // 5: NIRV mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.pranaMint), isSigner: false, isWriteable: true),      // 6: prANA mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(useNirv ? userNirvAccount : userUsdcAccount), isSigner: false, isWriteable: true), // 7: CONDITIONAL payment source
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPranaAccount), isSigner: false, isWriteable: true),       // 8: user prANA account (burn source)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),         // 9: user ANA account (destination)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),  // 10: escrow revenue NIRV
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantUsdcVault), isSigner: false, isWriteable: true), // 11: tenant USDC vault
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAnaVault), isSigner: false, isWriteable: true), // 12: tenant ANA vault
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),          // 13: token program
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),          // 14: token program (duplicate)
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build repay instruction (repays NIRV debt by burning NIRV)
  /// Based on Chrome injection analysis of actual repay transactions
  Instruction buildRepayInstruction({
    required String userPubkey,
    required String personalAccount,
    required String userNirvAccount,
    required int nirvLamports,
  }) {
    // repay discriminator (confirmed from Chrome injection analysis)
    final discriminator = [28, 158, 130, 191, 125, 127, 195, 94];

    // Build instruction data
    final nirvBytes = Uint8List(8);
    nirvBytes.buffer.asByteData().setUint64(0, nirvLamports, Endian.little);

    final instructionData = [
      ...discriminator,
      ...nirvBytes,
    ];

    // Build accounts in exact order from Chrome injection analysis (6 accounts)
    // Repay burns NIRV to reduce debt
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),           // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true), // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),       // 2: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userNirvAccount), isSigner: false, isWriteable: true),       // 3: user NIRV account (burns NIRV)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.nirvMint), isSigner: false, isWriteable: true),      // 4: NIRV mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),         // 5: token program
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build claim prANA instruction (claims accumulated prANA rewards)
  /// Based on Chrome injection analysis of actual claim transactions
  Instruction buildClaimPranaInstruction({
    required String userPubkey,
    required String personalAccount,
    required String userPranaAccount,
  }) {
    // claim_prana discriminator (from browser injection log)
    final discriminator = [47, 124, 203, 241, 4, 53, 226, 166];

    // No amount parameter - claims all available prANA
    final instructionData = [...discriminator];

    // Build accounts in exact order from Chrome injection analysis (6 accounts)
    // Instruction 5 from claim_prANA.log:
    // 0: user (signer), 1: tenant, 2: pranaMint, 3: userPranaAccount, 4: personalAccount, 5: tokenProgram
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),              // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),  // 1: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.pranaMint), isSigner: false, isWriteable: true),      // 2: prANA mint
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPranaAccount), isSigner: false, isWriteable: true),       // 3: user prANA account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),        // 4: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),          // 5: token program
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build claim revenue share instruction (claims accumulated ANA + NIRV revenue)
  /// Based on Chrome injection analysis of actual claim revenue share transactions
  Instruction buildClaimRevenueShareInstruction({
    required String userPubkey,
    required String personalAccount,
    required String userAnaAccount,
    required String userNirvAccount,
  }) {
    // claim_revenue_share discriminator (from browser injection log)
    final discriminator = [69, 140, 105, 250, 40, 226, 233, 116];

    // No amount parameter - claims all available revenue share
    final instructionData = [...discriminator];

    // Build accounts in exact order from Chrome injection analysis (8 accounts)
    // Instruction 4 from claim_revenue_share log:
    // 0: user (signer), 1: personalAccount, 2: tenant, 3: escrowNirvAccount,
    // 4: escrowRevNirv, 5: userAnaAccount, 6: userNirvAccount, 7: tokenProgram
    final accounts = [
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userPubkey), isSigner: true, isWriteable: true),                 // 0: user/signer
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(personalAccount), isSigner: false, isWriteable: true),           // 1: personal account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.tenantAccount), isSigner: false, isWriteable: true),     // 2: tenant
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowNirvAccount), isSigner: false, isWriteable: true), // 3: escrow NIRV account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(_config.escrowRevNirv), isSigner: false, isWriteable: true),     // 4: escrow rev NIRV (ANA fees)
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userAnaAccount), isSigner: false, isWriteable: true),            // 5: user ANA account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(userNirvAccount), isSigner: false, isWriteable: true),           // 6: user NIRV account
      AccountMeta(pubKey: Ed25519HDPublicKey.fromBase58(tokenProgram), isSigner: false, isWriteable: false),             // 7: token program
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.programId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }
}