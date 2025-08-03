import 'package:test/test.dart';
import 'package:nirvana_solana/nirvana_solana.dart';
import 'package:solana/solana.dart';

void main() {
  group('NirvanaConfig', () {
    test('should create mainnet config with correct values', () {
      final config = NirvanaConfig.mainnet();
      
      expect(config.programId, equals('NirvHuZvrm2zSxjkBvSbaF2tHfP5j7cvMj9QmdoHVwb'));
      expect(config.tenantAccount, equals('BcAoCEdkzV2J21gAjCCEokBw5iMnAe96SbYo9F6QmKWV'));
      expect(config.anaMint, equals('5DkzT65YJvCsZcot9L6qwkJnsBCPmKHjJz3QU7t7QeRW'));
      expect(config.nirvMint, equals('3eamaYJ7yicyRd3mYz4YeNyNPGVo6zMmKUp5UP25AxRM'));
      expect(config.pranaMint, equals('CLr7G2af9VSfH1PFZ5fYvB8WK1DTgE85qrVjpa8Xkg4N'));
      expect(config.usdcMint, equals('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'));
    });
  });

  group('NirvanaPrices', () {
    test('should create prices with all fields', () {
      final now = DateTime.now();
      final prices = NirvanaPrices(
        anaMarket: 1.5,
        anaFloor: 1.2,
        prana: 0.3,
        lastUpdated: now,
      );
      
      expect(prices.anaMarket, equals(1.5));
      expect(prices.anaFloor, equals(1.2));
      expect(prices.prana, equals(0.3));
      expect(prices.lastUpdated, equals(now));
    });
    
    test('should implement equality correctly', () {
      final now = DateTime.now();
      final prices1 = NirvanaPrices(
        anaMarket: 1.5,
        anaFloor: 1.2,
        prana: 0.3,
        lastUpdated: now,
      );
      final prices2 = NirvanaPrices(
        anaMarket: 1.5,
        anaFloor: 1.2,
        prana: 0.3,
        lastUpdated: now,
      );
      
      expect(prices1, equals(prices2));
    });
  });

  group('TransactionResult', () {
    test('should create success result', () {
      final result = TransactionResult.success(
        signature: 'test-signature',
        logs: ['log1', 'log2'],
      );
      
      expect(result.success, isTrue);
      expect(result.signature, equals('test-signature'));
      expect(result.error, isNull);
      expect(result.logs, equals(['log1', 'log2']));
    });
    
    test('should create failure result', () {
      final result = TransactionResult.failure(
        signature: 'test-signature',
        error: 'Test error',
        logs: ['error log'],
      );
      
      expect(result.success, isFalse);
      expect(result.signature, equals('test-signature'));
      expect(result.error, equals('Test error'));
      expect(result.logs, equals(['error log']));
    });
  });

  // Note: Full integration tests would require mocking the RPC client
  // and testing the NirvanaClient methods
}