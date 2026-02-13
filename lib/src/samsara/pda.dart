import 'package:solana/solana.dart';

/// Samsara protocol PDA (Program Derived Address) derivations.
///
/// Seeds were extracted from the Samsara web app's client-side JS bundles.
/// See docs/samsara/pda_seeds.md for the full reference and discovery method.
class SamsaraPda {
  final Ed25519HDPublicKey samsaraProgramId;

  SamsaraPda(this.samsaraProgramId);

  factory SamsaraPda.mainnet() => SamsaraPda(
        Ed25519HDPublicKey.fromBase58(
            'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7'),
      );

  /// Personal governance account PDA.
  /// Seeds: ["personal_gov_account", market, owner]
  Future<Ed25519HDPublicKey> personalGovAccount({
    required Ed25519HDPublicKey market,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_gov_account'.codeUnits,
          market.bytes,
          owner.bytes,
        ],
        programId: samsaraProgramId,
      );

  /// prANA escrow token account PDA.
  /// Seeds: ["prana_escrow", govAccount]
  Future<Ed25519HDPublicKey> personalGovPranaEscrow({
    required Ed25519HDPublicKey govAccount,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'prana_escrow'.codeUnits,
          govAccount.bytes,
        ],
        programId: samsaraProgramId,
      );

  /// Singleton log counter PDA.
  /// Seeds: ["log_counter"]
  Future<Ed25519HDPublicKey> logCounter() =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: ['log_counter'.codeUnits],
        programId: samsaraProgramId,
      );

  /// Market PDA.
  /// Seeds: ["market", marketMeta]
  Future<Ed25519HDPublicKey> market({
    required Ed25519HDPublicKey marketMeta,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'market'.codeUnits,
          marketMeta.bytes,
        ],
        programId: samsaraProgramId,
      );

  /// Market cash escrow PDA.
  /// Seeds: ["cash_escrow", market]
  Future<Ed25519HDPublicKey> marketCashEscrow({
    required Ed25519HDPublicKey market,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'cash_escrow'.codeUnits,
          market.bytes,
        ],
        programId: samsaraProgramId,
      );

  /// Zen escrow PDA (cross-program, uses Mayflower personalPosition as input).
  /// Seeds: ["zen_escrow", personalAccount]
  Future<Ed25519HDPublicKey> personalZenEscrow({
    required Ed25519HDPublicKey personalAccount,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'zen_escrow'.codeUnits,
          personalAccount.bytes,
        ],
        programId: samsaraProgramId,
      );

  /// Tenant PDA.
  /// Seeds: ["tenant", seedAddress]
  Future<Ed25519HDPublicKey> tenant({
    required Ed25519HDPublicKey seedAddress,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'tenant'.codeUnits,
          seedAddress.bytes,
        ],
        programId: samsaraProgramId,
      );
}

/// Mayflower protocol PDA (Program Derived Address) derivations.
///
/// Seeds were extracted from the Samsara web app's client-side JS bundles.
/// See docs/samsara/pda_seeds.md for the full reference and discovery method.
class MayflowerPda {
  final Ed25519HDPublicKey mayflowerProgramId;

  MayflowerPda(this.mayflowerProgramId);

  factory MayflowerPda.mainnet() => MayflowerPda(
        Ed25519HDPublicKey.fromBase58(
            'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v'),
      );

  /// Personal position PDA (user's navToken position for a specific market).
  /// Seeds: ["personal_position", marketMetaAddress, owner]
  Future<Ed25519HDPublicKey> personalPosition({
    required Ed25519HDPublicKey marketMeta,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_position'.codeUnits,
          marketMeta.bytes,
          owner.bytes,
        ],
        programId: mayflowerProgramId,
      );

  /// Personal position escrow PDA (user's navToken shares token account).
  /// This is the "userShares" account used in buy/sell instructions.
  /// Seeds: ["personal_position_escrow", personalPositionAddress]
  Future<Ed25519HDPublicKey> personalPositionEscrow({
    required Ed25519HDPublicKey personalPosition,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_position_escrow'.codeUnits,
          personalPosition.bytes,
        ],
        programId: mayflowerProgramId,
      );

  /// Log account PDA.
  /// Seeds: ["log"]
  Future<Ed25519HDPublicKey> logAccount() =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: ['log'.codeUnits],
        programId: mayflowerProgramId,
      );

  /// Tenant PDA.
  /// Seeds: ["tenant", seedAddress]
  Future<Ed25519HDPublicKey> tenant({
    required Ed25519HDPublicKey seedAddress,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'tenant'.codeUnits,
          seedAddress.bytes,
        ],
        programId: mayflowerProgramId,
      );

  /// Market PDA.
  /// Seeds: ["market", seedAddress]
  Future<Ed25519HDPublicKey> market({
    required Ed25519HDPublicKey seedAddress,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'market'.codeUnits,
          seedAddress.bytes,
        ],
        programId: mayflowerProgramId,
      );

  /// Market metadata PDA.
  /// Seeds: ["market_meta", seedAddress]
  Future<Ed25519HDPublicKey> marketMeta({
    required Ed25519HDPublicKey seedAddress,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'market_meta'.codeUnits,
          seedAddress.bytes,
        ],
        programId: mayflowerProgramId,
      );

  /// Liquidity vault main authority PDA.
  /// Seeds: ["liq_vault_main", marketMetaAddress]
  Future<Ed25519HDPublicKey> liqVaultMain({
    required Ed25519HDPublicKey marketMeta,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'liq_vault_main'.codeUnits,
          marketMeta.bytes,
        ],
        programId: mayflowerProgramId,
      );
}
