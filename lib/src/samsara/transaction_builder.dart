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

  static const List<int> _initPositionDiscriminator = SamsaraDiscriminators.initPersonalPosition;
  static const List<int> _buyDiscriminator = SamsaraDiscriminators.buy;

  /// Build init_personal_position instruction
  /// This must be called before the first buy for a fresh wallet
  Instruction buildInitPositionInstruction({
    required String userPubkey,
    required String personalPosition,
    required String userShares,
    required String logAccount,
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
      // 8: Mayflower log account (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logAccount),
        isSigner: false,
        isWriteable: true,
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
    required String logAccount,
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
      // 16: Mayflower log account (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logAccount),
        isSigner: false,
        isWriteable: true,
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

  /// Build Mayflower sell instruction for navSOL (SellWithExactTokenIn)
  ///
  /// Sells navToken for base token. The full transaction also requires:
  /// 1. ComputeBudget instructions (set units and price)
  /// 2. Create wSOL ATA (AssociatedToken idempotent) - for receiving output
  /// 3. Transfer 0 SOL to wSOL ATA (ensure account exists)
  /// 4. SyncNative on wSOL (Token program)
  /// 5. Create navSOL ATA (AssociatedToken idempotent)
  /// 6. THIS INSTRUCTION (Mayflower sell)
  /// 7. Close wSOL account (Token program - unwrap to native SOL)
  Instruction buildSellNavSolInstruction({
    required String userPubkey,
    required String userWsolAccount,
    required String userNavSolAccount,
    required String personalPosition,
    required String userShares,
    required String logAccount,
    required NavTokenMarket market,
    required int inputNavLamports,
    int minOutputLamports = 0,
  }) {
    // Build instruction data: discriminator + input amount + min output
    final inputBytes = Uint8List(8);
    inputBytes.buffer.asByteData().setUint64(0, inputNavLamports, Endian.little);
    final minOutputBytes = Uint8List(8);
    minOutputBytes.buffer.asByteData().setUint64(0, minOutputLamports, Endian.little);

    final instructionData = [
      ...SamsaraDiscriminators.sell,
      ...inputBytes,
      ...minOutputBytes,
    ];

    // Build accounts in exact order from intercepted sell transaction (18 accounts)
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
      // 4: Mayflower Market (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: personal_position PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: Market Base Vault (SOL vault, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketSolVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: Market navToken Vault (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketNavVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 8: Fee Vault (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.feeVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 9: navToken Mint (writable - burn)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.navMint),
        isSigner: false,
        isWriteable: true,
      ),
      // 10: Base Token Mint (wSOL)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.baseMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 11: User wSOL ATA (output destination, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userWsolAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 12: User navToken ATA (input source, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userNavSolAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 13: user_shares PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userShares),
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
      // 16: Mayflower log account (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logAccount),
        isSigner: false,
        isWriteable: true,
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
      data: ByteArray(Uint8List.fromList(SamsaraDiscriminators.initGovAccount)),
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
    data.setAll(0, SamsaraDiscriminators.depositPrana);
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

  /// Build Mayflower borrow instruction (borrows base token from market)
  ///
  /// Borrows base token (e.g., SOL) from the market's vault against the user's
  /// deposited prANA. The borrowed tokens are sent to the user's base token ATA.
  ///
  /// Based on browser interception of borrow transaction from navSOL market.
  Instruction buildBorrowInstruction({
    required String userPubkey,
    required String userBaseTokenAccount,
    required String personalPosition,
    required String logAccount,
    required NavTokenMarket market,
    required int borrowLamports,
  }) {
    // Build instruction data: discriminator + borrow amount
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, borrowLamports, Endian.little);

    final instructionData = [
      ...SamsaraDiscriminators.borrow,
      ...amountBytes,
    ];

    // Build accounts in exact order from intercepted borrow transaction (14 accounts)
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
      // 4: Market Base Vault (writable — funds leave vault)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketSolVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: Market navToken Vault (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketNavVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: Fee Vault (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.feeVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: Base Token Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.baseMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: User base token ATA (writable — receives borrowed tokens)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userBaseTokenAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 9: Mayflower Market (writable — tracks borrow state)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 10: Personal Position PDA (writable — tracks user's borrow)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 11: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 12: Mayflower log account (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(logAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 13: Mayflower Program
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

  /// Build Mayflower repay instruction (repays borrowed base token to market)
  ///
  /// Repays base token (e.g., SOL) back to the market's vault, reducing the
  /// user's borrow balance. The repaid tokens are transferred from the user's
  /// base token ATA to the market vault.
  ///
  /// Based on browser interception of repay transaction to navSOL market.
  Instruction buildRepayInstruction({
    required String userPubkey,
    required String userBaseTokenAccount,
    required String personalPosition,
    required NavTokenMarket market,
    required int repayLamports,
  }) {
    // Build instruction data: discriminator + repay amount
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, repayLamports, Endian.little);

    final instructionData = [
      ...SamsaraDiscriminators.repay,
      ...amountBytes,
    ];

    // Build accounts in exact order from intercepted repay transaction (10 accounts)
    final accounts = [
      // 0: User Wallet (signer)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: Market Metadata
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketMetadata),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: Mayflower Market (writable — tracks borrow state)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 3: Personal Position PDA (writable — tracks user's borrow)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 4: Base Token Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.baseMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 5: User base token ATA (writable — tokens leave here)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userBaseTokenAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: Market Base Vault (writable — tokens return here)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketSolVault),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: Authority PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.authorityPda),
        isSigner: false,
        isWriteable: true,
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
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build Mayflower deposit instruction (deposits navToken into personal position escrow)
  ///
  /// Deposits navToken (e.g., navSOL) from the user's wallet ATA into the
  /// market's personal position escrow. The user must already have a personal
  /// position for this market.
  ///
  /// Based on browser interception of deposit transaction to navSOL market.
  Instruction buildDepositNavTokenInstruction({
    required String userPubkey,
    required String userNavTokenAccount,
    required String personalPosition,
    required String userShares,
    required NavTokenMarket market,
    required int depositLamports,
  }) {
    // Build instruction data: discriminator + deposit amount
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, depositLamports, Endian.little);

    final instructionData = [
      ...SamsaraDiscriminators.deposit,
      ...amountBytes,
    ];

    // Build accounts in exact order from intercepted deposit transaction (10 accounts)
    final accounts = [
      // 0: User Wallet (signer)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: Market Metadata
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketMetadata),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: navToken Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.navMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 3: Mayflower Market (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 4: Personal Position PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: User Shares / escrow PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userShares),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: User navToken ATA (source, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userNavTokenAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: Authority PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.authorityPda),
        isSigner: false,
        isWriteable: true,
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
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build Mayflower withdraw instruction (withdraws navToken from personal position escrow)
  ///
  /// Withdraws navToken (e.g., navSOL) from the market's personal position
  /// escrow back to the user's wallet ATA. Same 10 accounts as deposit,
  /// different discriminator.
  ///
  /// Based on browser interception of withdraw transaction from navSOL market.
  Instruction buildWithdrawNavTokenInstruction({
    required String userPubkey,
    required String userNavTokenAccount,
    required String personalPosition,
    required String userShares,
    required NavTokenMarket market,
    required int withdrawLamports,
  }) {
    // Build instruction data: discriminator + withdraw amount
    final amountBytes = Uint8List(8);
    amountBytes.buffer.asByteData().setUint64(0, withdrawLamports, Endian.little);

    final instructionData = [
      ...SamsaraDiscriminators.withdraw,
      ...amountBytes,
    ];

    // Build accounts in exact order from intercepted withdraw transaction (10 accounts)
    // Same layout as deposit instruction
    final accounts = [
      // 0: User Wallet (signer)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: Market Metadata
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.marketMetadata),
        isSigner: false,
        isWriteable: false,
      ),
      // 2: navToken Mint
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.navMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 3: Mayflower Market (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.mayflowerMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 4: Personal Position PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(personalPosition),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: User Shares / escrow PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userShares),
        isSigner: false,
        isWriteable: true,
      ),
      // 6: User navToken ATA (destination, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userNavTokenAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 7: Token Program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 8: Authority PDA (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(market.authorityPda),
        isSigner: false,
        isWriteable: true,
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
      data: ByteArray(Uint8List.fromList(instructionData)),
    );
  }

  /// Build Samsara collectRevPrana instruction (claim accumulated prANA revenue).
  ///
  /// Claims revenue from prANA deposits in the market's govAccount.
  /// Revenue is paid in the market's base token (e.g., SOL for navSOL).
  /// Data is discriminator-only (8 bytes, no amount parameter).
  ///
  /// Based on browser interception of claim transaction from navSOL market.
  Instruction buildCollectRevPranaInstruction({
    required String userPubkey,
    required String samsaraMarket,
    required String govAccount,
    required String cashEscrow,
    required String cashDst,
    required String baseMint,
    required String samLogCounter,
  }) {
    final accounts = [
      // 0: Owner (signer, writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(userPubkey),
        isSigner: true,
        isWriteable: true,
      ),
      // 1: Samsara Market (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(samsaraMarket),
        isSigner: false,
        isWriteable: true,
      ),
      // 2: GovAccount (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(govAccount),
        isSigner: false,
        isWriteable: true,
      ),
      // 3: Cash escrow (writable — funds leave escrow)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(cashEscrow),
        isSigner: false,
        isWriteable: true,
      ),
      // 4: Cash destination — user's base token ATA (writable — receives rewards)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(cashDst),
        isSigner: false,
        isWriteable: true,
      ),
      // 5: Base token mint (read-only)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(baseMint),
        isSigner: false,
        isWriteable: false,
      ),
      // 6: Token program
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.tokenProgram),
        isSigner: false,
        isWriteable: false,
      ),
      // 7: Samsara log counter (writable)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(samLogCounter),
        isSigner: false,
        isWriteable: true,
      ),
      // 8: Samsara program (CPI target)
      AccountMeta(
        pubKey: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
        isSigner: false,
        isWriteable: false,
      ),
    ];

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(_config.samsaraProgramId),
      accounts: accounts,
      data: ByteArray(Uint8List.fromList(SamsaraDiscriminators.collectRevPrana)),
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
