// Fetches and decodes an Address Lookup Table from Solana
// Usage: dart run scripts/fetch_lookup_table.dart <lookup_table_address> [--rpc <url>]

import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// Known addresses for labeling
const knownAddresses = {
  'So11111111111111111111111111111111111111112': 'Native SOL',
  'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo': 'navSOL Mint',
  'A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS': 'ZEC Token',
  'navZyeDnqgHBJQjHX8Kk7ZEzwFgDXxVJBcsAXd76gVe': 'navZEC Mint',
  'CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N': 'prANA',
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': 'USDC',
  '4KnomWX4ga9qmDdQN9GctJKjEnwLQTNWWHs57MyYtmYc': 'navSOL Samsara Market',
  'A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc': 'navSOL Mayflower Market',
  'DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj': 'navSOL Market Metadata',
  'Lmdgb4NE4T3ubmQZQZQZ7t4UP6A98NdVbmZPcoEdkdC': 'navSOL Market Group',
  '9JiASAyMBL9riFDPJtWCEtK4E2rr2Yfpqxoynxa3XemE': 'navZEC Samsara Market',
  '9SBSQvx5B8tKRgtYa3tyXeyvL3JMAZiA2JVXWzDnFKig': 'navZEC Mayflower Market',
  'HcGpdC8EtNpZPComvRaXDQtGHLpCFXMqfzRYeRSPCT5L': 'navZEC Market Metadata',
  '81JEJdJSZbaXixpD8WQSBWBfkDa6m6KpXpSErzYUHq6z': 'Mayflower Tenant',
  'FvLdBhqeSJktfcUGq5S4mpNAiTYg2hUhto8AHzjqskFC': 'Samsara Tenant',
  'SiDxZaBNqVDCDxvVvXoGMLwLhzSbLVtaQing4RtPpDN': 'Tenant Admin',
  'SAMmdq34d9RJoqoqfnGhMRUvZumQriaT55eGzXeAQj7': 'Samsara Program',
  'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v': 'Mayflower Program',
  'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA': 'Token Program',
  'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL': 'Associated Token Program',
  '11111111111111111111111111111111': 'System Program',
  'ComputeBudget111111111111111111111111111111': 'Compute Budget Program',
};

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    LogService.log('Usage: dart run scripts/fetch_lookup_table.dart <lookup_table_address> [--rpc <url>]');
    LogService.log('');
    LogService.log('Example:');
    LogService.log('  dart run scripts/fetch_lookup_table.dart HeTHfJCgHxpb1snGC5mk8M7bzs99kYAeMBuk9qHd3tMd');
    exit(1);
  }

  final lookupTableAddress = args[0];
  String rpcUrl = Platform.environment['SOLANA_RPC_URL'] ?? 'https://api.mainnet-beta.solana.com';

  // Parse --rpc flag
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--rpc' && i + 1 < args.length) {
      rpcUrl = args[i + 1];
      break;
    }
  }

  LogService.log('Fetching lookup table: $lookupTableAddress');
  LogService.log('RPC: $rpcUrl');
  LogService.log('');

  try {
    final addresses = await fetchLookupTable(rpcUrl, lookupTableAddress);

    LogService.log('Lookup Table Contents (${addresses.length} addresses):');
    LogService.log('=' * 80);

    for (var i = 0; i < addresses.length; i++) {
      final addr = addresses[i];
      final label = knownAddresses[addr] ?? '';
      final labelStr = label.isNotEmpty ? ' [$label]' : '';
      LogService.log('  $i: $addr$labelStr');
    }

    LogService.log('');
    LogService.log('JSON output:');
    final output = {
      'lookupTable': lookupTableAddress,
      'addresses': addresses.asMap().map((i, addr) => MapEntry(
        i.toString(),
        {
          'address': addr,
          'label': knownAddresses[addr] ?? '',
        },
      )),
    };
    LogService.log(JsonEncoder.withIndent('  ').convert(output));
  } catch (e) {
    LogService.log('Error: $e');
    exit(1);
  }
}

Future<List<String>> fetchLookupTable(String rpcUrl, String address) async {
  final response = await http.post(
    Uri.parse(rpcUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getAccountInfo',
      'params': [
        address,
        {'encoding': 'base64'},
      ],
    }),
  );

  if (response.statusCode != 200) {
    throw Exception('RPC request failed: ${response.statusCode}');
  }

  final json = jsonDecode(response.body);
  if (json['error'] != null) {
    throw Exception('RPC error: ${json['error']}');
  }

  final accountInfo = json['result']?['value'];
  if (accountInfo == null) {
    throw Exception('Account not found');
  }

  final data = base64Decode(accountInfo['data'][0]);
  return decodeLookupTable(data);
}

List<String> decodeLookupTable(Uint8List data) {
  // Address Lookup Table format:
  // - 4 bytes: discriminator (unused here)
  // - 8 bytes: deactivation slot
  // - 8 bytes: last extended slot
  // - 1 byte: last extended slot start index
  // - 1 byte: padding
  // - 32 bytes each: addresses

  // The actual format is more complex, let's use the simpler approach
  // Header is 56 bytes, then 32 bytes per address

  const headerSize = 56;
  if (data.length < headerSize) {
    throw Exception('Invalid lookup table data: too short');
  }

  final addressCount = (data.length - headerSize) ~/ 32;
  final addresses = <String>[];

  for (var i = 0; i < addressCount; i++) {
    final offset = headerSize + (i * 32);
    final addressBytes = data.sublist(offset, offset + 32);
    addresses.add(base58Encode(addressBytes));
  }

  return addresses;
}

// Base58 encoding for Solana addresses
const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

String base58Encode(List<int> bytes) {
  if (bytes.isEmpty) return '';

  // Count leading zeros
  var leadingZeros = 0;
  for (final b in bytes) {
    if (b == 0) {
      leadingZeros++;
    } else {
      break;
    }
  }

  // Convert to base58
  final size = bytes.length * 138 ~/ 100 + 1;
  final b58 = List<int>.filled(size, 0);

  for (final byte in bytes) {
    var carry = byte;
    var i = size - 1;
    while (carry != 0 || i >= size - (b58.length - leadingZeros)) {
      carry += 256 * b58[i];
      b58[i] = carry % 58;
      carry ~/= 58;
      i--;
    }
  }

  // Skip leading zeros in b58
  var start = 0;
  while (start < b58.length && b58[start] == 0) {
    start++;
  }

  // Build result
  final result = StringBuffer();
  for (var i = 0; i < leadingZeros; i++) {
    result.write('1');
  }
  for (var i = start; i < b58.length; i++) {
    result.write(_alphabet[b58[i]]);
  }

  return result.toString();
}
