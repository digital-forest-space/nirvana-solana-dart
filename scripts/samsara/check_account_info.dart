import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final rpcUrl = 'https://api.mainnet-beta.solana.com';

  // Accounts to check
  final accounts = {
    'user_shares_user1': '67x1iMn9Gx14TPUbifFft44TbC27atwsk22bKKS17im5',
    'user_shares_user2': '8aCFTTWQRUvEgycNikKMjnkE2L99xM2qy1Z6Cfxq8ZKQ',
    'personal_position_user1': 'GsCuiZUzBsUcwtm4E95QvNFRAE25u8TBvBAD1ZJycjGf',
    'personal_position_user2': 'J55Lc31GF5ae5xeztckqQEbWd6Xmkp37YYHzCy7VtgZ1',
    'navMint': 'navSnrYJkCxMiyhM3F7K889X1u8JFLVHHLxiyo6Jjqo',
    'marketMetadata': 'DotD4dZAyr4Kb6AD3RHid8VgmsHUzWF6LRd4WvAMezRj',
    'mayflowerMarket': 'A5M1nWfi6ATSamEJ1ASr2FC87BMwijthTbNRYG7BhYSc',
  };

  for (final entry in accounts.entries) {
    print('\n=== ${entry.key}: ${entry.value} ===');
    await checkAccount(rpcUrl, entry.value);
  }
}

Future<void> checkAccount(String rpcUrl, String pubkey) async {
  try {
    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getAccountInfo',
        'params': [
          pubkey,
          {'encoding': 'jsonParsed'},
        ],
      }),
    );

    final result = jsonDecode(response.body);
    if (result['result'] != null && result['result']['value'] != null) {
      final value = result['result']['value'];
      final owner = value['owner'];
      final dataLen = value['data'] is List ? value['data'][0].length : (value['data']['parsed'] != null ? 'parsed' : 'unknown');
      final lamports = value['lamports'];
      final executable = value['executable'];

      print('  Owner: $owner');
      print('  Lamports: $lamports');
      print('  Executable: $executable');
      print('  Data length: $dataLen');

      // Check if it's a token account
      if (owner == 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA') {
        final parsed = value['data']['parsed'];
        if (parsed != null) {
          final info = parsed['info'];
          print('  Token Account Info:');
          print('    Mint: ${info['mint']}');
          print('    Owner: ${info['owner']}');
          print('    Amount: ${info['tokenAmount']['uiAmount']}');
        }
      } else {
        // Print first 100 bytes of raw data
        if (value['data'] is List && value['data'].isNotEmpty) {
          final rawData = value['data'][0];
          final preview = rawData.length > 100 ? rawData.substring(0, 100) : rawData;
          print('  Data preview (base64): $preview...');
        }
      }
    } else {
      print('  Account not found or error');
      if (result['error'] != null) {
        print('  Error: ${result['error']}');
      }
    }
  } catch (e) {
    print('  Error: $e');
  }
}
