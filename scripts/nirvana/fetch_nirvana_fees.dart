import 'dart:io';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/nirvana_solana.dart';

/// Fetch and display Nirvana V2 protocol fees from the tenant account.
///
/// Usage: dart run scripts/nirvana/fetch_nirvana_fees.dart
///
/// Environment:
///   SOLANA_RPC_URL - RPC endpoint (default: https://api.mainnet-beta.solana.com)

void main() async {
  final rpcUrl = Platform.environment['SOLANA_RPC_URL'] ??
      'https://api.mainnet-beta.solana.com';

  final uri = Uri.parse(rpcUrl);
  final wsUrl = Uri.parse(rpcUrl.replaceFirst('https', 'wss'));
  final solanaClient = SolanaClient(
    rpcUrl: uri,
    websocketUrl: wsUrl,
    timeout: const Duration(seconds: 30),
  );
  final rpcClient = DefaultSolanaRpcClient(solanaClient, rpcUrl: uri);
  final client = NirvanaClient(rpcClient: rpcClient);

  final fees = await client.fetchNirvanaFees();
  if (fees == null) {
    LogService.log('ERROR: Could not read tenant account');
    exit(1);
  }

  LogService.log('Nirvana V2 Fees (from tenant account):');
  LogService.log('');
  LogService.log(
    '${'Fee'.padRight(22)} '
    '${'mbps'.padRight(10)} '
    'Percent',
  );
  LogService.log('-' * 45);
  _printFee('Buy ANA', fees.buyAnaMbps);
  _printFee('Sell ANA', fees.sellAnaMbps);
  _printFee('Withdraw ANA', fees.withdrawAnaMbps);
  _printFee('Borrow NIRV', fees.borrowNirvMbps);
  _printFee('Realize prANA', fees.realizePranaMbps);

  LogService.log('');
  LogService.log('(mbps = milli-basis-points, 10000 = 1%)');

  exit(0);
}

void _printFee(String label, int mbps) {
  final pct = (mbps / 10000.0).toStringAsFixed(3);
  LogService.log(
    '${label.padRight(22)} '
    '${mbps.toString().padRight(10)} '
    '$pct%',
  );
}
