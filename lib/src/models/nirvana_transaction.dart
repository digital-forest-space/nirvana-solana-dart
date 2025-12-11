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
  final TokenAmount? spent;
  final DateTime timestamp;
  final String userAddress;
  final double? fee;

  const NirvanaTransaction({
    required this.signature,
    required this.type,
    this.received,
    this.spent,
    required this.timestamp,
    required this.userAddress,
    this.fee,
  });

  /// Price per ANA (if applicable)
  double? get pricePerAna {
    if (type == NirvanaTransactionType.buy && received != null && spent != null) {
      if (received!.currency == 'ANA' && received!.amount > 0) {
        return spent!.amount / received!.amount;
      }
    }
    if (type == NirvanaTransactionType.sell && received != null && spent != null) {
      if (spent!.currency == 'ANA' && spent!.amount > 0) {
        return received!.amount / spent!.amount;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [signature, type, received, spent, timestamp, userAddress, fee];

  @override
  String toString() {
    final buffer = StringBuffer('NirvanaTransaction(');
    buffer.write('type: ${type.name}, ');
    if (spent != null) buffer.write('spent: $spent, ');
    if (received != null) buffer.write('received: $received, ');
    buffer.write('timestamp: $timestamp, ');
    buffer.write('signature: $signature');
    buffer.write(')');
    return buffer.toString();
  }
}
