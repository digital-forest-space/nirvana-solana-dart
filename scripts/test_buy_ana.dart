import 'package:nirvana_solana/nirvana_solana.dart';

/// Test script for buy_exact2 instruction building
/// Compares library output with expected account order from companion

void main() {
  print('Testing Buy ANA Instruction Building\n');

  final builder = NirvanaTransactionBuilder();

  // Test accounts (from companion's browser-intercepted transaction)
  const userPubkey = 'YOUR_WALLET_ADDRESS_HERE';
  const userNirvAccount = '2MxgvoCvsrwBFHGAKchXJvCDFP7U4XNKA5TDE5Mg5ckh';
  const userAnaAccount = '3H7ih6Q1CiavvKSAoci6drN4c1rdKnHyTN3uqcZnmBFF';
  const userUsdcAccount = '7fjbQwUk34xaRicyM8UKsjKz5MvM4ZJzw7pxoWZBY9Mi'; // Valid base58

  // Expected account order from companion (browser-intercepted):
  // 0: User wallet (signer)
  // 1: Tenant account - BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV
  // 2: Price curve PDA - Fx5u5BCTwpckbB6jBbs13nDsRabHb5bq2t2hBDszhSbd
  // 3: NIRV mint - 5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW
  // 4: ANA mint - 3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM
  // 5: USDC mint - EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v
  // 6: Tenant USDC vault - FhTJEGXVwj4M6NQ1tPu9jgDZUXWQ9w2hP89ebZHwrJPS
  // 7: Tenant ANA vault - EkwPHXXZNAguNoxeftVRXThCQJfD6EaG852pDsYLs2eB
  // 8: Escrow rev NIRV - 42rJYSmYHqbn5mk992xAoKZnWEiuMzr6u6ydj9m8fAjP
  // 9: Payment source (NIRV or USDC depending on useNirv)
  // 10: User ANA account (destination)
  // 11-12: Token program (x2)

  print('=== Test 1: Buy with NIRV (useNirv=true) ===\n');

  final buyWithNirv = builder.buildBuyExact2Instruction(
    userPubkey: userPubkey,
    userPaymentAccount: userUsdcAccount, // Not used when useNirv=true
    userAnaAccount: userAnaAccount,
    userNirvAccount: userNirvAccount,
    amountLamports: 5000000, // 5 NIRV
    useNirv: true,
  );

  print('Instruction built with ${buyWithNirv.accounts.length} accounts:');
  for (int i = 0; i < buyWithNirv.accounts.length; i++) {
    final acc = buyWithNirv.accounts[i];
    final key = acc.pubKey.toBase58();
    final signer = acc.isSigner ? 'SIGNER' : '';
    final writable = acc.isWriteable ? 'W' : 'R';
    print('  [$i] $key [$writable] $signer');
  }

  // Verify key positions
  print('\nVerification:');
  final acc9 = buyWithNirv.accounts[9].pubKey.toBase58();
  final acc10 = buyWithNirv.accounts[10].pubKey.toBase58();

  print('  Position 9 (payment source): $acc9');
  print('  Expected (userNirvAccount):  $userNirvAccount');
  print('  Match: ${acc9 == userNirvAccount ? '✅' : '❌'}');

  print('  Position 10 (ANA destination): $acc10');
  print('  Expected (userAnaAccount):     $userAnaAccount');
  print('  Match: ${acc10 == userAnaAccount ? '✅' : '❌'}');

  print('\n=== Test 2: Buy with USDC (useNirv=false) ===\n');

  final buyWithUsdc = builder.buildBuyExact2Instruction(
    userPubkey: userPubkey,
    userPaymentAccount: userUsdcAccount,
    userAnaAccount: userAnaAccount,
    userNirvAccount: userNirvAccount, // Not used when useNirv=false
    amountLamports: 10000000, // 10 USDC
    useNirv: false,
  );

  print('Instruction built with ${buyWithUsdc.accounts.length} accounts:');
  final acc9Usdc = buyWithUsdc.accounts[9].pubKey.toBase58();
  final acc10Usdc = buyWithUsdc.accounts[10].pubKey.toBase58();

  print('  Position 9 (payment source): $acc9Usdc');
  print('  Expected (userUsdcAccount):  $userUsdcAccount');
  print('  Match: ${acc9Usdc == userUsdcAccount ? '✅' : '❌'}');

  print('  Position 10 (ANA destination): $acc10Usdc');
  print('  Expected (userAnaAccount):     $userAnaAccount');
  print('  Match: ${acc10Usdc == userAnaAccount ? '✅' : '❌'}');

  // Check instruction data
  print('\n=== Instruction Data ===');
  final data = buyWithNirv.data.toList();
  print('Data length: ${data.length} bytes');
  print('Discriminator: [${data.sublist(0, 8).join(', ')}]');
  print('Expected:      [109, 5, 199, 243, 164, 233, 19, 152]');

  final discriminatorMatch = data.sublist(0, 8).toString() == [109, 5, 199, 243, 164, 233, 19, 152].toString();
  print('Discriminator match: ${discriminatorMatch ? '✅' : '❌'}');

  print('\n=== Summary ===');
  final allPassed = acc9 == userNirvAccount &&
      acc10 == userAnaAccount &&
      acc9Usdc == userUsdcAccount &&
      acc10Usdc == userAnaAccount &&
      discriminatorMatch;

  if (allPassed) {
    print('All tests PASSED ✅');
  } else {
    print('Some tests FAILED ❌');
  }
}
