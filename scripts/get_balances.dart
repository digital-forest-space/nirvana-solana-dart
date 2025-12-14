import 'dart:convert';
import 'dart:io';
import 'package:nirvana_solana/nirvana_solana.dart';

/// Get all Nirvana balances for a wallet address
///
/// Usage: dart scripts/get_balances.dart <pubkey> [--rpc <url>] [--verbose]
///
/// Examples:
///   dart scripts/get_balances.dart YOUR_WALLET_ADDRESS_HERE
///   dart scripts/get_balances.dart YOUR_WALLET_ADDRESS_HERE --verbose
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart scripts/get_balances.dart <pubkey> [--rpc <url>] [--verbose]');
    print('');
    print('Options:');
    print('  --rpc <url>  Custom RPC endpoint');
    print('  --verbose    Show detailed output before JSON result');
    print('');
    print('Environment:');
    print('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
    exit(1);
  }

  final pubkey = args[0];
  final verbose = args.any((a) => a.toLowerCase() == '--verbose');

  // Parse RPC URL from --rpc flag or environment
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';
  final rpcIndex = args.indexWhere((a) => a.toLowerCase() == '--rpc');
  if (rpcIndex >= 0 && rpcIndex + 1 < args.length) {
    rpcUrl = args[rpcIndex + 1];
  }

  if (verbose) {
    print('Wallet: $pubkey');
    print('RPC: $rpcUrl');
    print('\nFetching balances...');
  }

  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  // Get wallet balances (ANA, NIRV, USDC, prANA)
  final walletBalances = await client.getUserBalances(pubkey);

  // Get staking info from PersonalAccount
  final personalInfo = await client.getPersonalAccountInfo(pubkey);

  // Get claimable prANA (calculated from counters)
  final claimablePrana = await client.getClaimablePrana(pubkey);

  // Get claimable revenue share
  // First check if already staged (fast), if 0 then simulate to get preview
  var claimableRevshare = await client.getClaimableRevshare(pubkey);
  if (claimableRevshare['ANA'] == 0.0 && claimableRevshare['NIRV'] == 0.0) {
    // Nothing staged - use simulation to preview what would be claimable
    claimableRevshare = await client.getClaimableRevshareViaSimulation(pubkey);
  }

  final result = {
    'wallet': {
      'ANA': walletBalances['ANA'] ?? 0.0,
      'NIRV': walletBalances['NIRV'] ?? 0.0,
      'USDC': walletBalances['USDC'] ?? 0.0,
      'prANA': walletBalances['prANA'] ?? 0.0,
    },
    'staked': {
      'ANA': personalInfo?.stakedAna ?? 0.0,
      'prANA': personalInfo?.stakedPrana ?? 0.0,
    },
    'debt': {
      'NIRV': personalInfo?.anaDebt ?? 0.0,
    },
    'claimable': {
      'prANA': claimablePrana,
      'ANA_revshare': claimableRevshare['ANA'] ?? 0.0,
      'NIRV_revshare': claimableRevshare['NIRV'] ?? 0.0,
    },
  };

  if (verbose) {
    print('\n=== Wallet Balances ===');
    print('  ANA:   ${walletBalances['ANA']?.toStringAsFixed(6) ?? '0'}');
    print('  NIRV:  ${walletBalances['NIRV']?.toStringAsFixed(6) ?? '0'}');
    print('  USDC:  ${walletBalances['USDC']?.toStringAsFixed(6) ?? '0'}');
    print('  prANA: ${walletBalances['prANA']?.toStringAsFixed(6) ?? '0'}');

    if (personalInfo != null) {
      print('\n=== Staking Position ===');
      print('  Staked ANA:   ${personalInfo.stakedAna.toStringAsFixed(6)}');
      print('  Staked prANA: ${personalInfo.stakedPrana.toStringAsFixed(6)}');
      print('  NIRV Debt:    ${personalInfo.anaDebt.toStringAsFixed(6)}');
      print('  Claimable prANA: ${claimablePrana.toStringAsFixed(6)}');
      print('\n=== Claimable Revenue Share ===');
      print('  ANA:  ${(claimableRevshare['ANA'] ?? 0.0).toStringAsFixed(6)}');
      print('  NIRV: ${(claimableRevshare['NIRV'] ?? 0.0).toStringAsFixed(6)}');
    } else {
      print('\n=== Staking Position ===');
      print('  No staking position found');
    }
    print('');
  }

  print(jsonEncode(result));
}
