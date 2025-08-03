import 'package:equatable/equatable.dart';
import 'package:solana/solana.dart';

/// Request to buy ANA tokens
class BuyAnaRequest extends Equatable {
  final String userPubkey;
  final Ed25519HDKeyPair keypair;
  final double amount; // Amount of USDC or NIRV to spend
  final bool useNirv; // true = use NIRV, false = use USDC
  final double? minAnaAmount; // Minimum ANA to receive (slippage protection)
  
  const BuyAnaRequest({
    required this.userPubkey,
    required this.keypair,
    required this.amount,
    required this.useNirv,
    this.minAnaAmount,
  });
  
  @override
  List<Object?> get props => [userPubkey, keypair, amount, useNirv, minAnaAmount];
}