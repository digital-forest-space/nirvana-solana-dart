import 'package:nirvana_solana/nirvana_solana.dart';

/// Test script for sell2 instruction building
/// Compares library output with expected account order from companion

void main() {
  print('Testing Sell ANA Instruction Building\n');

  final builder = NirvanaTransactionBuilder();

  // Test accounts (using same pattern as buy test)
  const userPubkey = 'YOUR_WALLET_ADDRESS_HERE';
  const userAnaAccount = '3H7ih6Q1CiavvKSAoci6drN4c1rdKnHyTN3uqcZnmBFF';
  const userUsdcAccount = 'FhTJEGXVwj4M6NQ1tPu9jgDZUXWQ9w2hP89ebZHwrJPS';

  // Expected account order from companion (Chrome injection analysis):
  // 0: user/signer (writable)
  // 1: tenant - BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV (writable)
  // 2: price curve - Fx5u5BCTwpckbB6jBbs13nDsRabHb5bq2t2hBDszhSbd (WRITABLE!)
  // 3: ANA mint - 5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW (writable)
  // 4: user USDC account (destination, writable)
  // 5: escrow ANA - 42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP (writable)
  // 6: tenant USDC vault - FhTJEGXVwj4M6NQ1tPu9jgDZUXWQ9w2hP89ebZHwrJPS (writable)
  // 7: tenant ANA vault - EkwPHXXZNAguNoxeftVRXThCQJfD6EaG852pDsYLs2eB (writable)
  // 8: user ANA account (source, writable)
  // 9: NIRV mint - 3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM (read-only)
  // 10: USDC mint - EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v (read-only)
  // 11-12: Token program (x2, read-only)

  print('=== Test: Sell ANA for USDC ===\n');

  final sellInstruction = builder.buildSellInstruction(
    userPubkey: userPubkey,
    userAnaAccount: userAnaAccount,
    userUsdcAccount: userUsdcAccount,
    anaLamports: 1000000, // 1 ANA
  );

  print('Instruction built with ${sellInstruction.accounts.length} accounts:');
  for (int i = 0; i < sellInstruction.accounts.length; i++) {
    final acc = sellInstruction.accounts[i];
    final key = acc.pubKey.toBase58();
    final signer = acc.isSigner ? 'SIGNER' : '';
    final writable = acc.isWriteable ? 'W' : 'R';
    print('  [$i] $key [$writable] $signer');
  }

  // Verify key positions
  print('\n=== Verification ===\n');

  final config = NirvanaConfig.mainnet();
  bool allPassed = true;

  // Position 2: priceCurve should be WRITABLE
  final pos2 = sellInstruction.accounts[2];
  final pos2Key = pos2.pubKey.toBase58();
  final pos2Writable = pos2.isWriteable;
  print('Position 2 (priceCurve):');
  print('  Key: $pos2Key');
  print('  Expected: ${config.priceCurve}');
  print('  Key match: ${pos2Key == config.priceCurve ? '✅' : '❌'}');
  print('  Writable: $pos2Writable (expected: true)');
  print('  Writable match: ${pos2Writable ? '✅' : '❌'}');
  if (pos2Key != config.priceCurve || !pos2Writable) allPassed = false;

  // Position 3: anaMint
  final pos3Key = sellInstruction.accounts[3].pubKey.toBase58();
  print('\nPosition 3 (anaMint):');
  print('  Key: $pos3Key');
  print('  Expected: ${config.anaMint}');
  print('  Match: ${pos3Key == config.anaMint ? '✅' : '❌'}');
  if (pos3Key != config.anaMint) allPassed = false;

  // Position 4: userUsdcAccount (destination)
  final pos4Key = sellInstruction.accounts[4].pubKey.toBase58();
  print('\nPosition 4 (userUsdcAccount - destination):');
  print('  Key: $pos4Key');
  print('  Expected: $userUsdcAccount');
  print('  Match: ${pos4Key == userUsdcAccount ? '✅' : '❌'}');
  if (pos4Key != userUsdcAccount) allPassed = false;

  // Position 8: userAnaAccount (source)
  final pos8Key = sellInstruction.accounts[8].pubKey.toBase58();
  print('\nPosition 8 (userAnaAccount - source):');
  print('  Key: $pos8Key');
  print('  Expected: $userAnaAccount');
  print('  Match: ${pos8Key == userAnaAccount ? '✅' : '❌'}');
  if (pos8Key != userAnaAccount) allPassed = false;

  // Position 9: nirvMint (read-only)
  final pos9 = sellInstruction.accounts[9];
  final pos9Key = pos9.pubKey.toBase58();
  final pos9Writable = pos9.isWriteable;
  print('\nPosition 9 (nirvMint):');
  print('  Key: $pos9Key');
  print('  Expected: ${config.nirvMint}');
  print('  Key match: ${pos9Key == config.nirvMint ? '✅' : '❌'}');
  print('  Read-only: ${!pos9Writable} (expected: true)');
  print('  Read-only match: ${!pos9Writable ? '✅' : '❌'}');
  if (pos9Key != config.nirvMint || pos9Writable) allPassed = false;

  // Position 10: usdcMint (read-only)
  final pos10 = sellInstruction.accounts[10];
  final pos10Key = pos10.pubKey.toBase58();
  final pos10Writable = pos10.isWriteable;
  print('\nPosition 10 (usdcMint):');
  print('  Key: $pos10Key');
  print('  Expected: ${config.usdcMint}');
  print('  Key match: ${pos10Key == config.usdcMint ? '✅' : '❌'}');
  print('  Read-only: ${!pos10Writable} (expected: true)');
  print('  Read-only match: ${!pos10Writable ? '✅' : '❌'}');
  if (pos10Key != config.usdcMint || pos10Writable) allPassed = false;

  // Check instruction data
  print('\n=== Instruction Data ===');
  final data = sellInstruction.data.toList();
  print('Data length: ${data.length} bytes');
  print('Discriminator: [${data.sublist(0, 8).join(', ')}]');
  print('Expected:      [47, 191, 120, 1, 28, 35, 253, 79]');

  final expectedDiscriminator = [47, 191, 120, 1, 28, 35, 253, 79];
  final discriminatorMatch = data.sublist(0, 8).toString() == expectedDiscriminator.toString();
  print('Discriminator match: ${discriminatorMatch ? '✅' : '❌'}');
  if (!discriminatorMatch) allPassed = false;

  // Check account count
  print('\n=== Account Count ===');
  print('Total accounts: ${sellInstruction.accounts.length}');
  print('Expected: 13');
  print('Match: ${sellInstruction.accounts.length == 13 ? '✅' : '❌'}');
  if (sellInstruction.accounts.length != 13) allPassed = false;

  print('\n=== Summary ===');
  if (allPassed) {
    print('All tests PASSED ✅');
  } else {
    print('Some tests FAILED ❌');
  }
}
