# Nirvana Solana

Dart client library for the Nirvana V2 and Samsara/Mayflower protocols on Solana.

## Installation

```yaml
dependencies:
  nirvana_solana:
    git:
      url: https://github.com/yourrepo/nirvana_solana.git
```

## Quick Start

```bash
export SOLANA_RPC_URL=https://your-rpc-endpoint.com

# Nirvana
dart scripts/nirvana/get_prices.dart
dart scripts/nirvana/get_balances.dart <pubkey>

# Samsara
dart scripts/samsara/fetch_nav_price.dart --market navSOL
dart scripts/samsara/discover_markets.dart --verbose
```

All scripts output JSON. Add `--verbose` for human-readable output.

---

## Nirvana Protocol (ANA/NIRV/prANA)

### NirvanaClient

```dart
import 'package:nirvana_solana/nirvana_solana.dart';

final client = NirvanaClient.fromRpcUrl('https://api.mainnet-beta.solana.com');
```

#### Read Methods (no keypair needed)

| Method | Returns | Description |
|--------|---------|-------------|
| `fetchFloorPrice()` | `Future<double>` | ANA floor price from on-chain PriceCurve2 account |
| `fetchPrices()` | `Future<NirvanaPrices>` | All prices: floor, market, prANA |
| `fetchLatestAnaPrice({afterSignature?, beforeSignature?, pageSize, ...})` | `Future<TransactionPriceResult>` | Latest ANA price from recent buy/sell txns |
| `fetchLatestAnaPriceWithPaging({afterSignature?, maxPages, ...})` | `Future<TransactionPriceResult>` | Same with automatic multi-page scanning |
| `getUserBalances(userPubkey)` | `Future<Map<String, double>>` | Wallet balances: ANA, NIRV, USDC, prANA |
| `getPersonalAccountInfo(userPubkey)` | `Future<PersonalAccountInfo?>` | Staking account: debt, staked ANA, claimable prANA |
| `getBorrowCapacity(userPubkey)` | `Future<Map<String, double>?>` | NIRV borrow capacity: debt, limit, available |
| `getClaimablePrana(userPubkey)` | `Future<double>` | Claimable prANA via transaction simulation |
| `getClaimableRevshare(userPubkey)` | `Future<Map<String, double>>` | Claimable ANA + NIRV revenue share |
| `getClaimableRevshareViaSimulation(userPubkey)` | `Future<Map<String, double>>` | Same via simulation (more accurate) |
| `parseTransaction(signature)` | `Future<NirvanaTransaction>` | Parse any Nirvana tx: type, amounts, price |
| `resolveUserAccounts(userPubkey)` | `Future<NirvanaUserAccounts>` | Resolve all user token account ATAs |
| `derivePersonalAccount(userPubkey)` | `Future<String>` | Derive user's personal account PDA |
| `getLatestBlockhash()` | `Future<String>` | Recent blockhash for tx construction |

#### Transaction Methods (sign-and-send with keypair)

| Method | Description |
|--------|-------------|
| `buyAna({userPubkey, keypair, amount, useNirv, minAnaAmount?})` | Buy ANA with USDC or NIRV |
| `sellAna({userPubkey, keypair, anaAmount, useNirv?, minOutputAmount?})` | Sell ANA for USDC or NIRV |
| `stakeAna({userPubkey, keypair, anaAmount})` | Stake ANA (auto-inits personal account) |
| `unstakeAna({userPubkey, keypair, anaAmount})` | Unstake ANA from staking position |
| `borrowNirv({userPubkey, keypair, nirvAmount})` | Borrow NIRV against staked ANA |
| `repayNirv({userPubkey, keypair, nirvAmount})` | Repay NIRV debt |
| `realizePrana({userPubkey, keypair, pranaAmount, useNirv?})` | Convert prANA to ANA (pay with USDC or NIRV) |
| `claimPrana({userPubkey, keypair})` | Claim accumulated prANA rewards |
| `claimRevenueShare({userPubkey, keypair})` | Claim ANA + NIRV revenue share |

