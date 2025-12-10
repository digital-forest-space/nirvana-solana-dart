import 'package:equatable/equatable.dart';

/// Result of looking up ANA price from a recent transaction
class TransactionPriceResult extends Equatable {
  final double price;
  final String transaction;
  final double fee;
  final String currency;

  const TransactionPriceResult({
    required this.price,
    required this.transaction,
    required this.fee,
    required this.currency,
  });

  @override
  List<Object?> get props => [price, transaction, fee, currency];

  @override
  String toString() {
    return 'TransactionPriceResult(price: $price, transaction: $transaction, fee: $fee, currency: $currency)';
  }
}
