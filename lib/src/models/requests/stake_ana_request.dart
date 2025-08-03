import 'package:equatable/equatable.dart';
import 'package:solana/solana.dart';

/// Request to stake ANA tokens
class StakeAnaRequest extends Equatable {
  final String userPubkey;
  final Ed25519HDKeyPair keypair;
  final double anaAmount; // Amount of ANA to stake
  
  const StakeAnaRequest({
    required this.userPubkey,
    required this.keypair,
    required this.anaAmount,
  });
  
  @override
  List<Object?> get props => [userPubkey, keypair, anaAmount];
}