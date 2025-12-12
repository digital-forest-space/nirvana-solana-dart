# Nirvana Solana

A Dart client library for interacting with the Nirvana V2 protocol on Solana blockchain.

## Supported Operations

| Operation | Description | Script |
|-----------|-------------|--------|
| **Get Prices** | Fetch current ANA floor, market, and prANA prices | [get_prices.dart](scripts/get_prices.dart) |
| **Buy ANA** | Purchase ANA tokens with USDC or NIRV | [buy_ana.dart](scripts/buy_ana.dart) |
| **Sell ANA** | Sell ANA tokens for USDC or NIRV | [sell_ana.dart](scripts/sell_ana.dart) |
| **Stake ANA** | Stake ANA tokens to earn prANA rewards | [stake_ana.dart](scripts/stake_ana.dart) |
| **Unstake ANA** | Withdraw staked ANA tokens | [unstake_ana.dart](scripts/unstake_ana.dart) |
| **Borrow NIRV** | Borrow NIRV against staked ANA collateral | [borrow_nirv.dart](scripts/borrow_nirv.dart) |
| **Repay NIRV** | Repay NIRV debt by burning NIRV | [repay_nirv.dart](scripts/repay_nirv.dart) |
| **Realize prANA** | Convert prANA to ANA (pay with USDC or NIRV) | [realize_prana.dart](scripts/realize_prana.dart) |
| **Claim prANA** | Claim accumulated prANA staking rewards | [claim_prana.dart](scripts/claim_prana.dart) |
| **Claim Revenue Share** | Claim accumulated ANA + NIRV revenue share | [claim_revenue_share.dart](scripts/claim_revenue_share.dart) |
| **Parse Transaction** | Parse any Nirvana transaction by signature | [parse_transaction.dart](scripts/parse_transaction.dart) |

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  nirvana_solana:
    git:
      url: https://github.com/yourrepo/nirvana_solana.git
```

## Quick Start

### Using Scripts

All scripts support `--rpc <url>` flag or `SOLANA_RPC_URL` environment variable:

```bash
# Set RPC endpoint
export SOLANA_RPC_URL=https://your-rpc-endpoint.com

# Get current prices
dart scripts/get_prices.dart

# Buy 10 USDC worth of ANA
dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --usdc

# Buy using NIRV instead
dart scripts/buy_ana.dart ~/.config/solana/id.json 10 --nirv

# Sell 1.5 ANA for USDC
dart scripts/sell_ana.dart ~/.config/solana/id.json 1.5 --usdc

# Sell ANA for NIRV
dart scripts/sell_ana.dart ~/.config/solana/id.json 1.5 --nirv

# Stake 2 ANA
dart scripts/stake_ana.dart ~/.config/solana/id.json 2

# Unstake 1 ANA
dart scripts/unstake_ana.dart ~/.config/solana/id.json 1

# Borrow 5 NIRV against staked ANA
dart scripts/borrow_nirv.dart ~/.config/solana/id.json 5

# Repay 3 NIRV debt
dart scripts/repay_nirv.dart ~/.config/solana/id.json 3

# Realize 0.5 prANA to ANA (pay with USDC)
dart scripts/realize_prana.dart ~/.config/solana/id.json 0.5 --usdc

# Realize prANA paying with NIRV
dart scripts/realize_prana.dart ~/.config/solana/id.json 0.5 --nirv

# Claim prANA rewards
dart scripts/claim_prana.dart ~/.config/solana/id.json

# Claim revenue share (ANA + NIRV)
dart scripts/claim_revenue_share.dart ~/.config/solana/id.json

# Parse a transaction
dart scripts/parse_transaction.dart <signature>
```

Add `--verbose` to any script for human-readable output before the JSON result.

### Script Output

All scripts output JSON. Default is a single line for programmatic use:

```json
{"signature":"5abc...","type":"buy","sent":{"amount":10,"currency":"USDC"},"received":{"amount":2.5,"currency":"ANA"},"pricePerAna":4.0,"timestamp":"2025-01-15T10:30:00Z","userAddress":"abc123..."}
```

Multi-token operations (like realize or claim revenue share) output arrays:

```json
{"signature":"...","type":"claimRevenueShare","sent":[],"received":[{"amount":0.123,"currency":"ANA"},{"amount":0.456,"currency":"NIRV"}],...}
```

### Using the Library

```dart
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

void main() async {
  // Create clients
  final solanaClient = SolanaClient(
    rpcUrl: Uri.parse('https://api.mainnet-beta.solana.com'),
    websocketUrl: Uri.parse('wss://api.mainnet-beta.solana.com'),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: Uri.parse('https://api.mainnet-beta.solana.com'));
  final client = NirvanaClient(rpcClient: rpcClient);

  // Fetch floor price
  final floorPrice = await client.fetchFloorPrice();
  print('Floor Price: \$${floorPrice.toStringAsFixed(6)}');

  // Get user balances
  final balances = await client.getUserBalances('YourPublicKey');
  print('ANA: ${balances['ANA']}');
  print('NIRV: ${balances['NIRV']}');
  print('prANA: ${balances['prANA']}');

  // Load keypair and execute transactions
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: yourPrivateKeyBytes,
  );

  // Buy ANA with NIRV
  final buyResult = await client.buyAna(
    userPubkey: keypair.publicKey.toBase58(),
    keypair: keypair,
    paymentAmount: 10.0,
    useNirv: true,
  );

  if (buyResult.success) {
    print('Buy successful: ${buyResult.signature}');

    // Parse the transaction for details
    final tx = await client.parseTransaction(buyResult.signature);
    print('Received: ${tx.received.first.amount} ANA');
    print('Price: \$${tx.pricePerAna}');
  }
}
```

## API Reference

### NirvanaClient Methods

| Method | Description |
|--------|-------------|
| `fetchFloorPrice()` | Get current ANA floor price |
| `fetchPrices()` | Get all prices (floor, market, prANA) |
| `getPersonalAccountInfo(userPubkey)` | Get staking account info |
| `getUserBalances(userPubkey)` | Get token balances |
| `parseTransaction(signature)` | Parse a Nirvana transaction |
| `buyAna(...)` | Buy ANA with USDC or NIRV |
| `sellAna(...)` | Sell ANA for USDC or NIRV |
| `stakeAna(...)` | Stake ANA tokens |
| `unstakeAna(...)` | Unstake ANA tokens |
| `borrowNirv(...)` | Borrow NIRV against staked ANA |
| `repayNirv(...)` | Repay NIRV debt |
| `realizePrana(...)` | Convert prANA to ANA |
| `claimPrana(...)` | Claim prANA rewards |
| `claimRevenueShare(...)` | Claim ANA + NIRV revenue |

### Transaction Types

The `parseTransaction()` method returns a `NirvanaTransaction` with type:

- `buy` - ANA purchase
- `sell` - ANA sale
- `stake` - ANA staking
- `unstake` - ANA withdrawal
- `borrow` - NIRV borrowing
- `repay` - NIRV debt repayment
- `realize` - prANA to ANA conversion
- `claimPrana` - prANA reward claim
- `claimRevenueShare` - Revenue share claim
- `unknown` - Unrecognized transaction

## Token Addresses

| Token | Mint Address |
|-------|--------------|
| ANA | `5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW` |
| NIRV | `3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM` |
| prANA | `CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N` |
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |

## License

MIT License