All return `Future<TransactionResult>` with `.success`, `.signature`, `.error`.

#### Unsigned Transaction Builders (for MWA / external signing)

Each `buildUnsigned*Transaction` method returns `Future<Uint8List>` — serialized tx bytes ready for wallet signing.

| Method | Params |
|--------|--------|
| `buildUnsignedBuyAnaTransaction` | `userPubkey, amount, useNirv, minAnaAmount?, userAccounts, recentBlockhash` |
| `buildUnsignedSellAnaTransaction` | `userPubkey, anaAmount, useNirv?, minOutputAmount?, userAccounts, recentBlockhash` |
| `buildUnsignedStakeAnaTransaction` | `userPubkey, anaAmount, userAccounts, recentBlockhash, personalAccount?, needsInit?` |
| `buildUnsignedUnstakeAnaTransaction` | `userPubkey, anaAmount, userAccounts, personalAccount, recentBlockhash` |
| `buildUnsignedBorrowNirvTransaction` | `userPubkey, nirvAmount, userAccounts, personalAccount, recentBlockhash` |
| `buildUnsignedRepayNirvTransaction` | `userPubkey, nirvAmount, userAccounts, personalAccount, recentBlockhash` |
| `buildUnsignedClaimPranaTransaction` | `userPubkey, userAccounts, personalAccount, recentBlockhash` |
| `buildUnsignedClaimRevshareTransaction` | `userPubkey, userAccounts, personalAccount, recentBlockhash` |

### Nirvana Scripts

| Script | Usage |
|--------|-------|
| `scripts/nirvana/get_prices.dart` | `dart scripts/nirvana/get_prices.dart` |
| `scripts/nirvana/get_balances.dart` | `dart scripts/nirvana/get_balances.dart <pubkey>` |
| `scripts/nirvana/buy_ana.dart` | `dart scripts/nirvana/buy_ana.dart <keypair> <amount> --usdc\|--nirv` |
| `scripts/nirvana/sell_ana.dart` | `dart scripts/nirvana/sell_ana.dart <keypair> <amount> --usdc\|--nirv` |
| `scripts/nirvana/stake_ana.dart` | `dart scripts/nirvana/stake_ana.dart <keypair> <amount>` |
| `scripts/nirvana/unstake_ana.dart` | `dart scripts/nirvana/unstake_ana.dart <keypair> <amount>` |
| `scripts/nirvana/borrow_nirv.dart` | `dart scripts/nirvana/borrow_nirv.dart <keypair> <amount>` |
| `scripts/nirvana/repay_nirv.dart` | `dart scripts/nirvana/repay_nirv.dart <keypair> <amount>` |
| `scripts/nirvana/realize_prana.dart` | `dart scripts/nirvana/realize_prana.dart <keypair> <amount> --usdc\|--nirv` |
| `scripts/nirvana/claim_prana.dart` | `dart scripts/nirvana/claim_prana.dart <keypair>` |
| `scripts/nirvana/claim_revenue_share.dart` | `dart scripts/nirvana/claim_revenue_share.dart <keypair>` |
| `scripts/nirvana/parse_transaction.dart` | `dart scripts/nirvana/parse_transaction.dart <signature>` |

### Transaction Types

`parseTransaction()` returns `NirvanaTransaction` with type: `buy`, `sell`, `stake`, `unstake`, `borrow`, `repay`, `realize`, `claimPrana`, `claimRevenueShare`, `unknown`.

---

## Samsara Protocol (navTokens)

navSOL, navZEC, navCBBTC, navETH derivative markets on the Samsara/Mayflower programs.

### SamsaraClient

```dart
import 'package:nirvana_solana/nirvana_solana.dart';

final client = SamsaraClient.fromRpcClient(rpcClient);
```

