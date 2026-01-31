import 'dart:convert';

/// Canonical map of all Anchor instruction discriminators for the Nirvana
/// and Samsara (Mayflower) protocols.
///
/// Each discriminator is the first 8 bytes of `sha256('global:<instruction_name>')`.
/// They are used as the instruction identifier prefix in Solana transaction data.
class NirvanaDiscriminators {
  NirvanaDiscriminators._();

  // ── Nirvana V2 protocol ──────────────────────────────────────────────

  /// `buy_exact2` — Buy ANA with USDC or NIRV.
  static const List<int> buyExact2 = [109, 5, 199, 243, 164, 233, 19, 152];

  /// `sell2` — Sell ANA for USDC or NIRV.
  static const List<int> sell2 = [47, 191, 120, 1, 28, 35, 253, 79];

  /// `deposit_ana` — Stake ANA into the protocol.
  static const List<int> depositAna = [68, 100, 197, 87, 22, 85, 190, 78];

  /// `withdraw_ana` — Unstake ANA from the protocol.
  static const List<int> withdrawAna = [93, 87, 203, 252, 78, 187, 97, 82];

  /// `init_personal_account` — Create a user's personal account PDA.
  static const List<int> initPersonalAccount = [161, 176, 40, 213, 71, 95, 78, 42];

  /// `borrow_nirv` — Borrow NIRV against staked ANA.
  static const List<int> borrowNirv = [155, 1, 43, 62, 79, 104, 66, 42];

  /// `realize` — Convert prANA to ANA by paying USDC or NIRV.
  static const List<int> realize = [64, 34, 113, 17, 141, 79, 61, 38];

  /// `repay` — Repay NIRV debt by burning NIRV.
  static const List<int> repay = [28, 158, 130, 191, 125, 127, 195, 94];

  /// `refresh_price_curve` — Update protocol price state.
  static const List<int> refreshPriceCurve = [205, 200, 207, 206, 57, 131, 162, 126];

  /// `refresh_personal_account` — Sync accrued prANA rewards.
  static const List<int> refreshPersonalAccount = [54, 112, 82, 14, 216, 131, 165, 126];

  /// `claim_prana` — Claim accumulated prANA rewards.
  static const List<int> claimPrana = [47, 124, 203, 241, 4, 53, 226, 166];

  /// `claim_revenue_share` — Claim accumulated ANA + NIRV revenue.
  static const List<int> claimRevenueShare = [69, 140, 105, 250, 40, 226, 233, 116];

  /// `stage_rev_prana` — Stage revenue prANA for claiming.
  static const List<int> stageRevPrana = [66, 99, 75, 75, 81, 176, 254, 169];

  // ── Nirvana V2 account discriminators ────────────────────────────────

  /// Tenant account discriminator — identifies Nirvana tenant accounts.
  static const List<int> tenant = [61, 43, 215, 51, 232, 242, 209, 170];

  // ── Samsara / Mayflower protocol ─────────────────────────────────────

  /// `init_personal_position` — Create navToken personal position PDA.
  static const List<int> initPersonalPosition = [146, 163, 167, 48, 30, 216, 179, 88];

  /// `buy` (BuyWithExactCashInAndDeposit) — Buy navToken with base token.
  static const List<int> buyNavToken = [30, 205, 124, 67, 20, 142, 236, 136];

  /// All Nirvana V2 protocol discriminators keyed by instruction name.
  static const Map<String, List<int>> nirvana = {
    'buy_exact2': buyExact2,
    'sell2': sell2,
    'deposit_ana': depositAna,
    'withdraw_ana': withdrawAna,
    'init_personal_account': initPersonalAccount,
    'borrow_nirv': borrowNirv,
    'realize': realize,
    'repay': repay,
    'refresh_price_curve': refreshPriceCurve,
    'refresh_personal_account': refreshPersonalAccount,
    'claim_prana': claimPrana,
    'claim_revenue_share': claimRevenueShare,
    'stage_rev_prana': stageRevPrana,
  };

  /// All Samsara / Mayflower discriminators keyed by instruction name.
  static const Map<String, List<int>> samsara = {
    'init_personal_position': initPersonalPosition,
    'buy': buyNavToken,
  };

  /// Every discriminator across both protocols.
  static const Map<String, List<int>> all = {
    ...nirvana,
    ...samsara,
  };

  /// JSON-serialisable representation of all discriminators.
  ///
  /// Each value is the 8-byte discriminator as a `List<int>`.
  /// Example: `{"buy_exact2": [109, 5, 199, 243, 164, 233, 19, 152], ...}`
  static String toJson() => jsonEncode(all);
}
