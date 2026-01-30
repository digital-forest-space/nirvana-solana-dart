import 'package:solana/solana.dart';

void main() async {
  final mayflowerProgram = Ed25519HDPublicKey.fromBase58('AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v');

  // User 1 (ag982bh...)
  final user1 = Ed25519HDPublicKey.fromBase58('YOUR_WALLET_ADDRESS_HERE');
  const expectedPosition1 = 'GsCuiZUzBsUcwtm4E95QvNFRAE25u8TBvBAD1ZJycjGf';
  const expectedShares1 = '67x1iMn9Gx14TPUbifFft44TbC27atwsk22bKKS17im5';

  // User 2 (df78cxz...)
  final user2 = Ed25519HDPublicKey.fromBase58('YOUR_WALLET_ADDRESS_HERE');
  const expectedPosition2 = 'J55Lc31GF5ae5xeztckqQEbWd6Xmkp37YYHzCy7VtgZ1';
  const expectedShares2 = '8aCFTTWQRUvEgycNikKMjnkE2L99xM2qy1Z6Cfxq8ZKQ';

  // Market data
  final marketMetadata = Ed25519HDPublicKey.fromBase58('DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj');
  final mayflowerMarket = Ed25519HDPublicKey.fromBase58('A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc');
  final navMint = Ed25519HDPublicKey.fromBase58('navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo');
  final marketGroup = Ed25519HDPublicKey.fromBase58('Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC');
  final authority = Ed25519HDPublicKey.fromBase58('EKVkmuwDKRKHw85NPTbKSKuS75EY4NLcxe1qzSPixLdy');

  print('Testing PDA derivations...\n');
  print('User 1: YOUR_WALLET_ADDRESS_HERE');
  print('Expected position: $expectedPosition1');
  print('Expected shares: $expectedShares1\n');

  // Different string prefixes to try
  final prefixes = [
    'position',
    'personal_position',
    'personal',
    'user_position',
    'pos',
    'pp',
  ];

  // Try with various market accounts
  final marketAccounts = {
    'marketMetadata': marketMetadata,
    'mayflowerMarket': mayflowerMarket,
    'marketGroup': marketGroup,
    'navMint': navMint,
    'authority': authority,
  };

  print('=== Testing personal_position PDA ===\n');

  // Try [prefix, user, market]
  for (final prefix in prefixes) {
    for (final entry in marketAccounts.entries) {
      try {
        final seeds = [prefix.codeUnits, user1.bytes, entry.value.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedPosition1) {
          print('✅ MATCH! Seeds: ["$prefix", user, ${entry.key}]');
          print('   Result: ${pda.toBase58()}\n');
        }
      } catch (_) {}
    }
  }

  // Try [prefix, market, user]
  for (final prefix in prefixes) {
    for (final entry in marketAccounts.entries) {
      try {
        final seeds = [prefix.codeUnits, entry.value.bytes, user1.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedPosition1) {
          print('✅ MATCH! Seeds: ["$prefix", ${entry.key}, user]');
          print('   Result: ${pda.toBase58()}\n');
        }
      } catch (_) {}
    }
  }

  // Try [user, market] without prefix
  for (final entry in marketAccounts.entries) {
    try {
      final seeds = [user1.bytes, entry.value.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedPosition1) {
        print('✅ MATCH! Seeds: [user, ${entry.key}]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try [market, user] without prefix
  for (final entry in marketAccounts.entries) {
    try {
      final seeds = [entry.value.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedPosition1) {
        print('✅ MATCH! Seeds: [${entry.key}, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    // Also try with navMint as third seed
    try {
      final seeds = [entry.value.bytes, user1.bytes, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedPosition1) {
        print('✅ MATCH! Seeds: [${entry.key}, user, navMint]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  print('\n=== Testing user_shares PDA ===\n');

  // User shares prefixes - expanded list
  final sharesPrefixes = [
    'shares',
    'user_shares',
    'nav_shares',
    'stake',
    'deposit',
    'user_nav_shares',
    'nav_position',
    'token_shares',
    'staked',
    'deposited',
    'user_deposit',
    'user_stake',
    'nav_stake',
    'position_shares',
  ];

  for (final prefix in sharesPrefixes) {
    for (final entry in marketAccounts.entries) {
      // [prefix, user, market]
      try {
        final seeds = [prefix.codeUnits, user1.bytes, entry.value.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedShares1) {
          print('✅ MATCH! Seeds: ["$prefix", user, ${entry.key}]');
          print('   Result: ${pda.toBase58()}\n');
        }
      } catch (_) {}

      // [prefix, user, market, navMint]
      try {
        final seeds = [prefix.codeUnits, user1.bytes, entry.value.bytes, navMint.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedShares1) {
          print('✅ MATCH! Seeds: ["$prefix", user, ${entry.key}, navMint]');
          print('   Result: ${pda.toBase58()}\n');
        }
      } catch (_) {}
    }
  }

  // Try without prefix
  for (final entry in marketAccounts.entries) {
    try {
      final seeds = [user1.bytes, entry.value.bytes, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [user, ${entry.key}, navMint]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Maybe user_shares is derived from the personal_position address?
  final pp1 = Ed25519HDPublicKey.fromBase58(expectedPosition1);
  try {
    final seeds = [pp1.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! Seeds: [personal_position, navMint]');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  // Try with personal_position and different combinations
  for (final prefix in sharesPrefixes) {
    try {
      final seeds = [prefix.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", personal_position]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, pp1.bytes, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", personal_position, navMint]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try [prefix, marketMetadata, user] pattern (same as personal_position but different prefix)
  for (final prefix in sharesPrefixes) {
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketMetadata, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try navMint-based patterns
  for (final prefix in sharesPrefixes) {
    try {
      final seeds = [prefix.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", navMint, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, user1.bytes, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", user, navMint]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try without prefix, navMint combinations
  try {
    final seeds = [navMint.bytes, user1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! Seeds: [navMint, user]');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  try {
    final seeds = [user1.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! Seeds: [user, navMint]');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  // Try marketMetadata + navMint combinations
  try {
    final seeds = [marketMetadata.bytes, navMint.bytes, user1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! Seeds: [marketMetadata, navMint, user]');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  // Maybe it's a token account PDA? Try with ATA-style seeds
  final tokenProgram = Ed25519HDPublicKey.fromBase58('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA');
  final ataProgram = Ed25519HDPublicKey.fromBase58('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL');

  // Standard ATA derivation
  try {
    final seeds = [user1.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! ATA Seeds: [user, tokenProgram, navMint] with ATA program');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  // Try with authority PDA as seed
  try {
    final seeds = [user1.bytes, authority.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH! Seeds: [user, authority, navMint]');
      print('   Result: ${pda.toBase58()}\n');
    }
  } catch (_) {}

  // Try with Samsara program ID instead of Mayflower
  print('\n=== Testing with Samsara program ===\n');
  final samsaraProgram = Ed25519HDPublicKey.fromBase58('SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7');

  for (final prefix in sharesPrefixes) {
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: samsaraProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Samsara Seeds: ["$prefix", marketMetadata, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: samsaraProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Samsara Seeds: ["$prefix", navMint, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, user1.bytes, marketMetadata.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: samsaraProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Samsara Seeds: ["$prefix", user, marketMetadata]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try with mayflowerMarket as seed
  print('\n=== Testing with mayflowerMarket seed ===\n');
  for (final prefix in sharesPrefixes) {
    try {
      final seeds = [prefix.codeUnits, mayflowerMarket.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", mayflowerMarket, user]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, user1.bytes, mayflowerMarket.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", user, mayflowerMarket]');
        print('   Result: ${pda.toBase58()}\n');
      }
    } catch (_) {}
  }

  // Try user_shares with personal_position-like pattern but different prefix
  print('\n=== Testing user_shares with position-like patterns ===\n');
  final ppPrefixes = ['user_shares', 'shares', 'nav_shares', 'user_nav_shares', 'position_shares', 'staked_shares'];
  for (final prefix in ppPrefixes) {
    // Same pattern as personal_position: [prefix, marketMetadata, user]
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      print('   Testing ["$prefix", marketMetadata, user] -> ${pda.toBase58()}');
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH!');
      }
    } catch (e) {
      print('   Error with "$prefix": $e');
    }
  }

  // Try "user_nav_shares" or "staked" specific patterns
  print('\n=== Testing specific prefix patterns ===\n');
  final specificPrefixes = ['nav', 'staked_nav', 'user_nav', 'nav_stake', 'stake_account', 'deposited_nav'];
  for (final prefix in specificPrefixes) {
    for (final entry in marketAccounts.entries) {
      try {
        final seeds = [prefix.codeUnits, entry.value.bytes, user1.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedShares1) {
          print('✅ MATCH! Seeds: ["$prefix", ${entry.key}, user]');
          print('   Result: ${pda.toBase58()}\n');
        }
      } catch (_) {}
    }
  }

  // Check if user_shares is simply an ATA for navMint
  print('\n=== Checking if user_shares is an ATA ===\n');
  try {
    // Standard ATA derivation: [owner, tokenProgram, mint] with ATA program
    final seeds = [user1.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    print('User1 navMint ATA: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ user_shares IS the navMint ATA!');
    } else {
      print('❌ Not a match. Expected: $expectedShares1');
    }
  } catch (e) {
    print('Error computing ATA: $e');
  }

  // Maybe the "shares" are tied to the personal_position account derived earlier
  // Let's check if user_shares is an ATA owned by the personal_position
  print('\n=== Checking if user_shares is ATA owned by personal_position ===\n');
  try {
    final seeds = [pp1.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    print('personal_position navMint ATA: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ user_shares IS the ATA owned by personal_position!');
    } else {
      print('❌ Not a match. Expected: $expectedShares1');
    }
  } catch (e) {
    print('Error computing ATA: $e');
  }

  // Check if it's an ATA owned by authority PDA
  print('\n=== Checking if user_shares is ATA owned by authority ===\n');
  try {
    final seeds = [authority.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    print('authority navMint ATA: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ user_shares IS the ATA owned by authority!');
    }
  } catch (e) {
    print('Error: $e');
  }

  // Let's try a different approach - print ALL possible combinations with the exact address we need
  print('\n=== Brute force: trying byte combinations ===\n');
  // user_shares might use a single-byte seed or numeric
  for (int i = 0; i < 256; i++) {
    try {
      final seeds = [[i], marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [[$i], marketMetadata, user]');
      }
    } catch (_) {}

    try {
      final seeds = [[i], user1.bytes, marketMetadata.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [[$i], user, marketMetadata]');
      }
    } catch (_) {}

    try {
      final seeds = [[i], navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [[$i], navMint, user]');
      }
    } catch (_) {}
  }

  // Try with personal_position and various suffixes
  print('\n=== Testing derivation from personal_position ===\n');
  final ppSuffixes = ['shares', 'nav', 'token', 'stake', 'deposit', 'balance', 'account'];
  for (final suffix in ppSuffixes) {
    try {
      final seeds = [pp1.bytes, suffix.codeUnits];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [personal_position, "$suffix"]');
      }
    } catch (_) {}

    try {
      final seeds = [suffix.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$suffix", personal_position]');
      }
    } catch (_) {}

    try {
      final seeds = [pp1.bytes, suffix.codeUnits, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [personal_position, "$suffix", navMint]');
      }
    } catch (_) {}
  }

  // Try with marketGroup
  print('\n=== Testing with marketGroup ===\n');
  final mgPrefixes = ['shares', 'user_shares', 'stake', 'staked', 'deposit', 'position_shares'];
  for (final prefix in mgPrefixes) {
    try {
      final seeds = [prefix.codeUnits, marketGroup.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketGroup, user]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, user1.bytes, marketGroup.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", user, marketGroup]');
      }
    } catch (_) {}
  }

  // Maybe it's just [personal_position] with no additional seeds
  print('\n=== Testing single-seed patterns ===\n');
  try {
    final seeds = [pp1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('Seeds [personal_position]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH!');
    }
  } catch (_) {}

  // Or uses navMint as the primary seed
  try {
    final seeds = [navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('Seeds [navMint]: ${pda.toBase58()}');
  } catch (_) {}

  // Try token-related strings
  print('\n=== Testing token-related patterns ===\n');
  final tokenPrefixes = ['token_account', 'mint_account', 'nav_account', 'user_token', 'user_mint'];
  for (final prefix in tokenPrefixes) {
    try {
      final seeds = [prefix.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", navMint, user]');
      }
    } catch (_) {}
  }

  // What if it's an ATA with a PDA owner?
  print('\n=== Testing PDA-owned ATA patterns ===\n');
  // Try using marketMetadata as owner
  try {
    final seeds = [marketMetadata.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    print('marketMetadata navMint ATA: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH!');
    }
  } catch (_) {}

  // Try using marketGroup as owner
  try {
    final seeds = [marketGroup.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: ataProgram);
    print('marketGroup navMint ATA: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH!');
    }
  } catch (_) {}

  // user_shares is a token account owned by personal_position
  // But it's NOT a standard ATA - it's a PDA created by Mayflower
  print('\n=== Testing Mayflower-derived token account patterns ===\n');

  // Try variations with Mayflower as the deriving program
  final tokenSeeds = [
    ['user_nav_shares', pp1.bytes, navMint.bytes],
    ['nav_shares', pp1.bytes, navMint.bytes],
    ['user_shares', pp1.bytes, navMint.bytes],
    ['shares', pp1.bytes, navMint.bytes],
    [pp1.bytes, navMint.bytes, 'shares'.codeUnits],
    [pp1.bytes, 'nav'.codeUnits],
    [navMint.bytes, pp1.bytes],
    [pp1.bytes, navMint.bytes],
    ['token_account'.codeUnits, pp1.bytes, navMint.bytes],
    ['nav_account'.codeUnits, pp1.bytes],
    // Maybe it's [personal_position, mint] pattern
    [pp1.bytes, navMint.bytes],
    // Or mint first
    [navMint.bytes, pp1.bytes],
    // With "user" prefix
    ['user'.codeUnits, pp1.bytes, navMint.bytes],
    // With position-related strings
    ['position_nav'.codeUnits, marketMetadata.bytes, user1.bytes],
    ['nav_position'.codeUnits, marketMetadata.bytes, user1.bytes],
    ['user_nav_position'.codeUnits, marketMetadata.bytes, user1.bytes],
  ];

  for (final seedList in tokenSeeds) {
    try {
      final seeds = seedList.map((s) {
        if (s is String) return s.codeUnits;
        if (s is List<int>) return s;
        return s;
      }).toList();

      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seeds.cast<List<int>>(),
        programId: mayflowerProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: $seedList');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (e) {
      // Skip errors
    }
  }

  // Try single string prefixes with [prefix, personal_position, navMint]
  final sharePrefixes = [
    'user_nav_shares', 'nav_shares', 'user_shares', 'shares',
    'staked', 'deposited', 'balance', 'token', 'nav_token',
    'position_token', 'user_nav', 'personal_nav', 'nav_balance',
  ];

  for (final prefix in sharePrefixes) {
    try {
      final seeds = [prefix.codeUnits, pp1.bytes, navMint.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", personal_position, navMint]');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (_) {}

    // Try without navMint
    try {
      final seeds = [prefix.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", personal_position]');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (_) {}
  }

  // Try the ATA-style seeds but with Mayflower program
  print('\n=== Testing ATA-style seeds with Mayflower program ===\n');
  try {
    final seeds = [pp1.bytes, tokenProgram.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('ATA-style with Mayflower: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) {
      print('✅ MATCH!');
    }
  } catch (_) {}

  // Try the exact pattern we found for personal_position but with navMint
  print('\n=== Testing personal_position pattern variants ===\n');
  final ppVariantPrefixes = [
    'user_nav_shares', 'nav_shares', 'staked_nav', 'deposited_nav',
    'personal_nav', 'position_nav', 'nav_deposit', 'nav_stake'
  ];
  for (final prefix in ppVariantPrefixes) {
    try {
      // Same as personal_position but different prefix
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketMetadata, user]');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (_) {}

    // Try with navMint instead of marketMetadata
    try {
      final seeds = [prefix.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", navMint, user]');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (_) {}

    // Try with both marketMetadata AND navMint
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketMetadata, navMint, user]');
        print('   Result: ${pda.toBase58()}');
      }
    } catch (_) {}
  }

  // Try authority-based patterns
  print('\n=== Testing authority-based patterns ===\n');
  final authPrefixes = ['user_shares', 'shares', 'nav_shares', 'staked', 'token'];
  for (final prefix in authPrefixes) {
    try {
      final seeds = [prefix.codeUnits, authority.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", authority, user]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, user1.bytes, authority.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", user, authority]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, authority.bytes, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", authority, navMint, user]');
      }
    } catch (_) {}
  }

  // Try personal_position-based derivation with navMint
  print('\n=== Testing position + navMint patterns ===\n');
  try {
    // Just [position, mint]
    final seeds1 = [pp1.bytes, navMint.bytes];
    final pda1 = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds1, programId: mayflowerProgram);
    print('[pp, navMint]: ${pda1.toBase58()}');
    if (pda1.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  try {
    // [mint, position]
    final seeds2 = [navMint.bytes, pp1.bytes];
    final pda2 = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds2, programId: mayflowerProgram);
    print('[navMint, pp]: ${pda2.toBase58()}');
    if (pda2.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  // The user_shares might be derived from personal_position somehow
  // Try the same seeds that created personal_position but with navMint added
  try {
    final seeds = ['personal_position'.codeUnits, marketMetadata.bytes, user1.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('["personal_position", marketMetadata, user, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  // Try with just [marketMetadata, user, navMint]
  try {
    final seeds = [marketMetadata.bytes, user1.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('[marketMetadata, user, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  // What if it's just using a simple incrementing pattern or personal_position bytes directly?
  print('\n=== Testing direct position-derived patterns ===\n');
  for (int i = 0; i < 10; i++) {
    try {
      final seeds = [pp1.bytes, [i]];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [personal_position, [$i]]');
      }
    } catch (_) {}

    try {
      final seeds = [[i], pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: [[$i], personal_position]');
      }
    } catch (_) {}
  }

  // Samsara program might be involved
  print('\n=== Testing Samsara program derivation ===\n');
  final samsaraSeeds = [
    ['user_shares'.codeUnits, pp1.bytes],
    ['shares'.codeUnits, pp1.bytes],
    [pp1.bytes, navMint.bytes],
    ['user_shares'.codeUnits, marketMetadata.bytes, user1.bytes],
    ['nav_shares'.codeUnits, marketMetadata.bytes, user1.bytes],
    ['staked'.codeUnits, marketMetadata.bytes, user1.bytes],
  ];
  for (final seedList in samsaraSeeds) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seedList.cast<List<int>>(),
        programId: samsaraProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH with Samsara! Seeds: $seedList');
      }
    } catch (_) {}
  }

  // The account could be created with init but derived differently
  // Let's print out what we'd get with common anchor patterns
  print('\n=== Printing common Anchor seed patterns ===\n');
  final anchorPatterns = <MapEntry<List<List<int>>, String>>[
    MapEntry(['user_shares'.codeUnits, marketMetadata.bytes, user1.bytes], 'user_shares + metadata + user'),
    MapEntry(['user_nav_shares'.codeUnits, marketMetadata.bytes, user1.bytes], 'user_nav_shares + metadata + user'),
    MapEntry(['user_token'.codeUnits, marketMetadata.bytes, user1.bytes], 'user_token + metadata + user'),
    MapEntry(['staked'.codeUnits, marketMetadata.bytes, user1.bytes], 'staked + metadata + user'),
    MapEntry(['nav_staked'.codeUnits, marketMetadata.bytes, user1.bytes], 'nav_staked + metadata + user'),
    MapEntry(['user_nav'.codeUnits, marketMetadata.bytes, user1.bytes], 'user_nav + metadata + user'),
    MapEntry(['token_account'.codeUnits, marketMetadata.bytes, user1.bytes], 'token_account + metadata + user'),
    MapEntry(['nav'.codeUnits, marketMetadata.bytes, user1.bytes], 'nav + metadata + user'),
  ];
  for (final pattern in anchorPatterns) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: pattern.key,
        programId: mayflowerProgram,
      );
      print('${pattern.value}: ${pda.toBase58()}');
      if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
    } catch (e) {
      print('${pattern.value}: ERROR');
    }
  }

  // Try camelCase and other naming conventions
  print('\n=== Testing camelCase and other naming conventions ===\n');
  final camelPrefixes = [
    'userShares', 'navShares', 'userNavShares', 'positionShares',
    'stakedShares', 'depositedShares', 'userDeposit', 'userStake',
    'personalShares', 'userNav', 'navBalance', 'userBalance',
    'tokenAccount', 'navAccount', 'userToken', 'navToken',
  ];
  for (final prefix in camelPrefixes) {
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketMetadata, user]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", navMint, user]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", personal_position]');
      }
    } catch (_) {}
  }

  // Let's also try with the personal_position seed text + navMint
  print('\n=== Testing with personal_position text + navMint ===\n');
  try {
    final seeds = ['personal_position'.codeUnits, marketMetadata.bytes, navMint.bytes, user1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('["personal_position", metadata, navMint, user]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  try {
    final seeds = ['personal_position'.codeUnits, navMint.bytes, marketMetadata.bytes, user1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('["personal_position", navMint, metadata, user]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  // Try with "token" suffix to personal_position
  print('\n=== Testing personal_position_token patterns ===\n');
  final ppTokenPrefixes = [
    'personal_position_token', 'personal_position_nav', 'personal_position_shares',
    'position_token', 'position_nav', 'position_shares',
  ];
  for (final prefix in ppTokenPrefixes) {
    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Seeds: ["$prefix", marketMetadata, user]');
      }
    } catch (_) {}
  }

  // Maybe the user_shares uses the authority as the owner for derivation
  print('\n=== Testing authority-owned token patterns ===\n');
  try {
    final seeds = [authority.bytes, navMint.bytes, user1.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('[authority, navMint, user]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  try {
    final seeds = [user1.bytes, authority.bytes, navMint.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    print('[user, authority, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('✅ MATCH!');
  } catch (_) {}

  // Systematic brute force with all combinations
  print('\n=== Systematic brute force ===\n');

  // All the key accounts
  final keyAccounts = {
    'user': user1,
    'marketMetadata': marketMetadata,
    'mayflowerMarket': mayflowerMarket,
    'navMint': navMint,
    'marketGroup': marketGroup,
    'authority': authority,
    'pp': pp1,
  };

  // Common prefixes for token/shares accounts
  final allPrefixes = [
    'user_shares', 'shares', 'nav_shares', 'staked', 'stake',
    'deposit', 'deposited', 'token', 'nav', 'balance', 'account',
    'user_nav', 'user_token', 'user_stake', 'user_deposit',
    'position', 'nav_position', 'token_account',
  ];

  // Try [prefix, X, Y] for all combinations
  for (final prefix in allPrefixes) {
    for (final x in keyAccounts.entries) {
      for (final y in keyAccounts.entries) {
        if (x.key == y.key) continue;
        try {
          final seeds = [prefix.codeUnits, x.value.bytes, y.value.bytes];
          final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
          if (pda.toBase58() == expectedShares1) {
            print('✅ MATCH! Mayflower: ["$prefix", ${x.key}, ${y.key}]');
          }
        } catch (_) {}

        try {
          final seeds = [prefix.codeUnits, x.value.bytes, y.value.bytes];
          final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: samsaraProgram);
          if (pda.toBase58() == expectedShares1) {
            print('✅ MATCH! Samsara: ["$prefix", ${x.key}, ${y.key}]');
          }
        } catch (_) {}
      }
    }
  }

  // Try [X, Y] without prefix
  for (final x in keyAccounts.entries) {
    for (final y in keyAccounts.entries) {
      if (x.key == y.key) continue;
      try {
        final seeds = [x.value.bytes, y.value.bytes];
        final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
        if (pda.toBase58() == expectedShares1) {
          print('✅ MATCH! Mayflower no prefix: [${x.key}, ${y.key}]');
        }
      } catch (_) {}
    }
  }

  // Try [prefix, X, Y, Z] for key combinations
  final tripleSeeds = [
    ['user_shares', 'marketMetadata', 'navMint', 'user'],
    ['user_shares', 'navMint', 'marketMetadata', 'user'],
    ['shares', 'marketMetadata', 'navMint', 'user'],
    ['nav_shares', 'marketMetadata', 'navMint', 'user'],
    ['token', 'marketMetadata', 'navMint', 'user'],
    ['nav', 'marketMetadata', 'navMint', 'user'],
    ['staked', 'marketMetadata', 'navMint', 'user'],
    ['user_shares', 'pp', 'navMint', 'user'],
  ];

  for (final combo in tripleSeeds) {
    try {
      final seeds = [
        combo[0].codeUnits,
        keyAccounts[combo[1]]!.bytes,
        keyAccounts[combo[2]]!.bytes,
        keyAccounts[combo[3]]!.bytes,
      ];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Mayflower: ["${combo[0]}", ${combo[1]}, ${combo[2]}, ${combo[3]}]');
      }
    } catch (_) {}
  }

  // Try with "user_nav_shares" (common Anchor pattern)
  print('\n=== Testing specific Anchor patterns ===\n');
  // The exact seed bytes for user_nav_shares in Rust would be b"user_nav_shares"
  final specificSeeds = [
    'user_nav_shares',
    'nav_shares',
    'user_shares',
    'shares',
    'staked_nav',
    'deposited_nav',
    'nav_staked',
    'nav_deposited',
    'user_staked_nav',
    'position_nav',
    'position_shares',
    'personal_nav',
    'personal_shares',
  ];

  for (final seedStr in specificSeeds) {
    // Pattern: [seed, metadata, user]
    try {
      final seeds = [seedStr.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$seedStr", marketMetadata, user]');
      }
    } catch (_) {}

    // Pattern: [seed, user, metadata]
    try {
      final seeds = [seedStr.codeUnits, user1.bytes, marketMetadata.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$seedStr", user, marketMetadata]');
      }
    } catch (_) {}

    // Pattern: [seed, mint, user]
    try {
      final seeds = [seedStr.codeUnits, navMint.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$seedStr", navMint, user]');
      }
    } catch (_) {}

    // Pattern: [seed, personal_position]
    try {
      final seeds = [seedStr.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$seedStr", personal_position]');
      }
    } catch (_) {}
  }

  // Try variations using Samsara market as well
  final samsaraMarket = Ed25519HDPublicKey.fromBase58('4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc');

  print('\n=== Testing with Samsara market ===\n');
  for (final seedStr in ['user_shares', 'shares', 'nav_shares', 'staked']) {
    try {
      final seeds = [seedStr.codeUnits, samsaraMarket.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Mayflower: ["$seedStr", samsaraMarket, user]');
      }
    } catch (_) {}

    try {
      final seeds = [seedStr.codeUnits, samsaraMarket.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: samsaraProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Samsara: ["$seedStr", samsaraMarket, user]');
      }
    } catch (_) {}
  }

  // Given that we couldn't find it, let's consider the possibility that
  // the user_shares address might need to be looked up from the personal_position account data
  // or derived using some other method
  print('\n=== Alternative: Check if user_shares is stored in personal_position ===');
  print('The user_shares address might be stored in the personal_position account data');
  print('rather than being independently derivable.');

  // We know user_shares is stored in personal_position at bytes 72-103
  // But for init, we need to derive it first. Try more patterns.
  print('\n=== Final attempt: position-based derivation ===\n');

  // Try patterns that derive user_shares from personal_position seed
  final positionPatterns = [
    // [prefix, position]
    ['user_shares'.codeUnits, pp1.bytes],
    ['shares'.codeUnits, pp1.bytes],
    ['token'.codeUnits, pp1.bytes],
    ['nav'.codeUnits, pp1.bytes],
    ['nav_token'.codeUnits, pp1.bytes],
    // [position, suffix]
    [pp1.bytes, 'shares'.codeUnits],
    [pp1.bytes, 'token'.codeUnits],
    [pp1.bytes, 'nav'.codeUnits],
    // [position, mint]
    [pp1.bytes, navMint.bytes],
    [navMint.bytes, pp1.bytes],
    // Just position
    [pp1.bytes],
    // [mint, position]
    [navMint.bytes, pp1.bytes],
    // [mint, user]
    [navMint.bytes, user1.bytes],
    [user1.bytes, navMint.bytes],
    // [metadata, mint, user]
    [marketMetadata.bytes, navMint.bytes, user1.bytes],
    [navMint.bytes, marketMetadata.bytes, user1.bytes],
  ];

  for (final seeds in positionPatterns) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seeds.cast<List<int>>(),
        programId: mayflowerProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Mayflower: ${_describeSeed(seeds)}');
      }
    } catch (_) {}

    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seeds.cast<List<int>>(),
        programId: samsaraProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! Samsara: ${_describeSeed(seeds)}');
      }
    } catch (_) {}
  }

  // Try with "user_nav_shares" and similar with position
  final lastChance = [
    'user_nav_shares', 'user_staked', 'staked_position', 'position_token',
    'nav_position', 'user_nav_position', 'position_nav', 'nav_staked',
  ];
  for (final prefix in lastChance) {
    try {
      final seeds = [prefix.codeUnits, pp1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$prefix", personal_position]');
      }
    } catch (_) {}

    try {
      final seeds = [prefix.codeUnits, marketMetadata.bytes, user1.bytes];
      final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! ["$prefix", marketMetadata, user]');
      }
    } catch (_) {}
  }

  // Print what we actually need to find
  // Let's try deriving user_shares using personal_position address + various seeds
  print('\n=== Using computed personal_position address ===\n');

  // First compute personal_position the right way
  final ppSeeds = ['personal_position'.codeUnits, marketMetadata.bytes, user1.bytes];
  final computedPp = await Ed25519HDPublicKey.findProgramAddress(seeds: ppSeeds, programId: mayflowerProgram);
  print('Computed personal_position: ${computedPp.toBase58()}');

  // Now try using the computed address
  final ppBasedSeeds = [
    [computedPp.bytes],
    [computedPp.bytes, navMint.bytes],
    [navMint.bytes, computedPp.bytes],
    ['token'.codeUnits, computedPp.bytes],
    ['shares'.codeUnits, computedPp.bytes],
    ['nav'.codeUnits, computedPp.bytes],
    [computedPp.bytes, 'token'.codeUnits],
    [computedPp.bytes, 'nav'.codeUnits],
    [computedPp.bytes, tokenProgram.bytes, navMint.bytes], // ATA-style
    [computedPp.bytes, 'nav_shares'.codeUnits],
    ['user_shares'.codeUnits, computedPp.bytes],
    ['user_nav_shares'.codeUnits, computedPp.bytes],
  ];

  for (final seeds in ppBasedSeeds) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: seeds.cast<List<int>>(),
        programId: mayflowerProgram,
      );
      print('  ${_describeSeed(seeds)} => ${pda.toBase58()}');
      if (pda.toBase58() == expectedShares1) {
        print('  ✅ MATCH!');
      }
    } catch (_) {}
  }

  // One more thing - try ATA with the computed PP address
  try {
    final ataSeeds = [computedPp.bytes, tokenProgram.bytes, navMint.bytes];
    final ataPda = await Ed25519HDPublicKey.findProgramAddress(seeds: ataSeeds, programId: ataProgram);
    print('\nATA(computed_pp, navMint): ${ataPda.toBase58()}');
    if (ataPda.toBase58() == expectedShares1) {
      print('  ✅ MATCH! user_shares IS a standard ATA of personal_position!');
    }
  } catch (e) {
    print('ATA error: $e');
  }

  // Try just [personal_position] as the only seed
  print('\n=== Testing single-seed patterns with computed PP ===\n');
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [computedPp.bytes],
      programId: mayflowerProgram,
    );
    print('[computed_pp]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (e) {
    print('Error: $e');
  }

  // Try with "b" prefix (common in Rust)
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [[0x62], computedPp.bytes], // 'b' = 0x62
      programId: mayflowerProgram,
    );
    print('["b", computed_pp]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  // Maybe it's user_shares derived from same seeds as personal_position
  // but the token account is created with a different authority
  print('\n=== Testing user_shares parallel to personal_position ===\n');
  final parallelPrefixes = ['user_shares', 'user_nav_shares', 'shares', 'nav_shares', 'token'];
  for (final prefix in parallelPrefixes) {
    try {
      // Same seeds as personal_position but different prefix
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [prefix.codeUnits, marketMetadata.bytes, user1.bytes],
        programId: mayflowerProgram,
      );
      print('["$prefix", marketMetadata, user]: ${pda.toBase58()}');
      if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
    } catch (_) {}
  }

  // What if it uses the mint first?
  print('\n=== Testing mint-first patterns ===\n');
  for (final prefix in ['shares', 'user_shares', 'nav_shares', 'staked']) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [prefix.codeUnits, navMint.bytes, marketMetadata.bytes, user1.bytes],
        programId: mayflowerProgram,
      );
      print('["$prefix", navMint, marketMetadata, user]: ${pda.toBase58()}');
      if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
    } catch (_) {}
  }

  // Try with token program as a seed element
  print('\n=== Testing with TOKEN_PROGRAM as seed ===\n');
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [computedPp.bytes, tokenProgram.bytes, navMint.bytes],
      programId: mayflowerProgram,
    );
    print('[pp, TOKEN_PROGRAM, navMint] with Mayflower: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  // Try with ATA program as seed element
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [computedPp.bytes, ataProgram.bytes, navMint.bytes],
      programId: mayflowerProgram,
    );
    print('[pp, ATA_PROGRAM, navMint] with Mayflower: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  // What if it uses authority + user?
  print('\n=== Testing authority-based patterns ===\n');
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [authority.bytes, user1.bytes, navMint.bytes],
      programId: mayflowerProgram,
    );
    print('[authority, user, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [user1.bytes, authority.bytes, navMint.bytes],
      programId: mayflowerProgram,
    );
    print('[user, authority, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  // What if user_shares uses the same seeds as personal_position but with navMint appended?
  print('\n=== Testing personal_position seeds + navMint ===\n');
  try {
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: ['personal_position'.codeUnits, marketMetadata.bytes, user1.bytes, navMint.bytes],
      programId: mayflowerProgram,
    );
    print('["personal_position", metadata, user, navMint]: ${pda.toBase58()}');
    if (pda.toBase58() == expectedShares1) print('  ✅ MATCH!');
  } catch (_) {}

  // What if it's a simple index or counter?
  print('\n=== Testing with index/counter seeds ===\n');
  for (int i = 0; i < 256; i++) {
    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [computedPp.bytes, [i]],
        programId: mayflowerProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! [computed_pp, [$i]]');
        break;
      }
    } catch (_) {}

    try {
      final pda = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [[i], computedPp.bytes],
        programId: mayflowerProgram,
      );
      if (pda.toBase58() == expectedShares1) {
        print('✅ MATCH! [[$i], computed_pp]');
        break;
      }
    } catch (_) {}
  }

  print('\n=== Summary ===');
  print('Expected user_shares: $expectedShares1');
  print('This is a token account owned by personal_position ($expectedPosition1)');
  print('Holding navMint tokens');
  print('\n*** user_shares is stored at bytes 72-103 in personal_position account ***');
  print('For init, we may need to read from existing accounts or use a different approach.');

  // Verify user2 with same seeds to confirm pattern
  print('\n=== Verifying with User 2 ===\n');

  // Test personal_position for user2 with found seeds
  try {
    final seeds = ['personal_position'.codeUnits, marketMetadata.bytes, user2.bytes];
    final pda = await Ed25519HDPublicKey.findProgramAddress(seeds: seeds, programId: mayflowerProgram);
    if (pda.toBase58() == expectedPosition2) {
      print('✅ User2 personal_position VERIFIED with: ["personal_position", marketMetadata, user]');
      print('   Expected: $expectedPosition2');
      print('   Got: ${pda.toBase58()}\n');
    } else {
      print('❌ User2 personal_position mismatch:');
      print('   Expected: $expectedPosition2');
      print('   Got: ${pda.toBase58()}\n');
    }
  } catch (e) {
    print('Error testing user2 position: $e');
  }

  print('\nDone testing. If no matches, seeds use different format or program.');
}

String _describeSeed(List<dynamic> seeds) {
  return seeds.map((s) {
    if (s is List<int>) {
      // Try to decode as string
      try {
        final str = String.fromCharCodes(s);
        if (str.length < 32 && str.codeUnits.every((c) => c >= 32 && c < 127)) {
          return '"$str"';
        }
      } catch (_) {}
      // Otherwise show first few bytes
      if (s.length == 32) return 'pubkey[${s.sublist(0, 4).map((b) => b.toRadixString(16)).join('')}...]';
      return 'bytes[${s.length}]';
    }
    return s.toString();
  }).toList().toString();
}
