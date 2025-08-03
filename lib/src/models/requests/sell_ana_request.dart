import 'package:equatable/equatable.dart';
import 'package:solana/solana.dart';

/// Request to sell ANA tokens
class SellAnaRequest extends Equatable {
  final String userPubkey;
  final Ed25519HDKeyPair keypair;
  final double anaAmount; // Amount of ANA to sell
  final double? minUsdcAmount; // Minimum USDC to receive (slippage protection)
  
  const SellAnaRequest({
    required this.userPubkey,
    required this.keypair,
    required this.anaAmount,
    this.minUsdcAmount,
  });
  
  @override
  List<Object?> get props => [userPubkey, keypair, anaAmount, minUsdcAmount];
}