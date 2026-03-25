import 'dart:io';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/nirvana_solana.dart';

/// Fetch and display per-market governance parameters for all Samsara markets.
///
/// Usage: dart run scripts/samsara/fetch_market_fees.dart

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
  final client = SamsaraClient(rpcClient: rpcClient);

  final markets = NavTokenMarket.all.values.toList();

  // --- Fees only (from MarketGroup) ---
  LogService.log('=== Market Fees (from MarketGroup) ===');
  LogService.log('');
  final allFees = await client.fetchAllMarketFees(markets);

  LogService.log(
    '${'Market'.padRight(10)} '
    '${'Buy'.padRight(10)} '
    '${'Sell'.padRight(10)} '
    '${'Borrow'.padRight(10)} '
    '${'Exercise'.padRight(10)} '
    '(ubps)',
  );
  LogService.log('-' * 60);

  for (final fees in allFees.values) {
    LogService.log(
      '${fees.marketName.padRight(10)} '
      '${fees.buyFeeUbps.toString().padRight(10)} '
      '${fees.sellFeeUbps.toString().padRight(10)} '
      '${fees.borrowFeeUbps.toString().padRight(10)} '
      '${fees.exerciseOptionFeeUbps.toString().padRight(10)}',
    );
  }

  // --- Full governance (from SamsaraMarket + MarketGroup) ---
  LogService.log('');
  LogService.log('=== Full Governance Parameters (from SamsaraMarket) ===');
  LogService.log('');

  final allGov = await client.fetchAllMarketGovernance(markets);

  for (final gov in allGov.values) {
    LogService.log('${gov.marketName}:');
    _printParam('  Buy Fee', gov.buyFee, unit: 'ubps', isUbps: true);
    _printParam('  Sell Fee', gov.sellFee, unit: 'ubps', isUbps: true);
    _printParam('  Borrow Fee', gov.borrowFee, unit: 'ubps', isUbps: true);
    _printParam('  Floor Cooldown', gov.floorRaiseCooldown, unit: 's');
    _printParam('  Floor Buffer', gov.floorRaiseBuffer, unit: 'ubps', isUbps: true);
    _printParam('  Floor Investment', gov.floorInvestment, unit: 'ubps', isUbps: true);
    _printParam('  Floor Raise Incr', gov.floorRaiseIncrease, unit: 'ubps', isUbps: true);
    LogService.log('  Exercise Option Fee: ${gov.exerciseOptionFeeUbps} ubps');
    LogService.log('');
  }

  exit(0);
}

void _printParam(String label, GovernanceParam p,
    {required String unit, bool isUbps = false}) {
  final pct = isUbps ? ' (${(p.current / 10000).toStringAsFixed(2)}%)' : '';
  LogService.log(
    '${label.padRight(20)} '
    'current=${p.current}$pct  '
    'step=${p.step}  '
    'min=${p.minimum}  '
    'max=${p.maximum} $unit',
  );
}
