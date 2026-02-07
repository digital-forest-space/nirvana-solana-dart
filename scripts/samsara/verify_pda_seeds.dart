/// Verifies PDA seeds discovered from the Samsara JS bundle IDL.
///
/// From SamsaraPda class in the bundle:
///   personalGovAccount({market, owner}) => findProgramAddress(["personal_gov_account", market, owner])
///   personalGovPranaEscrow({govAccount}) => findProgramAddress(["prana_escrow", govAccount])
///   logCounter() => findProgramAddress(["log_counter"])
///
/// All PDAs are derived against the Samsara program.
import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'package:solana/solana.dart';

void main() async {
  // --- Constants ---
  final samsaraProgram = Ed25519HDPublicKey.fromBase58(
    'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7',
  );
  final user = Ed25519HDPublicKey.fromBase58(
    'YOUR_WALLET_ADDRESS_HERE',
  );
  final navSolMarket = Ed25519HDPublicKey.fromBase58(
    '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc',
  );

  // Expected results
  const expectedGovAccount = 'Gvj2W5XvB611ZJqZvAWdTUcD2uB2UkfFqgv3R4ico6gw';
  const expectedPranaEscrow = 'A2mQkk1zdUx1uMn2BXiKQ57vQVPB3Soi9dtCwVHkdotM';
  const expectedLogCounter = 'G5GdMpizMafXkcPrLzmf1H7bQR3CMyxoMsHYmXKFaAdA';

  LogService.log('========================================');
  LogService.log('  Samsara PDA Seed Verification');
  LogService.log('========================================\n');
  LogService.log('Program:  SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7');
  LogService.log('User:     YOUR_WALLET_ADDRESS_HERE');
  LogService.log('Market:   4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc');
  LogService.log('');

  int passed = 0;
  int failed = 0;

  // -------------------------------------------------------
  // 1. personalGovAccount: ["personal_gov_account", market, owner]
  // -------------------------------------------------------
  LogService.log('--- Test 1: personalGovAccount ---');
  LogService.log('  Seeds: ["personal_gov_account", market.toBuffer(), owner.toBuffer()]');

  final govAccount = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('personal_gov_account'),
      navSolMarket.bytes,
      user.bytes,
    ],
    programId: samsaraProgram,
  );
  final derivedGovAccount = govAccount.toBase58();

  LogService.log('  Expected: $expectedGovAccount');
  LogService.log('  Derived:  $derivedGovAccount');
  if (derivedGovAccount == expectedGovAccount) {
    LogService.log('  Result:   PASS');
    passed++;
  } else {
    LogService.log('  Result:   FAIL');
    failed++;
  }
  LogService.log('');

  // -------------------------------------------------------
  // 2. personalGovPranaEscrow: ["prana_escrow", govAccount]
  //    Uses the govAccount derived in step 1
  // -------------------------------------------------------
  LogService.log('--- Test 2: personalGovPranaEscrow ---');
  LogService.log('  Seeds: ["prana_escrow", govAccount.toBuffer()]');
  LogService.log('  (govAccount from step 1: $derivedGovAccount)');

  final pranaEscrow = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('prana_escrow'),
      govAccount.bytes,
    ],
    programId: samsaraProgram,
  );
  final derivedPranaEscrow = pranaEscrow.toBase58();

  LogService.log('  Expected: $expectedPranaEscrow');
  LogService.log('  Derived:  $derivedPranaEscrow');
  if (derivedPranaEscrow == expectedPranaEscrow) {
    LogService.log('  Result:   PASS');
    passed++;
  } else {
    LogService.log('  Result:   FAIL');
    failed++;
  }
  LogService.log('');

  // -------------------------------------------------------
  // 3. logCounter: ["log_counter"]
  // -------------------------------------------------------
  LogService.log('--- Test 3: logCounter (samLogCounter) ---');
  LogService.log('  Seeds: ["log_counter"]');

  final logCounter = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('log_counter'),
    ],
    programId: samsaraProgram,
  );
  final derivedLogCounter = logCounter.toBase58();

  LogService.log('  Expected: $expectedLogCounter');
  LogService.log('  Derived:  $derivedLogCounter');
  if (derivedLogCounter == expectedLogCounter) {
    LogService.log('  Result:   PASS');
    passed++;
  } else {
    LogService.log('  Result:   FAIL');
    failed++;
  }
  LogService.log('');

  // -------------------------------------------------------
  // Summary
  // -------------------------------------------------------
  LogService.log('========================================');
  LogService.log('  Summary: $passed passed, $failed failed (out of 3)');
  LogService.log('========================================');

  if (failed > 0) {
    LogService.log('\nSome PDA derivations did not match. Check seed ordering or encoding.');
  } else {
    LogService.log('\nAll PDA seeds verified successfully!');
  }
}
