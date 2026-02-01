/// Verifies PDA seeds discovered from the Samsara JS bundle IDL.
///
/// From SamsaraPda class in the bundle:
///   personalGovAccount({market, owner}) => findProgramAddress(["personal_gov_account", market, owner])
///   personalGovPranaEscrow({govAccount}) => findProgramAddress(["prana_escrow", govAccount])
///   logCounter() => findProgramAddress(["log_counter"])
///
/// All PDAs are derived against the Samsara program.
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

  print('========================================');
  print('  Samsara PDA Seed Verification');
  print('========================================\n');
  print('Program:  SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7');
  print('User:     YOUR_WALLET_ADDRESS_HERE');
  print('Market:   4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc');
  print('');

  int passed = 0;
  int failed = 0;

  // -------------------------------------------------------
  // 1. personalGovAccount: ["personal_gov_account", market, owner]
  // -------------------------------------------------------
  print('--- Test 1: personalGovAccount ---');
  print('  Seeds: ["personal_gov_account", market.toBuffer(), owner.toBuffer()]');

  final govAccount = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('personal_gov_account'),
      navSolMarket.bytes,
      user.bytes,
    ],
    programId: samsaraProgram,
  );
  final derivedGovAccount = govAccount.toBase58();

  print('  Expected: $expectedGovAccount');
  print('  Derived:  $derivedGovAccount');
  if (derivedGovAccount == expectedGovAccount) {
    print('  Result:   PASS');
    passed++;
  } else {
    print('  Result:   FAIL');
    failed++;
  }
  print('');

  // -------------------------------------------------------
  // 2. personalGovPranaEscrow: ["prana_escrow", govAccount]
  //    Uses the govAccount derived in step 1
  // -------------------------------------------------------
  print('--- Test 2: personalGovPranaEscrow ---');
  print('  Seeds: ["prana_escrow", govAccount.toBuffer()]');
  print('  (govAccount from step 1: $derivedGovAccount)');

  final pranaEscrow = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('prana_escrow'),
      govAccount.bytes,
    ],
    programId: samsaraProgram,
  );
  final derivedPranaEscrow = pranaEscrow.toBase58();

  print('  Expected: $expectedPranaEscrow');
  print('  Derived:  $derivedPranaEscrow');
  if (derivedPranaEscrow == expectedPranaEscrow) {
    print('  Result:   PASS');
    passed++;
  } else {
    print('  Result:   FAIL');
    failed++;
  }
  print('');

  // -------------------------------------------------------
  // 3. logCounter: ["log_counter"]
  // -------------------------------------------------------
  print('--- Test 3: logCounter (samLogCounter) ---');
  print('  Seeds: ["log_counter"]');

  final logCounter = await Ed25519HDPublicKey.findProgramAddress(
    seeds: [
      utf8.encode('log_counter'),
    ],
    programId: samsaraProgram,
  );
  final derivedLogCounter = logCounter.toBase58();

  print('  Expected: $expectedLogCounter');
  print('  Derived:  $derivedLogCounter');
  if (derivedLogCounter == expectedLogCounter) {
    print('  Result:   PASS');
    passed++;
  } else {
    print('  Result:   FAIL');
    failed++;
  }
  print('');

  // -------------------------------------------------------
  // Summary
  // -------------------------------------------------------
  print('========================================');
  print('  Summary: $passed passed, $failed failed (out of 3)');
  print('========================================');

  if (failed > 0) {
    print('\nSome PDA derivations did not match. Check seed ordering or encoding.');
  } else {
    print('\nAll PDA seeds verified successfully!');
  }
}