#### Read Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `discoverMarkets({batchSize?})` | `Future<List<NavTokenMarket>>` | Discover all markets from on-chain data (3 RPC calls) |
| `fetchFloorPrice(market)` | `Future<double>` | Floor price from Mayflower Market account |
| `fetchAllFloorPrices({markets, batchSize?})` | `Future<Map<String, double>>` | Floor prices for multiple markets (1 batched RPC call) |
| `fetchMarketBalances({userPubkey, market, batchSize?})` | `Future<Map<String, double>>` | User balances for one market: navToken, deposited, base, prANA, rewards, debt |
| `fetchAllMarketBalances({userPubkey, markets?, batchSize?})` | `Future<Map<String, Map<String, double>>>` | Balances for all markets (1 batched RPC call) |
| `getClaimableRewardsViaSimulation({userPubkey, market})` | `Future<double>` | Claimable prANA revenue via tx simulation |
| `fetchLatestNavTokenPrice(market, {afterSignature?, ...})` | `Future<TransactionPriceResult>` | Latest navToken price from buy/sell txns |
| `fetchLatestNavTokenPriceWithPaging(market, {afterSignature?, ...})` | `Future<TransactionPriceResult>` | Same with automatic multi-page scanning |

#### Unsigned Transaction Builders

All return `Future<Uint8List>` — serialized tx bytes for external signing.

| Method | Params | Description |
|--------|--------|-------------|
| `buildUnsignedBuyNavSolTransaction` | `userPubkey, market, inputLamports, recentBlockhash, minOutputLamports?, computeUnitLimit?, computeUnitPrice?` | Buy navToken with base token (wraps SOL for native markets) |
| `buildUnsignedSellNavSolTransaction` | `userPubkey, market, inputNavLamports, recentBlockhash, minOutputLamports?, computeUnitLimit?, computeUnitPrice?` | Sell navToken for base token (unwraps SOL for native markets) |
| `buildUnsignedDepositNavTokenTransaction` | `userPubkey, market, depositLamports, recentBlockhash, computeUnitLimit?, computeUnitPrice?` | Deposit navToken into personal position escrow |
| `buildUnsignedWithdrawNavTokenTransaction` | `userPubkey, market, withdrawLamports, recentBlockhash, computeUnitLimit?, computeUnitPrice?` | Withdraw navToken from personal position escrow |
| `buildUnsignedBorrowTransaction` | `userPubkey, market, borrowLamports, recentBlockhash, computeUnitLimit?, computeUnitPrice?` | Borrow base token against deposited navToken |
| `buildUnsignedRepayTransaction` | `userPubkey, market, repayLamports, recentBlockhash, computeUnitLimit?, computeUnitPrice?` | Repay borrowed base token |
| `buildUnsignedDepositPranaTransaction` | `userPubkey, market, pranaAmount, recentBlockhash` | Deposit prANA to market governance account (auto-inits govAccount) |
| `buildUnsignedClaimRewardsTransaction` | `userPubkey, market, recentBlockhash, computeUnitLimit?, computeUnitPrice?` | Claim prANA revenue (paid in base token) |

### Market Configuration

```dart
// Hardcoded known markets
final sol = NavTokenMarket.navSol();
final all = NavTokenMarket.all; // Map<String, NavTokenMarket>
final market = NavTokenMarket.byName('navSOL');

// Dynamic discovery from on-chain data
final discovered = await client.discoverMarkets();
```

`NavTokenMarket` fields: `name`, `baseName`, `baseMint`, `navMint`, `samsaraMarket`, `mayflowerMarket`, `marketMetadata`, `marketGroup`, `marketSolVault`, `marketNavVault`, `feeVault`, `authorityPda`, `baseDecimals`, `navDecimals`.

`NavTokenMarket.wellKnownMints` maps known mint addresses to `(name, symbol)` records for name resolution without Metaplex RPC calls.

### PDA Derivation

```dart
final samsaraPda = SamsaraPda.mainnet();
final mayflowerPda = MayflowerPda.mainnet();

// Samsara PDAs
final govAccount = await samsaraPda.personalGovAccount(market: key, owner: ownerKey);
final pranaEscrow = await samsaraPda.personalGovPranaEscrow(govAccount: govKey);
final cashEscrow = await samsaraPda.marketCashEscrow(market: marketKey);
final logCounter = await samsaraPda.logCounter();
final samsaraMarket = await samsaraPda.market(marketMeta: metaKey);

// Mayflower PDAs
final position = await mayflowerPda.personalPosition(marketMeta: metaKey, owner: ownerKey);
final escrow = await mayflowerPda.personalPositionEscrow(personalPosition: posKey);
final authority = await mayflowerPda.liqVaultMain(marketMeta: metaKey);
final log = await mayflowerPda.logAccount();
```

