import 'package:nirvana_solana/src/utils/log_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';

/// Find a user's Samsara position by querying program accounts
/// This uses the same approach as Nirvana - getProgramAccounts with filters
void main() async {
  final rpcUrl = 'https://api.mainnet-beta.solana.com';
  final mayflowerProgram = 'AVMmmRzwc2kETQNhPiFVnyu62HrgsQXTD6D7SnSfEz7v';

  // Test users from intercepted transactions
  final testUsers = {
    'user1': 'YOUR_WALLET_ADDRESS_HERE',
    'user2': 'YOUR_WALLET_ADDRESS_HERE',
  };

  // Known positions from interception
  final knownPositions = {
    'YOUR_WALLET_ADDRESS_HERE': 'GsCuiZUzBsUcwtm4E95QvNFRAE25u8TBvBAD1ZJycjGf',
    'YOUR_WALLET_ADDRESS_HERE': 'J55Lc31GF5ae5xeztckqQEbWd6Xmkp37YYHzCy7VtgZ1',
  };

  // personal_position account structure:
  // Bytes 0-7:    Discriminator
  // Bytes 8-39:   marketMetadata pubkey
  // Bytes 40-71:  user pubkey  <-- This is what we filter on
  // Bytes 72-103: user_shares pubkey
  // Total observed size: 121 bytes

  LogService.log('Querying Mayflower program accounts to find user positions...\n');

  for (final entry in testUsers.entries) {
    final userName = entry.key;
    final userPubkey = entry.value;
    final expectedPosition = knownPositions[userPubkey];

    LogService.log('=== $userName: $userPubkey ===');
    LogService.log('Expected position: $expectedPosition');

    try {
      // Query with memcmp filter at offset 40 (where user pubkey is stored)
      final response = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getProgramAccounts',
          'params': [
            mayflowerProgram,
            {
              'encoding': 'base64',
              'filters': [
                {'dataSize': 121}, // personal_position size
                {
                  'memcmp': {
                    'offset': 40, // user pubkey starts at byte 40
                    'bytes': userPubkey,
                  }
                }
              ]
            }
          ]
        }),
      );

      final result = jsonDecode(response.body);

      if (result['error'] != null) {
        LogService.log('  RPC Error: ${result['error']}');
        continue;
      }

      final accounts = result['result'] as List;
      LogService.log('  Found ${accounts.length} account(s)');

      for (final account in accounts) {
        final pubkey = account['pubkey'];
        LogService.log('  Account: $pubkey');

        if (pubkey == expectedPosition) {
          LogService.log('  ✅ MATCH! Found the expected personal_position');
        }

        // Decode the data to extract user_shares
        final dataBase64 = account['account']['data'][0] as String;
        final data = base64Decode(dataBase64);

        if (data.length >= 104) {
          final userSharesBytes = data.sublist(72, 104);
          final userShares = Ed25519HDPublicKey(userSharesBytes).toBase58();
          LogService.log('  User shares: $userShares');
        }
      }
    } catch (e) {
      LogService.log('  Error: $e');
    }
    LogService.log('');
  }

  LogService.log('Done!');
}
