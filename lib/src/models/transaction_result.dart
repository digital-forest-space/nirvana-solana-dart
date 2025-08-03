import 'package:equatable/equatable.dart';

/// Result of a blockchain transaction
class TransactionResult extends Equatable {
  final bool success;
  final String signature;
  final String? error;
  final List<String> logs;
  
  const TransactionResult({
    required this.success,
    required this.signature,
    this.error,
    required this.logs,
  });
  
  factory TransactionResult.success({
    required String signature,
    List<String> logs = const [],
  }) {
    return TransactionResult(
      success: true,
      signature: signature,
      error: null,
      logs: logs,
    );
  }
  
  factory TransactionResult.failure({
    required String signature,
    required String error,
    List<String> logs = const [],
  }) {
    return TransactionResult(
      success: false,
      signature: signature,
      error: error,
      logs: logs,
    );
  }
  
  @override
  List<Object?> get props => [success, signature, error, logs];
  
  @override
  String toString() {
    return 'TransactionResult(success: $success, signature: $signature, error: $error, logs: $logs)';
  }
}