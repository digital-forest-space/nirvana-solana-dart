/// Configuration for Samsara protocol (navTokens derivatives)
class SamsaraConfig {
  // Program IDs
  final String samsaraProgramId;
  final String mayflowerProgramId;

  // Tenants
  final String mayflowerTenant;
  final String samsaraTenant;

  // System programs
  final String tokenProgram;
  final String associatedTokenProgram;
  final String systemProgram;
  final String computeBudgetProgram;

  const SamsaraConfig({
    required this.samsaraProgramId,
    required this.mayflowerProgramId,
    required this.mayflowerTenant,
    required this.samsaraTenant,
    required this.tokenProgram,
    required this.associatedTokenProgram,
    required this.systemProgram,
    required this.computeBudgetProgram,
  });

  factory SamsaraConfig.mainnet() {
    return const SamsaraConfig(
      samsaraProgramId: 'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7',
      mayflowerProgramId: 'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v',
      mayflowerTenant: '81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z',
      samsaraTenant: 'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC',
      tokenProgram: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
      associatedTokenProgram: 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL',
      systemProgram: '11111111111111111111111111111111',
      computeBudgetProgram: 'ComputeBudget111111111111111111111111111111',
    );
  }
}

/// Configuration for a specific navToken market
class NavTokenMarket {
  final String name;
  final String baseName; // e.g., 'SOL', 'cbBTC'
  final String baseMint; // e.g., Native SOL
  final String navMint; // e.g., navSOL
  final String samsaraMarket;
  final String mayflowerMarket;
  final String marketMetadata;
  final String marketGroup;
  final String lookupTable;
  final String marketSolVault;
  final String marketNavVault;
  final String feeVault;
  final String authorityPda;
  final int baseDecimals;
  final int navDecimals;

  const NavTokenMarket({
    required this.name,
    required this.baseName,
    required this.baseMint,
    required this.navMint,
    required this.samsaraMarket,
    required this.mayflowerMarket,
    required this.marketMetadata,
    required this.marketGroup,
    required this.lookupTable,
    required this.marketSolVault,
    required this.marketNavVault,
    required this.feeVault,
    required this.authorityPda,
    required this.baseDecimals,
    required this.navDecimals,
  });

  /// navSOL market configuration (SOL → navSOL)
  factory NavTokenMarket.navSol() {
    return const NavTokenMarket(
      name: 'navSOL',
      baseName: 'SOL',
      baseMint: 'So11111111111111111111111111111111111111112', // Native SOL (wSOL)
      navMint: 'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo',
      samsaraMarket: '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc',
      mayflowerMarket: 'A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc',
      marketMetadata: 'DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj',
      marketGroup: 'Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC',
      lookupTable: 'HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd',
      marketSolVault: '43vPhZeow3pgYa6zrPXASVQhdXTMfowyfNK87BYizhnL',
      marketNavVault: 'BCYzijbWwmqRnsTWjGhHbneST2emQY36WcRAkbkhsQMt',
      feeVault: 'B8jccpiKZjapgfw1ay6EH3pPnxqTmimsm2KsTZ9LSmjf',
      authorityPda: 'EKVkmuwDKRKHw85NPTbKSKuS75EY4NLcxe1qzSPixLdy',
      baseDecimals: 9, // SOL has 9 decimals
      navDecimals: 9, // navSOL has 9 decimals
    );
  }

  /// navZEC market configuration (ZEC → navZEC)
  factory NavTokenMarket.navZec() {
    return const NavTokenMarket(
      name: 'navZEC',
      baseName: 'ZEC',
      baseMint: 'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS',
      navMint: 'navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe',
      samsaraMarket: '9JiASAyMBL9riFDPJtWCEtK4E2rr2Yfpqxoynxa3XemE',
      mayflowerMarket: '9SBSQvx5B8tKRgtYa3tyXeyvL3JMAZiA2JVXWzDnFKig',
      marketMetadata: 'HcGpdC8EtNpZPComvRaXDQtGHLpCFXMqfzRYeRSPCT5L',
      marketGroup: 'BfGgpGGyMFfZDYyXqjyPU4YG6Py5kkD93mUGXT7TxGnf',
      lookupTable: '', // TODO: Discover from interception
      marketSolVault: 'GreFb71nqhudTo5iYBUa8Czgb9ACCUuTDYpm98XdLUwk',
      marketNavVault: 'CfE1xoGPJSmppr9N7ysTGq3tca5Xc22RbsbZycir1tVq',
      feeVault: 'GPpY9M9XraDsbGBpTqtnoQJugktgMDBjGM6UxdQoD3UM',
      authorityPda: '', // TODO: Discover from interception
      baseDecimals: 8, // ZEC typically has 8 decimals
      navDecimals: 8, // Assumed same as base
    );
  }

  /// navCBBTC market configuration (cbBTC → navCBBTC)
  factory NavTokenMarket.navCbBtc() {
    return const NavTokenMarket(
      name: 'navCBBTC',
      baseName: 'cbBTC',
      baseMint: 'cbbtcf3aa214zXHbiAZQwf4122FBYbraNdFqgw4iMij',
      navMint: 'navB4nQ2ENP18CCo1Jqw9bbLncLBC389Rf3XRCQ6zau',
      samsaraMarket: '', // TODO: Discover from interception
      mayflowerMarket: '3WNH5EArcmVDJzi4KtaX75WiSY65mqT735GEEvqnFJ6B',
      marketMetadata: 'rQL153FrAAcepv1exoemsf9WEsC2uJaajBaaWCykvnK',
      marketGroup: 'AXJJT2A7pUAzFKaRWzGgSN9fr9sEvKdGiqbJjdyYQbqj',
      lookupTable: '', // TODO: Discover from interception
      marketSolVault: 'DH1tmXZ2sDe24o4JA6KPELt8G9nk8PfZHP6zfvAxZivM',
      marketNavVault: '2kfQBRonDGXQfo1WkohTbTq55k6RcuYsfEDzXBozvR5X',
      feeVault: 'JCbzDUCn5aLiE6rvvvy5hZoYv3cJzkYFmr35A4SZxzyW',
      authorityPda: '', // TODO: Discover from interception
      baseDecimals: 8, // cbBTC has 8 decimals
      navDecimals: 8, // Assumed same as base
    );
  }
}
