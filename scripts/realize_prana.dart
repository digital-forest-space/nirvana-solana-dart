import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a realize prANA transaction (convert prANA to ANA)
///
/// Usage: dart scripts/realize_prana.dart <keypair_path> <prana_amount> [--nirv] [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/realize_prana.dart ~/.config/solana/id.json 0.5
///   dart scripts/realize_prana.dart ~/.config/solana/id.json 0.5 --nirv --verbose
///
/// Options:
///   --nirv     Pay with NIRV instead of USDC (default is USDC)
///   --verbose  Show detailed output before JSON result
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/realize_prana.dart <keypair_path> <prana_amount> [--nirv] [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --nirv     Pay with NIRV instead of USDC (default is USDC)');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final keypairPath = args[0];
  final pranaAmount = double.tryParse(args[1]);

  // Parse flags
  final useNirv = args.any((a) => a.toLowerCase() == '--nirv');
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (pranaAmount == null || pranaAmount <= 0) {
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

  final paymentCurrency = useNirv ? 'NIRV' : 'USDC';
  if (verbose) {
    print('\nTransaction:');
    print('  Realizing: $pranaAmount prANA');
    print('  Payment: $paymentCurrency');
    print('\nExecuting realize transaction...');
  }

  // Execute realize
  final result = await client.realizePrana(
    userPubkey: userPubkey,
    keypair: keypair,
    pranaAmount: pranaAmount,
    useNirv: useNirv,
  );

  if (result.success) {
    if (verbose) {
      print('\n✅ Realize successful!');
      print('  Signature: ${result.signature}');
      print('  Explorer: https://solscan.io/tx/${result.signature}');
      print('\nParsing transaction...');
    }

    // Parse the transaction
    try {
      final tx = await client.parseTransaction(result.signature);
      if (verbose) {
        print('  Type: ${tx.type.name.toUpperCase()}');
        for (final s in tx.sent) {
          print('  Sent: ${s.amount.toStringAsFixed(6)} ${s.currency}');
        }
        for (final r in tx.received) {
          print('  Received: ${r.amount.toStringAsFixed(6)} ${r.currency}');
        }
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
      print('\n❌ Realize failed!');
      print('  Error: ${result.error}');
    }
    print(jsonEncode({'success': false, 'error': result.error}));
    exit(1);
  }
}
