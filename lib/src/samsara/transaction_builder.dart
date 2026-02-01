import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';
import 'config.dart';
import '../discriminators.dart';

/// Builds Solana instructions for Samsara protocol operations (navTokens)
class SamsaraTransactionBuilder {
  final SamsaraConfig _config;

  SamsaraTransactionBuilder({SamsaraConfig? config})
      : _config = config ?? SamsaraConfig.mainnet();

  static const List<int> _initPositionDiscriminator = NirvanaDiscriminators.initPersonalPosition;
  static const List<int> _buyDiscriminator = NirvanaDiscriminators.buyNavToken;

  /// Build init_personal_position instruction
  /// This must be called before the first buy for a fresh wallet
  Instruction buildInitPositionInstruction({
    required String userPubkey,
    required String personalPosition,
    required String userShares,
    required NavTokenMarket market,
  }) {
    final accounts = [
      // 0: User wallet (signer, payer)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: User wallet again (owner)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: Market Metadata
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketMetadata),
        isSigner: false,
        isWriteable: false,
      ),
      // 3: navToken Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.navMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 4: personal_position PDA (will be created)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: user_shares PDA (will be created)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userShares),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 7: System Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.systemProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: Authority PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.authorityPda),
        isSigner: false,
        isWriteable: false,
      ),
      // 9: Mayflower Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId),
        isSigner: false,
        isWriteable: false,
      ),
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(_initPositionDiscriminator)),
    );
  }

  /// Build Mayflower buy instruction for navSOL (BuyWithExactCashInAndDeposit)
  ///
  /// This builds the main Mayflower instruction. The full transaction also requires:
  /// 1. ComputeBudget instructions (set units and price)
  /// 2. Create wSOL ATA (AssociatedToken idempotent)
  /// 3. Transfer SOL to wSOL ATA (System transfer)
  /// 4. SyncNative on wSOL (Token program)
  /// 5. Create navSOL ATA (AssociatedToken idempotent)
  /// 6. Init personal_position (if fresh wallet)
  /// 7. THIS INSTRUCTION (Mayflower buy)
  /// 8. Close wSOL account (Token program)
  Instruction buildBuyNavSolInstruction({
    required String userPubkey,
    required String userWsolAccount,
    required String userNavSolAccount,
    required String personalPosition,
    required String userShares,
    required NavTokenMarket market,
    required int inputLamports,
    int minOutputLamports = 0,
  }) {
    // Build instruction data: discriminator + input amount + min output
    final inputBytes = Uint8List(8);
    inputBytes.buffer.asByteData().setUint64(0, inputLamports, Endian.little);
    final minOutputBytes = Uint8List(8);
    minOutputBytes.buffer.asByteData().setUint64(0, minOutputLamports, Endian.little);

    final instructionData = [
      ..._buyDiscriminator,
      ...inputBytes,
      ...minOutputBytes,
    ];

    // Build accounts in exact order from intercepted transaction (18 accounts)
    // Corrected based on fresh wallet interception analysis
    final accounts = [
      // 0: User Wallet (signer)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: Mayflower Tenant
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.mayflowerTenant),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: Market Group
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketGroup),
        isSigner: false,
        isWriteable: false,
      ),
      // 3: Market Metadata
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketMetadata),
        isSigner: false,
        isWriteable: false,
      ),
      // 4: Mayflower Market
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: personal_position PDA (USER-SPECIFIC, MUST BE WRITABLE)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: user_shares PDA (USER-SPECIFIC, MUST BE WRITABLE)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userShares),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: navToken Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.navMint),
        isSigner: false,
        isWriteable: true,
      ),
      // 8: Base Token Mint (wSOL)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.baseMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 9: User navToken ATA (output destination)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userNavSolAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 10: User wSOL ATA (input source)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userWsolAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 11: Market Base Vault (SOL vault)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketSolVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 12: Market navToken Vault
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketNavVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 13: Fee Vault
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.feeVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 14: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 15: Token Program (duplicate)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 16: Authority PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.authorityPda),
        isSigner: false,
        isWriteable: false,
      ),
      // 17: Mayflower Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId),
        isSigner: false,
        isWriteable: false,
      ),
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.mayflowerProgramId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build ComputeBudget SetComputeUnitLimit instruction
  Instruction buildSetComputeUnitLimitInstruction(int units) {
    // Instruction type 2 = SetComputeUnitLimit
    final data = Uint8List(5);
    data[0] = 2; // instruction type
    data.buffer.asByteData().setUint32(1, units, Endian.little);

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.computeBudgetProgram),
      accounts: [],
      data: ByteArray(data),
    );
  }

  /// Build ComputeBudget SetComputeUnitPrice instruction
  Instruction buildSetComputeUnitPriceInstruction(int microLamports) {
    // Instruction type 3 = SetComputeUnitPrice
    final data = Uint8List(9);
    data[0] = 3; // instruction type
    data.buffer.asByteData().setUint64(1, microLamports, Endian.little);

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.computeBudgetProgram),
      accounts: [],
      data: ByteArray(data),
    );
  }

  /// Build System Transfer instruction (for wrapping SOL)
  Instruction buildTransferInstruction({
    required String from,
    required String to,
    required int lamports,
  }) {
    // System program transfer instruction type = 2
    final data = Uint8List(12);
    data.buffer.asByteData().setUint32(0, 2, Endian.little); // instruction type
    data.buffer.asByteData().setUint64(4, lamports, Endian.little);

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.systemProgram),
      accounts: [
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(from),
          isSigner: true,
          isWriteable: true,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(to),
          isSigner: false,
          isWriteable: true,
        ),
      ],
      data: ByteArray(data),
    );
  }

  /// Build Token SyncNative instruction
  Instruction buildSyncNativeInstruction(String tokenAccount) {
    // SyncNative = instruction type 17 (0x11)
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
      accounts: [
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(tokenAccount),
          isSigner: false,
          isWriteable: true,
        ),
      ],
      data: ByteArray(Uint8List.fromList([17])),
    );
  }

  /// Build Token CloseAccount instruction
  Instruction buildCloseAccountInstruction({
    required String account,
    required String destination,
    required String owner,
  }) {
    // CloseAccount = instruction type 9
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
      accounts: [
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(account),
          isSigner: false,
          isWriteable: true,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(destination),
          isSigner: false,
          isWriteable: true,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(owner),
          isSigner: true,
          isWriteable: false,
        ),
      ],
      data: ByteArray(Uint8List.fromList([9])),
    );
  }

  /// Build Samsara init_gov_account instruction
  ///
  /// Creates a user's governance account for a specific Samsara market.
  /// Must be called before the first depositPrana for a given market+owner pair.
  Instruction buildInitGovAccountInstruction({
    required String payerPubkey,
    required String ownerPubkey,
    required NavTokenMarket market,
    required String govAccount,
    required String pranaEscrow,
    required String logCounter,
  }) {
    final accounts = [
      // 0: payer (signer, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(payerPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: owner (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(ownerPubkey),
        isSigner: false,
        isWriteable: true,
      ),
      // 2: tenant (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.samsaraTenant),
        isSigner: false,
        isWriteable: false,
      ),
      // 3: mintPrana (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.pranaMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 4: market (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.samsaraMarket),
        isSigner: false,
        isWriteable: false,
      ),
      // 5: pranaEscrow (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(pranaEscrow),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: govAccount (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(govAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: tokenProgram (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: systemProgram (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.systemProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 9: samLogCounter (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logCounter),
        isSigner: false,
        isWriteable: true,
      ),
      // 10: samsaraProgram (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
        isSigner: false,
        isWriteable: false,
      ),
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(NirvanaDiscriminators.initGovAccount)),
    );
  }

  /// Build Samsara deposit_prana instruction
  ///
  /// Deposits prANA tokens into a market's governance account.
  /// The govAccount must already exist (call initGovAccount first).
  Instruction buildDepositPranaInstruction({
    required String depositorPubkey,
    required NavTokenMarket market,
    required String govAccount,
    required String pranaSrc,
    required String pranaEscrow,
    required String logCounter,
    required int amount,
  }) {
    // Instruction data: discriminator (8 bytes) + amount (u64 LE, 8 bytes)
    final data = Uint8List(16);
    data.setAll(0, NirvanaDiscriminators.depositPrana);
    data.buffer.asByteData().setUint64(8, amount, Endian.little);

    final accounts = [
      // 0: depositor (signer, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(depositorPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: tenant (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.samsaraTenant),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: market (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.samsaraMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 3: govAccount (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(govAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 4: mintPrana (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.pranaMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 5: pranaSrc (writable) -- user's prANA token account
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(pranaSrc),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: pranaEscrow (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(pranaEscrow),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: tokenProgram (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: samLogCounter (writable) -- PDA
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logCounter),
        isSigner: false,
        isWriteable: true,
      ),
      // 9: samsaraProgram (readonly)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
        isSigner: false,
        isWriteable: false,
      ),
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
      accounts: accounts,
      data: ByteArray(data),
    );
  }

  /// Build CreateAssociatedTokenAccountIdempotent instruction
  Instruction buildCreateAtaIdempotentInstruction({
    required String payer,
    required String associatedTokenAccount,
    required String owner,
    required String mint,
  }) {
    // CreateIdempotent = instruction type 1
    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.associatedTokenProgram),
      accounts: [
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(payer),
          isSigner: true,
          isWriteable: true,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(associatedTokenAccount),
          isSigner: false,
          isWriteable: true,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(owner),
          isSigner: false,
          isWriteable: false,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(mint),
          isSigner: false,
          isWriteable: false,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(_config.systemProgram),
          isSigner: false,
          isWriteable: false,
        ),
        AccountMeta(
          pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
          isSigner: false,
          isWriteable: false,
        ),
      ],
      data: ByteArray(Uint8List.fromList([1])),
    );
  }
}
