import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';

void main() async {
  final rpcUrl = 'https://api.mainnet-beta.solana.com';

  // The personal_position account we want to decode
  final positionAddress = 'GsCuiZUzBsUcwtm4E95QvNFRAE25u8TBvBAD1ZJycjGf';
  final expectedShares = '67x1iMn9Gx14TPUbifFft44TbC27atwsk22bKKS17im5';

  print('Decoding personal_position account: $positionAddress\n');

  try {
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getAccountInfo',
        'params': [
          positionAddress,
          {'encoding': 'base64'},
        ],
      }),
    );

    final result = jsonDecode(response.body);
    if (result['result'] != null && result['result']['value'] != null) {
      final value = result['result']['value'];
      final dataBase64 = value['data'][0] as String;
      final data = base64Decode(dataBase64);

      print('Account data length: ${data.length} bytes');
      print('Owner: ${value['owner']}');
      print('\n=== Raw data (hex) ===');
      print(data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));

      print('\n=== Trying to find pubkey patterns ===');
      // A Solana pubkey is 32 bytes
      // Let's look for any 32-byte sequence that could be a pubkey
      if (data.length >= 40) {
        // Skip the 8-byte discriminator
        print('\n--- After discriminator (bytes 8+) ---');

        // Check each 32-byte chunk
        for (int offset = 8; offset <= data.length - 32; offset++) {
          try {
            final pubkeyBytes = data.sublist(offset, offset + 32);
            final pubkey = Ed25519HDPublicKey(pubkeyBytes);
            final address = pubkey.toBase58();

            // Print if it looks like a valid address (not all zeros, etc.)
            if (!_isAllZeros(pubkeyBytes) && !_isAllOnes(pubkeyBytes)) {
              print('Offset $offset: $address');
              if (address == expectedShares) {
                print('  ^^^ THIS IS THE EXPECTED user_shares! ^^^');
              }
            }
          } catch (e) {
            // Not a valid pubkey
          }
        }
      }

      print('\n=== Structured decode attempt ===');
      // Anchor accounts typically have:
      // - 8 bytes: discriminator
      // - Then struct fields

      if (data.length >= 8) {
        final discriminator = data.sublist(0, 8);
        print('Discriminator: ${discriminator.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }

      // The struct likely contains:
      // - owner pubkey (32 bytes)
      // - market metadata pubkey (32 bytes)
      // - nav mint pubkey (32 bytes)
      // - user_shares pubkey (32 bytes)
      // - various u64/i64 values for amounts

      if (data.length >= 8 + 32) {
        final field1 = Ed25519HDPublicKey(data.sublist(8, 40));
        print('\nField 1 (bytes 8-39): ${field1.toBase58()}');
        if (field1.toBase58() == expectedShares) print('  ^^^ MATCH user_shares! ^^^');
      }

      if (data.length >= 8 + 64) {
        final field2 = Ed25519HDPublicKey(data.sublist(40, 72));
        print('Field 2 (bytes 40-71): ${field2.toBase58()}');
        if (field2.toBase58() == expectedShares) print('  ^^^ MATCH user_shares! ^^^');
      }

      if (data.length >= 8 + 96) {
        final field3 = Ed25519HDPublicKey(data.sublist(72, 104));
        print('Field 3 (bytes 72-103): ${field3.toBase58()}');
        if (field3.toBase58() == expectedShares) print('  ^^^ MATCH user_shares! ^^^');
      }

      if (data.length >= 8 + 128) {
        final field4 = Ed25519HDPublicKey(data.sublist(104, 136));
        print('Field 4 (bytes 104-135): ${field4.toBase58()}');
        if (field4.toBase58() == expectedShares) print('  ^^^ MATCH user_shares! ^^^');
      }

      // Remaining bytes might be amounts
      if (data.length >= 144) {
        final remaining = data.sublist(136);
        print('\nRemaining bytes (${remaining.length}): ${remaining.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

        // Try to interpret as u64 values
        if (remaining.length >= 8) {
          final bd = ByteData.sublistView(Uint8List.fromList(remaining));
          print('\nAs u64 values:');
          for (int i = 0; i + 8 <= remaining.length; i += 8) {
            final val = bd.getUint64(i, Endian.little);
            print('  Offset ${136 + i}: $val');
          }
        }
      }
    } else {
      print('Account not found');
    }
  } catch (e) {
    print('Error: $e');
  }
}

bool _isAllZeros(List<int> bytes) {
  return bytes.every((b) => b == 0);
}

bool _isAllOnes(List<int> bytes) {
  return bytes.every((b) => b == 255);
}
