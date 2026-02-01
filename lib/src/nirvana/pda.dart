import 'package:solana/solana.dart';

/// Nirvana V2 protocol PDA (Program Derived Address) derivations.
///
/// Seeds were extracted from the Nirvana web app's client-side JS bundles
/// at https://app.nirvana.finance/ (chunk 7292).
/// See docs/nirvana/pda_seeds.md for the full reference and discovery method.
class NirvanaPda {
  final Ed25519HDPublicKey programId;

  NirvanaPda(this.programId);

  factory NirvanaPda.mainnet() => NirvanaPda(
        Ed25519HDPublicKey.fromBase58(
            'NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb'),
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
        programId: programId,
      );

  /// Personal account PDA (user's position for staking/borrowing).
  /// Seeds: ["personal_position", tenant, owner]
  ///
  /// Note: The JS class calls this `personalAccount` but the seed string
  /// is "personal_position". The seed order is [tenant, owner].
  Future<Ed25519HDPublicKey> personalAccount({
    required Ed25519HDPublicKey tenant,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_position'.codeUnits,
          tenant.bytes,
          owner.bytes,
        ],
        programId: programId,
      );

  /// Price curve PDA.
  /// Seeds: ["price_curve", tenant]
  Future<Ed25519HDPublicKey> priceCurve({
    required Ed25519HDPublicKey tenant,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'price_curve'.codeUnits,
          tenant.bytes,
        ],
        programId: programId,
      );

  /// Curve ballot PDA.
  /// Seeds: ["curve_ballot", tenant]
  Future<Ed25519HDPublicKey> curveBallot({
    required Ed25519HDPublicKey tenant,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'curve_ballot'.codeUnits,
          tenant.bytes,
        ],
        programId: programId,
      );

  /// Personal curve ballot PDA.
  /// Seeds: ["personal_curve_ballot", tenant, owner]
  Future<Ed25519HDPublicKey> personalCurveBallot({
    required Ed25519HDPublicKey tenant,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'personal_curve_ballot'.codeUnits,
          tenant.bytes,
          owner.bytes,
        ],
        programId: programId,
      );

  /// Alms rewarder PDA.
  /// Seeds: ["alms_rewarder", tenant, owner]
  Future<Ed25519HDPublicKey> almsRewarder({
    required Ed25519HDPublicKey tenant,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'alms_rewarder'.codeUnits,
          tenant.bytes,
          owner.bytes,
        ],
        programId: programId,
      );

  /// Metta rewarder PDA.
  /// Seeds: ["metta_rewarder", tenant, owner]
  Future<Ed25519HDPublicKey> mettaRewarder({
    required Ed25519HDPublicKey tenant,
    required Ed25519HDPublicKey owner,
  }) =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          'metta_rewarder'.codeUnits,
          tenant.bytes,
          owner.bytes,
        ],
        programId: programId,
      );
}
