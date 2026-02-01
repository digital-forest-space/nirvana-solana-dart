import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

/// Execute a stake ANA transaction
///
/// Usage: dart scripts/stake_ana.dart <keypair_path> <ana_amount> [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/stake_ana.dart ~/.config/solana/id.json 1.5
///   dart scripts/stake_ana.dart ~/.config/solana/id.json 1.5 --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart scripts/stake_ana.dart <keypair_path> <ana_amount> [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
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
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');

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
  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  // Show current prices
  if (verbose) print('\nFetching current floor price...');
  final floorPrice = await client.fetchFloorPrice();
  if (verbose) print('  Floor price: \$${floorPrice.toStringAsFixed(6)}');

  // Check personal account status
  if (verbose) print('\nChecking personal account...');
  final personalAccount = await client.derivePersonalAccount(userPubkey);
  if (verbose) print('  PDA: $personalAccount');
  final personalAccountInfo = await client.getPersonalAccountInfo(userPubkey);
  final needsInit = personalAccountInfo == null;
  if (verbose) {
    if (needsInit) {
      print('  Status: not found — will initialize in same transaction');
    } else {
      print('  Status: exists');
      print('  Staked ANA: ${personalAccountInfo.stakedAna.toStringAsFixed(6)}');
    }
  }

  if (verbose) {
    print('\nTransaction:');
    print('  Staking: $anaAmount ANA');
    if (needsInit) print('  Init: personal account will be created');
    print('\nExecuting stake transaction...');
  }

  // Execute stake
  final result = await client.stakeAna(
    userPubkey: userPubkey,
    keypair: keypair,
    anaAmount: anaAmount,
  );

  if (result.success) {
    if (verbose) {
      print('\n✅ Stake successful!');
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
          print('  Staked: ${s.amount.toStringAsFixed(6)} ${s.currency}');
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
      print('\n❌ Stake failed!');
      print('  Error: ${result.error}');
    }
    print(jsonEncode({'success': false, 'error': result.error}));
    exit(1);
  }
}
