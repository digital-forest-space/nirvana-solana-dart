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
    LogService.log('Usage: dart scripts/get_balances.dart <pubkey> [--rpc <url>] [--verbose]');
    LogService.log('');
    LogService.log('Options:');
    LogService.log('  --rpc <url>  Custom RPC endpoint');
    LogService.log('  --verbose    Show detailed output before JSON result');
    LogService.log('');
    LogService.log('Environment:');
    LogService.log('  SOLANA_RPC_URL  RPC endpoint (overridden by --rpc)');
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
    LogService.log('Wallet: $pubkey');
    LogService.log('RPC: $rpcUrl');
    LogService.log('\nFetching balances...');
  }

  final client = NirvanaClient.fromRpcUrl(rpcUrl);

  // Get wallet balances (ANA, NIRV, USDC, prANA)
  final walletBalances = await client.getUserBalances(pubkey);

  // Get staking info from PersonalAccount
  final personalInfo = await client.getPersonalAccountInfo(pubkey);

  // Get claimable prANA (calculated from counters)
  final claimablePrana = await client.getClaimablePrana(pubkey);

  // Get borrow capacity (debt, limit, available)
  final borrowCapacity = await client.getBorrowCapacity(pubkey);

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
    if (borrowCapacity != null)
      'borrow': borrowCapacity,
    'claimable': {
      'prANA': claimablePrana,
      'ANA_revshare': claimableRevshare['ANA'] ?? 0.0,
      'NIRV_revshare': claimableRevshare['NIRV'] ?? 0.0,
    },
  };

  if (verbose) {
    LogService.log('\n=== Wallet Balances ===');
    LogService.log('  ANA:   ${walletBalances['ANA']?.toStringAsFixed(6) ?? '0'}');
    LogService.log('  NIRV:  ${walletBalances['NIRV']?.toStringAsFixed(6) ?? '0'}');
    LogService.log('  USDC:  ${walletBalances['USDC']?.toStringAsFixed(6) ?? '0'}');
    LogService.log('  prANA: ${walletBalances['prANA']?.toStringAsFixed(6) ?? '0'}');

    if (personalInfo != null) {
      LogService.log('\n=== Staking Position ===');
      LogService.log('  Staked ANA:   ${personalInfo.stakedAna.toStringAsFixed(6)}');
      LogService.log('  Staked prANA: ${personalInfo.stakedPrana.toStringAsFixed(6)}');
      if (borrowCapacity != null) {
        LogService.log('\n=== Borrow ===');
        LogService.log('  Debt:       ${borrowCapacity['debt']!.toStringAsFixed(6)} NIRV');
        LogService.log('  Limit:      ${borrowCapacity['limit']!.toStringAsFixed(6)} NIRV');
        LogService.log('  Available:  ${borrowCapacity['available']!.toStringAsFixed(6)} NIRV');
      }
      LogService.log('\n=== Claimable ===');
      LogService.log('  prANA: ${claimablePrana.toStringAsFixed(6)}');
      LogService.log('\n=== Claimable Revenue Share ===');
      LogService.log('  ANA:  ${(claimableRevshare['ANA'] ?? 0.0).toStringAsFixed(6)}');
      LogService.log('  NIRV: ${(claimableRevshare['NIRV'] ?? 0.0).toStringAsFixed(6)}');
    } else {
      LogService.log('\n=== Staking Position ===');
      LogService.log('  No staking position found');
    }
    LogService.log('');
  }

  LogService.log(jsonEncode(result));
}