See [docs/samsara/pda_seeds.md](docs/samsara/pda_seeds.md) for full seed reference.

### Samsara Scripts

| Script | Usage |
|--------|-------|
| `scripts/samsara/fetch_nav_price.dart` | `dart scripts/samsara/fetch_nav_price.dart --market navSOL` |
| `scripts/samsara/discover_markets.dart` | `dart scripts/samsara/discover_markets.dart [--verbose] [--health]` |
| `scripts/samsara/fetch_balance.dart` | `dart scripts/samsara/fetch_balance.dart <pubkey> [--market navSOL]` |
| `scripts/samsara/buy_nav.dart` | `dart scripts/samsara/buy_nav.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/sell_nav.dart` | `dart scripts/samsara/sell_nav.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/deposit_nav.dart` | `dart scripts/samsara/deposit_nav.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/withdraw_nav.dart` | `dart scripts/samsara/withdraw_nav.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/borrow.dart` | `dart scripts/samsara/borrow.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/repay.dart` | `dart scripts/samsara/repay.dart <keypair> <amount> [--market navSOL]` |
| `scripts/samsara/deposit_prana.dart` | `dart scripts/samsara/deposit_prana.dart <keypair> <amount> --market navSOL` |
| `scripts/samsara/claim_rewards.dart` | `dart scripts/samsara/claim_rewards.dart <keypair> --market navSOL` |
| `scripts/samsara/check_pda_seeds.dart` | `dart scripts/samsara/check_pda_seeds.dart --verbose` |

---

## RPC Client

```dart
import 'package:nirvana_solana/nirvana_solana.dart';

final solanaClient = SolanaClient(rpcUrl: uri, websocketUrl: wsUrl);
final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
```

| Method | Returns | Description |
|--------|---------|-------------|
| `getAccountInfo(address)` | `Future<Map<String, dynamic>>` | Raw account data |
| `getMultipleAccounts(addresses, {batchSize?})` | `Future<List<Map?>>` | Batch fetch accounts (auto-chunks to 100) |
| `getProgramAccounts(programId, {dataSize, memcmpOffset?, memcmpBytes?})` | `Future<List<Map>>` | Find program accounts by size/memcmp filter |
| `getTokenBalance(tokenAccount)` | `Future<double>` | SPL token account balance |
| `findTokenAccount(owner, mint)` | `Future<String?>` | Find token account for owner+mint |
| `getAssociatedTokenAddress(owner, mint)` | `Future<String>` | Derive ATA address |
| `getSignaturesForAddress(address, {limit?, until?, before?})` | `Future<List<String>>` | Recent tx signatures |
| `getTransaction(signature)` | `Future<Map<String, dynamic>>` | Full tx data (jsonParsed) |
| `getLatestBlockhash()` | `Future<String>` | Recent blockhash |
| `simulateTransaction(txBase64)` | `Future<Map<String, dynamic>>` | Simulate tx |
| `simulateTransactionWithAccounts(txBase64, accounts)` | `Future<Map<String, dynamic>>` | Simulate tx and return post-state of accounts |
| `sendAndConfirmTransaction({message, signers, commitment?})` | `Future<String>` | Sign, send, confirm |

---

## Token Addresses

| Token | Mint |
|-------|------|
| ANA | `5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW` |
| NIRV | `3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM` |
| prANA | `CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N` |
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |
| navSOL | `navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo` |
| navZEC | `navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe` |
| navCBBTC | `navB4nQ2ENP18CCo1Jqw9bbLncLBC389Rf3XRCQ6zau` |
| navETH | `navEgA7saxpNqKcnJcWbCeCFMhSQtN8hQWQkK4h9scH` |

## License

MIT License
