import 'package:equatable/equatable.dart';

/// Types of Nirvana protocol transactions
enum NirvanaTransactionType {
  buy,
  sell,
  stake,
  unstake,
  borrow,
  repay,
  realize,
  claimPrana,
  unknown,
}

/// Represents a token amount with currency
class TokenAmount extends Equatable {
  final double amount;
  final String currency;

  const TokenAmount({
    required this.amount,
    required this.currency,
  });

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'currency': currency,
  };

  @override
  List<Object?> get props => [amount, currency];

  @override
  String toString() => '$amount $currency';
}

/// Parsed information about a Nirvana protocol transaction
class NirvanaTransaction extends Equatable {
  final String signature;
  final NirvanaTransactionType type;
  final TokenAmount? received;
  final TokenAmount? sent;
  final TokenAmount? fee; // Fee is a separate TokenAmount since it can be a different currency than sent
  final DateTime timestamp;
  final String userAddress;

  const NirvanaTransaction({
    required this.signature,
    required this.type,
    this.received,
    this.sent,
    this.fee,
    required this.timestamp,
    required this.userAddress,
  });

  /// Price per ANA (if applicable)
  double? get pricePerAna {
    if (type == NirvanaTransactionType.buy && received != null && sent != null) {
      if (received!.currency == 'ANA' && received!.amount > 0) {
        return sent!.amount / received!.amount;
      }
    }
    if (type == NirvanaTransactionType.sell && received != null && sent != null) {
      if (sent!.currency == 'ANA' && sent!.amount > 0) {
        return received!.amount / sent!.amount;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'signature': signature,
    'type': type.name,
    'sent': sent?.toJson(),
    'received': received?.toJson(),
    'fee': fee?.toJson(),
    'pricePerAna': pricePerAna,
    'timestamp': timestamp.toIso8601String(),
    'userAddress': userAddress,
  };

  @override
  List<Object?> get props => [signature, type, received, sent, fee, timestamp, userAddress];

  @override
  String toString() {
    final buffer = StringBuffer('NirvanaTransaction(');
    buffer.write('type: ${type.name}, ');
    if (sent != null) buffer.write('sent: $sent, ');
    if (received != null) buffer.write('received: $received, ');
    if (fee != null) buffer.write('fee: $fee, ');
    buffer.write('timestamp: $timestamp, ');
    buffer.write('signature: $signature');
    buffer.write(')');
    return buffer.toString();
  }
}
