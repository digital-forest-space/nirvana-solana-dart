import 'package:nirvana_solana/nirvana_solana.dart';

/// Test script for repay instruction building
/// Compares library output with expected account order from companion

void main() {
  print('Testing Repay Instruction Building\n');

  final builder = NirvanaTransactionBuilder();

  // Test accounts
  const userPubkey = 'YOUR_WALLET_ADDRESS_HERE';
  const personalAccount = '8xM1E4Ub3S5mM4XfVSJLxKQw5bZ3j7Z3p8Q4mYJq9K8b'; // Example PDA
  const userAnaAccount = '3H7ih6Q1CiavvKSAoci6drN4c1rdKnHyTN3uqcZnmBFF';

  // Expected account order from companion (Chrome injection analysis):
  // 0: user/signer (writable)
  // 1: tenant - BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV (writable)
  // 2: personal account (writable)
  // 3: user ANA account (burns ANA, writable)
  // 4: ANA mint - 5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW (writable)
  // 5: token program (read-only)

  print('=== Test: Repay NIRV Debt with ANA ===\n');

  final repayInstruction = builder.buildRepayInstruction(
    userPubkey: userPubkey,
    personalAccount: personalAccount,
    userAnaAccount: userAnaAccount,
    anaLamports: 1000000, // 1 ANA
  );

  print('Instruction built with ${repayInstruction.accounts.length} accounts:');
  for (int i = 0; i < repayInstruction.accounts.length; i++) {
    final acc = repayInstruction.accounts[i];
    final key = acc.pubKey.toBase58();
    final signer = acc.isSigner ? 'SIGNER' : '';
    final writable = acc.isWriteable ? 'W' : 'R';
    print('  [$i] $key [$writable] $signer');
  }

  // Verify key positions
  print('\n=== Verification ===\n');

  final config = NirvanaConfig.mainnet();
  bool allPassed = true;

  // Position 0: user (signer, writable)
  final pos0 = repayInstruction.accounts[0];
  print('Position 0 (user):');
  print('  Key: ${pos0.pubKey.toBase58()}');
  print('  Expected: $userPubkey');
  print('  Key match: ${pos0.pubKey.toBase58() == userPubkey ? '✅' : '❌'}');
  print('  Is signer: ${pos0.isSigner ? '✅' : '❌'}');
  print('  Is writable: ${pos0.isWriteable ? '✅' : '❌'}');
  if (pos0.pubKey.toBase58() != userPubkey || !pos0.isSigner || !pos0.isWriteable) allPassed = false;

  // Position 1: tenant (writable)
  final pos1Key = repayInstruction.accounts[1].pubKey.toBase58();
  print('\nPosition 1 (tenant):');
  print('  Key: $pos1Key');
  print('  Expected: ${config.tenantAccount}');
  print('  Match: ${pos1Key == config.tenantAccount ? '✅' : '❌'}');
  if (pos1Key != config.tenantAccount) allPassed = false;

  // Position 2: personal account (writable)
  final pos2Key = repayInstruction.accounts[2].pubKey.toBase58();
  print('\nPosition 2 (personalAccount):');
  print('  Key: $pos2Key');
  print('  Expected: $personalAccount');
  print('  Match: ${pos2Key == personalAccount ? '✅' : '❌'}');
  if (pos2Key != personalAccount) allPassed = false;

  // Position 3: user ANA account (writable)
  final pos3Key = repayInstruction.accounts[3].pubKey.toBase58();
  print('\nPosition 3 (userAnaAccount):');
  print('  Key: $pos3Key');
  print('  Expected: $userAnaAccount');
  print('  Match: ${pos3Key == userAnaAccount ? '✅' : '❌'}');
  if (pos3Key != userAnaAccount) allPassed = false;

  // Position 4: ANA mint (writable)
  final pos4Key = repayInstruction.accounts[4].pubKey.toBase58();
  print('\nPosition 4 (anaMint):');
  print('  Key: $pos4Key');
  print('  Expected: ${config.anaMint}');
  print('  Match: ${pos4Key == config.anaMint ? '✅' : '❌'}');
  if (pos4Key != config.anaMint) allPassed = false;

  // Position 5: token program (read-only)
  final pos5 = repayInstruction.accounts[5];
  final pos5Key = pos5.pubKey.toBase58();
  const tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  print('\nPosition 5 (tokenProgram):');
  print('  Key: $pos5Key');
  print('  Expected: $tokenProgram');
  print('  Key match: ${pos5Key == tokenProgram ? '✅' : '❌'}');
  print('  Read-only: ${!pos5.isWriteable ? '✅' : '❌'}');
  if (pos5Key != tokenProgram || pos5.isWriteable) allPassed = false;

  // Check instruction data
  print('\n=== Instruction Data ===');
  final data = repayInstruction.data.toList();
  print('Data length: ${data.length} bytes');
  print('Discriminator: [${data.sublist(0, 8).join(', ')}]');
  print('Expected:      [28, 158, 130, 191, 125, 127, 195, 94]');

  final expectedDiscriminator = [28, 158, 130, 191, 125, 127, 195, 94];
  final discriminatorMatch = data.sublist(0, 8).toString() == expectedDiscriminator.toString();
  print('Discriminator match: ${discriminatorMatch ? '✅' : '❌'}');
  if (!discriminatorMatch) allPassed = false;

  // Check account count
  print('\n=== Account Count ===');
  print('Total accounts: ${repayInstruction.accounts.length}');
  print('Expected: 6');
  print('Match: ${repayInstruction.accounts.length == 6 ? '✅' : '❌'}');
  if (repayInstruction.accounts.length != 6) allPassed = false;

  print('\n=== Summary ===');
  if (allPassed) {
    print('All tests PASSED ✅');
  } else {
    print('Some tests FAILED ❌');
  }
}
