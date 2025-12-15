import 'package:equatable/equatable.dart';

/// Status of the price lookup result
enum PriceResultStatus {
  /// Successfully found a buy/sell transaction with price.
  /// [signature] contains the buy/sell tx signature (for caching).
  found,

  /// Reached the afterSignature limit - no new buy/sell transactions.
  /// App should use its cached price.
  /// [signature] may contain the oldest checked signature (not useful).
  reachedAfterLimit,

  /// Checked all transactions in batch but none were buy/sell.
  /// App should retry with `beforeSignature: result.signature` to page deeper.
  /// [signature] contains the oldest checked signature (for paging).
  limitReached,

  /// Network or RPC error occurred.
  /// App should give up or retry later.
  error,
}

/// Result of looking up ANA price from a recent transaction
class TransactionPriceResult extends Equatable {
  /// The calculated price (null if status != found)
  final double? price;

  /// Context-dependent signature:
  /// - [found]: the buy/sell tx signature (for price caching)
  /// - [limitReached]: the oldest checked signature (use as beforeSignature to page)
  /// - [reachedAfterLimit]: null (no new transactions)
  /// - [error]: null
  final String? signature;

  /// The newest transaction signature that was checked (for checkpoint caching).
  /// Use this as `afterSignature` on next fetch to skip already-parsed transactions.
  /// Available for [found] and [limitReached] statuses.
  final String? newestCheckedSignature;

  /// Fee paid in the transaction
  final double? fee;

  /// Currency used (USDC, NIRV)
  final String? currency;

  /// Status of the lookup
  final PriceResultStatus status;

  /// Error message if status == error
  final String? errorMessage;

  const TransactionPriceResult({
    this.price,
    this.signature,
    this.newestCheckedSignature,
    this.fee,
    this.currency,
    required this.status,
    this.errorMessage,
  });

  /// Creates a successful result
  factory TransactionPriceResult.found({
    required double price,
    required String signature,
    String? newestCheckedSignature,
    double? fee,
    String? currency,
  }) {
    return TransactionPriceResult(
      price: price,
      signature: signature,
      newestCheckedSignature: newestCheckedSignature,
      fee: fee,
      currency: currency,
      status: PriceResultStatus.found,
    );
  }

  /// Creates a result indicating we reached the afterSignature limit
  factory TransactionPriceResult.reachedAfterLimit() {
    return const TransactionPriceResult(
      status: PriceResultStatus.reachedAfterLimit,
    );
  }

  /// Creates a result indicating we hit the batch limit without finding buy/sell
  factory TransactionPriceResult.limitReached({
    required String signature,
    required String newestCheckedSignature,
  }) {
    return TransactionPriceResult(
      status: PriceResultStatus.limitReached,
      signature: signature,
      newestCheckedSignature: newestCheckedSignature,
    );
  }

  /// Creates an error result
  factory TransactionPriceResult.error(String message) {
    return TransactionPriceResult(
      status: PriceResultStatus.error,
      errorMessage: message,
    );
  }

  /// Whether a price was found
  bool get hasPrice => status == PriceResultStatus.found && price != null;

  /// Whether the app should use its cached price
  bool get shouldUseCached => status == PriceResultStatus.reachedAfterLimit;

  /// Whether the app should retry with paging
  bool get shouldRetryWithPaging => status == PriceResultStatus.limitReached;

  /// Whether an error occurred
  bool get hasError => status == PriceResultStatus.error;

  @override
  List<Object?> get props => [price, signature, newestCheckedSignature, fee, currency, status, errorMessage];

  @override
  String toString() {
    switch (status) {
      case PriceResultStatus.found:
        return 'TransactionPriceResult.found(price: $price, signature: $signature, newestChecked: $newestCheckedSignature)';
      case PriceResultStatus.reachedAfterLimit:
        return 'TransactionPriceResult.reachedAfterLimit()';
      case PriceResultStatus.limitReached:
        return 'TransactionPriceResult.limitReached(signature: $signature, newestChecked: $newestCheckedSignature)';
      case PriceResultStatus.error:
        return 'TransactionPriceResult.error($errorMessage)';
    }
  }
}
