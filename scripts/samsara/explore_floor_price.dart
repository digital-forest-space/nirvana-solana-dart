import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:nirvana_solana/src/samsara/config.dart';
import 'package:nirvana_solana/src/rpc/solana_rpc_client.dart';

/// Explore Samsara market accounts to find floor price data
/// Target: floor = ~0.048 SOL, market = ~0.070 SOL

void main(List<String> args) async {
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

  final market = NavTokenMarket.navSol();

  // All candidate accounts
  final accounts = {
    'Mayflower Market': market.mayflowerMarket,
    'Samsara Market': market.samsaraMarket,
    'Market Metadata': market.marketMetadata,
    'Market Group': market.marketGroup,
  };

  for (final entry in accounts.entries) {
    LogService.log('=== ${entry.key}: ${entry.value} ===');

    final accountInfo = await rpcClient.getAccountInfo(entry.value);
    if (accountInfo.isEmpty || accountInfo['data'] == null) {
      LogService.log('  Account not found\n');
      continue;
    }

    final base64Data = accountInfo['data']?[0] as String?;
    if (base64Data == null || base64Data.isEmpty) {
      LogService.log('  No data\n');
      continue;
    }

    final bytes = Uint8List.fromList(base64.decode(base64Data));
    final bd = bytes.buffer.asByteData(bytes.offsetInBytes);
    LogService.log('  Owner: ${accountInfo['owner']}');
    LogService.log('  Length: ${bytes.length} bytes');
    LogService.log('');

    // Full hex dump
    LogService.log('  Full hex dump:');
    for (var i = 0; i < bytes.length; i += 16) {
      final end = (i + 16).clamp(0, bytes.length);
      final hex = bytes.sublist(i, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final ascii = bytes.sublist(i, end).map((b) => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.').join('');
      LogService.log('  ${i.toRadixString(16).padLeft(4, '0')}: ${hex.padRight(47)} $ascii');
    }
    LogService.log('');

    // Scan every byte offset for u64 values that could be 0.048 SOL
    // 0.048 SOL = 48,000,000 lamports (9 decimals)
    // Range: 0.03 - 0.08 SOL = 30M - 80M lamports
    LogService.log('  u64 LE scan (0.03-0.08 SOL range, 9 dec):');
    for (var offset = 0; offset + 8 <= bytes.length; offset++) {
      final val = bd.getUint64(offset, Endian.little);
      if (val >= 30000000 && val <= 80000000) {
        final solValue = val / 1e9;
        LogService.log('    offset $offset (0x${offset.toRadixString(16)}): $val = ${solValue.toStringAsFixed(6)} SOL');
      }
    }
    LogService.log('');

    // Scan for Nirvana-style Rust Decimal (scale 10-28)
    LogService.log('  Rust Decimal scan (Nirvana-style, scale 10-28, range 0.03-0.10):');
    for (var offset = 0; offset + 16 <= bytes.length; offset++) {
      final scale = bytes[offset + 2];
      if (scale < 10 || scale > 28) continue;

      BigInt rawValue = BigInt.zero;
      for (int i = 4; i < 16; i++) {
        rawValue |= BigInt.from(bytes[offset + i]) << (8 * (i - 4));
      }
      if (rawValue == BigInt.zero) continue;

      final divisor = BigInt.from(10).pow(scale);
      final val = rawValue.toDouble() / divisor.toDouble();
      if (val >= 0.03 && val <= 0.10) {
        LogService.log('    offset $offset (0x${offset.toRadixString(16)}): scale=$scale val=${val.toStringAsFixed(9)}');
      }
    }
    LogService.log('');

    // Scan for f64 values
    LogService.log('  f64 LE scan (range 0.03-0.10):');
    for (var offset = 0; offset + 8 <= bytes.length; offset++) {
      final val = bd.getFloat64(offset, Endian.little);
      if (val >= 0.03 && val <= 0.10 && val.isFinite) {
        LogService.log('    offset $offset (0x${offset.toRadixString(16)}): ${val.toStringAsFixed(9)}');
      }
    }
    LogService.log('');

    // Scan for wider Rust Decimal (any scale 1-28)
    LogService.log('  Rust Decimal scan (wide scale 1-28, range 0.03-0.10):');
    for (var offset = 0; offset + 16 <= bytes.length; offset++) {
      final scale = bytes[offset + 2];
      if (scale < 1 || scale > 28) continue;

      BigInt rawValue = BigInt.zero;
      for (int i = 4; i < 16; i++) {
        rawValue |= BigInt.from(bytes[offset + i]) << (8 * (i - 4));
      }
      if (rawValue == BigInt.zero) continue;

      final divisor = BigInt.from(10).pow(scale);
      final val = rawValue.toDouble() / divisor.toDouble();
      if (val >= 0.03 && val <= 0.10) {
        LogService.log('    offset $offset (0x${offset.toRadixString(16)}): scale=$scale val=${val.toStringAsFixed(9)}');
      }
    }
    LogService.log('');
  }

  exit(0);
}
