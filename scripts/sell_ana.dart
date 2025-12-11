import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a sell ANA transaction
///
/// Usage: dart scripts/sell_ana.dart <keypair_path> <ana_amount> [--nirv|--usdc] [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/sell_ana.dart ~/.config/solana/id.json 1.5
///   dart scripts/sell_ana.dart ~/.config/solana/id.json 1.5 --nirv
///   dart scripts/sell_ana.dart ~/.config/solana/id.json 1.5 --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/sell_ana.dart <keypair_path> <ana_amount> [--nirv|--usdc] [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --nirv       Receive NIRV instead of USDC');
    print('  --usdc       Receive USDC (default)');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final anaAmount = double.tryParse(args[1]);

  // Parse flags
  final useNirv = args.any((a) => a.toLowerCase() == '--nirv');
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');
  final receiveCurrency = useNirv ? 'NIRV' : 'USDC';

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (anaAmount == null || anaAmount <= 0) {
    print(jsonEncode({'success': false, 'error': 'Invalid amount: ${args[1]}'}));
    exit(1);
  }

  // Load keypair
  final keypairFile = File(keypairPath);
  if (!keypairFile.existsSync()) {
    print(jsonEncode({'success': false, 'error': 'Keypair file not found: $keypairPath'}));
    exit(1);
  }

  if (verbose) print('Loading keypair from $keypairPath...');
  final keypairJson = keypairFile.readAsStringSync();
  final keypairBytes = (RegExp(r'\d+').allMatches(keypairJson).map((m) => int.parse(m.group(0)!)).toList());
  final keypair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
    privateKey: keypairBytes.sublist(0, 32),
  );
  final userPubkey = keypair.publicKey.toBase58();
  if (verbose) print('Wallet: $userPubkey');

  // Create client
  if (verbose) print('RPC: $rpcUrl');
  final solanaClient = SolanaClient(rpcUrl: Uri.parse(rpcUrl), websocketUrl: Uri.parse(rpcUrl.replaceFirst('https', 'wss')));
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: Uri.parse(rpcUrl));
  final client = NirvanaClient(rpcClient: rpcClient);

  // Show current prices
  if (verbose) print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  if (verbose) print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Estimate output
  final estimatedOutput = anaAmount * floorPrice * 0.97;
  if (verbose) {
    print('\nTransaction:');
    print('  Selling: $anaAmount ANA');
    print('  Receive: $receiveCurrency');
    print('  Estimated: ${estimatedOutput.toStringAsFixed(6)} $receiveCurrency (after ~3% fee)');
    print('\nExecuting sell transaction...');
  }

  // Execute sell
  final result = await client.sellAna(
    userPubkey: userPubkey,
    keypair: keypair,
    anaAmount: anaAmount,
    useNirv: useNirv,
  );

  if (result.success) {
    if (verbose) {
      print('\n✅ Sell successful!');
      print('  Signature: ${result.signature}');
      print('  Explorer: https://solscan.io/tx/${result.signature}');
      print('\nParsing transaction...');
    }

    // Parse the transaction
    try {
      final tx = await client.parseTransaction(result.signature);
      if (verbose) {
        print('  Type: ${tx.type.name.toUpperCase()}');
        if (tx.sent != null) print('  Sent: ${tx.sent!.amount.toStringAsFixed(6)} ${tx.sent!.currency}');
        if (tx.received != null) print('  Received: ${tx.received!.amount.toStringAsFixed(6)} ${tx.received!.currency}');
        if (tx.fee != null) print('  Fee: ${tx.fee!.amount.toStringAsFixed(6)} ${tx.fee!.currency}');
        if (tx.pricePerAna != null) print('  Price: \$${tx.pricePerAna!.toStringAsFixed(6)} per ANA');
        print('');
      }

      // Output JSON result
      print(jsonEncode(tx.toJson()));
    } catch (e) {
      print(jsonEncode({
        'success': true,
        'signature': result.signature,
        'parseError': e.toString(),
        'explorer': 'https://solscan.io/tx/${result.signature}',
      }));
    }
  } else {
    if (verbose) {
      print('\n❌ Sell failed!');
      print('  Error: ${result.error}');
    }
    print(jsonEncode({'success': false, 'error': result.error}));
    exit(1);
  }
}
