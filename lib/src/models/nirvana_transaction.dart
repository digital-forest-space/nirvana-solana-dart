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
  final List<TokenAmount> received; // List for multi-token receives (e.g., realize)
  final List<TokenAmount> sent; // List for multi-token sends (e.g., realize burns prANA + pays NIRV/USDC)
  final TokenAmount? fee;
  final DateTime timestamp;
  final String userAddress;

  const NirvanaTransaction({
    required this.signature,
    required this.type,
    this.received = const [],
    this.sent = const [],
    this.fee,
    required this.timestamp,
    required this.userAddress,
  });

  /// Price per ANA (if applicable)
  double? get pricePerAna {
    if (type == NirvanaTransactionType.buy && received.isNotEmpty && sent.isNotEmpty) {
      final anaReceived = received.where((t) => t.currency == 'ANA').firstOrNull;
      final payment = sent.firstOrNull;
      if (anaReceived != null && payment != null && anaReceived.amount > 0) {
        return payment.amount / anaReceived.amount;
      }
    }
    if (type == NirvanaTransactionType.sell && received.isNotEmpty && sent.isNotEmpty) {
      final anaSent = sent.where((t) => t.currency == 'ANA').firstOrNull;
      final payment = received.firstOrNull;
      if (anaSent != null && payment != null && anaSent.amount > 0) {
        return payment.amount / anaSent.amount;
      }
    }
    if (type == NirvanaTransactionType.realize && received.isNotEmpty && sent.isNotEmpty) {
      // For realize: price = NIRV or USDC payment / ANA received
      final anaReceived = received.where((t) => t.currency == 'ANA').firstOrNull;
      final payment = sent.where((t) => t.currency == 'NIRV' || t.currency == 'USDC').firstOrNull;
      if (anaReceived != null && payment != null && anaReceived.amount > 0) {
        return payment.amount / anaReceived.amount;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'signature': signature,
    'type': type.name,
    'sent': sent.length == 1 ? sent.first.toJson() : sent.map((t) => t.toJson()).toList(),
    'received': received.length == 1 ? received.first.toJson() : received.map((t) => t.toJson()).toList(),
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
    if (sent.isNotEmpty) buffer.write('sent: $sent, ');
    if (received.isNotEmpty) buffer.write('received: $received, ');
    if (fee != null) buffer.write('fee: $fee, ');
    buffer.write('timestamp: $timestamp, ');
    buffer.write('signature: $signature');
    buffer.write(')');
    return buffer.toString();
  }
}
