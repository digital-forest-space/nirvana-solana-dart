# Nirvana Solana

A Dart client library for interacting with the Nirvana V2 protocol on Solana blockchain.

## Features

- Fetch live ANA token prices from on-chain data
- Buy and sell ANA tokens
- Stake and unstake ANA tokens
- Borrow against staked ANA
- Manage personal accounts
- Full transaction building support

## Getting Started

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  nirvana_solana: ^0.1.0
```

### Usage

```dart
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

void main() async {
  // Create a Solana RPC client
  final rpcClient = SolanaClient(
    rpcUrl: Uri.parse('https://api.mainnet-beta.solana.com'),
    websocketUrl: Uri.parse('wss://api.mainnet-beta.solana.com'),
  );
  
  // Create Nirvana client
  final nirvanaClient = NirvanaClient(
    rpcClient: rpcClient,
    config: NirvanaConfig.mainnet(), // or provide custom config
  );
  
  // Fetch current prices
  final prices = await nirvanaClient.fetchPrices();
  print('ANA Market Price: \$${prices.anaMarket}');
  print('ANA Floor Price: \$${prices.anaFloor}');
  print('prANA Price: \$${prices.prana}');
  
  // Get user balances
  final balances = await nirvanaClient.getUserBalances('YourPublicKey');
  print('ANA Balance: ${balances['ANA']}');
  
  // Buy ANA with USDC
  final keypair = await Ed25519HDKeyPair.fromSeedWithHdPath(
    seed: yourSeed,
    hdPath: "m/44'/501'/0'/0'",
  );
  
  final buyResult = await nirvanaClient.buyAna(
    BuyAnaRequest(
      userPubkey: keypair.publicKey.toBase58(),
      keypair: keypair,
      amount: 100.0, // 100 USDC
      useNirv: false, // use USDC
      minAnaAmount: 95.0, // slippage protection
    ),
  );
  
  if (buyResult.success) {
    print('Transaction successful: ${buyResult.signature}');
  }
}
```

## API Reference

### NirvanaClient

The main entry point for interacting with the Nirvana protocol.

#### Methods

- `fetchPrices()` - Get current ANA token prices
- `getPersonalAccountInfo(userPubkey)` - Get user's staking account info
- `getUserBalances(userPubkey)` - Get user's token balances
- `buyAna(request)` - Buy ANA tokens
- `sellAna(request)` - Sell ANA tokens
- `stakeAna(request)` - Stake ANA tokens
- `unstakeAna(request)` - Unstake ANA tokens
- `borrowNirv(request)` - Borrow NIRV against staked ANA
- `repayNirv(request)` - Repay NIRV debt

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.