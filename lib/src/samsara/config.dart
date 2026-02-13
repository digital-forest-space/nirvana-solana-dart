/// Configuration for Samsara protocol (navTokens derivatives)
class SamsaraConfig {
  // Program IDs
  final String samsaraProgramId;
  final String mayflowerProgramId;

  // Tenants
  final String mayflowerTenant;
  final String samsaraTenant;

  // Mints
  final String pranaMint;

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
    required this.pranaMint,
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
      samsaraTenant: 'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskTC',
      pranaMint: 'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N',
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
      samsaraMarket: 'E9xCJujXkNBmeJ7ds1AcKhAEHuGw6E874S6XTUU5PB4Q',
      mayflowerMarket: '3WNH5EArcmVDJzi4KtaX75WiSY65mqT735GEEvqnFJ6B',
      marketMetadata: 'rQL153FrAAcepv1exoemsf9WEsC2uJaajBaaWCykvnK',
      marketGroup: 'AXJJT2A7pUAzFKaRWzGgSN9fr9sEvKdGiqbJjdyYQbqj',
      marketSolVault: 'DH1tmXZ2sDe24o4JA6KPELt8G9nk8PfZHP6zfvAxZivM',
      marketNavVault: '2kfQBRonDGXQfo1WkohTbTq55k6RcuYsfEDzXBozvR5X',
      feeVault: 'JCbzDUCn5aLiE6rvvvy5hZoYv3cJzkYFmr35A4SZxzyW',
      authorityPda: '', // TODO: Discover from interception
      baseDecimals: 8, // cbBTC has 8 decimals
      navDecimals: 8, // Assumed same as base
    );
  }

  /// navETH market configuration (WETH → navETH)
  factory NavTokenMarket.navEth() {
    return const NavTokenMarket(
      name: 'navETH',
      baseName: 'WETH',
      baseMint: '7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs',
      navMint: 'navEgA7saxpNqKcnJcWbCeCFMhSQtN8hQWQkK4h9scH',
      samsaraMarket: 'HMkKNuq948jBmevDZAm3kG67edF9Hc2YacNHkfeBC4SP',
      mayflowerMarket: '3AwyQgXuhQAFzMaw17V42EW2htwZknr11grEGddvZEUh',
      marketMetadata: 'XAJvRwx5PmCgCYjsKMSoSrL6MZXJtWC6dwgndFvE1uu',
      marketGroup: '72ECyHwnmmRCMrm2BuTKVgLdPSKHhDx5sNGFDYDwN8ym',
      marketSolVault: 'FpENWfyotJxhAFSsowsSERaEbWMrSopHBAgyGamrvg1a',
      marketNavVault: '6GAADZA83t5Uzk6fwZ55zisfGJ7TFPbnWTRxfLYDF6JM',
      feeVault: '8XQi1aojXMgU4FEfvZmtytQjLAzi7Qyx3theFdCwhfhb',
      authorityPda: '', // TODO: Discover from interception
      baseDecimals: 8, // WETH has 8 decimals
      navDecimals: 8, // Assumed same as base
    );
  }

  /// All known navToken markets, keyed by lowercase name.
  static final Map<String, NavTokenMarket> all = {
    'navsol': NavTokenMarket.navSol(),
    'navzec': NavTokenMarket.navZec(),
    'navcbbtc': NavTokenMarket.navCbBtc(),
    'naveth': NavTokenMarket.navEth(),
  };

  /// Looks up a market by name (case-insensitive).
  /// Returns null if not found.
  static NavTokenMarket? byName(String name) => all[name.toLowerCase()];

  /// Returns all available market keys.
  static List<String> get availableMarkets =>
      all.values.map((m) => m.name).toList();

  /// Well-known mint addresses to human-readable names.
  /// Used by [SamsaraClient.discoverMarkets] to assign names to discovered
  /// markets without requiring Metaplex metadata lookups.
  static const wellKnownMints = <String, ({String name, String symbol})>{
    // Base mints
    'So11111111111111111111111111111111111111112': (name: 'Wrapped SOL', symbol: 'SOL'),
    'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS': (name: 'Zcash', symbol: 'ZEC'),
    'cbbtcf3aa214zXHbiAZQwf4122FBYbraNdFqgw4iMij': (name: 'Coinbase Wrapped BTC', symbol: 'cbBTC'),
    '7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs': (name: 'Wrapped Ether', symbol: 'WETH'),
    // Nav mints
    'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo': (name: 'navSOL', symbol: 'navSOL'),
    'navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe': (name: 'navZEC', symbol: 'navZEC'),
    'navB4nQ2ENP18CCo1Jqw9bbLncLBC389Rf3XRCQ6zau': (name: 'navCBBTC', symbol: 'navCBBTC'),
    'navEgA7saxpNqKcnJcWbCeCFMhSQtN8hQWQkK4h9scH': (name: 'navETH', symbol: 'navETH'),
  };
}
