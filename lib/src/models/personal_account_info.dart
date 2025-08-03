import 'package:equatable/equatable.dart';

/// User's personal account information in Nirvana protocol
class PersonalAccountInfo extends Equatable {
  final String address;
  final double anaDebt;
  final double stakedAna;
  final double claimablePrana;
  final double stakedPrana;
  final DateTime lastUpdated;
  
  const PersonalAccountInfo({
    required this.address,
    required this.anaDebt,
    required this.stakedAna,
    required this.claimablePrana,
    required this.stakedPrana,
    required this.lastUpdated,
  });
  
  @override
  List<Object?> get props => [
    address,
    anaDebt,
    stakedAna,
    claimablePrana,
    stakedPrana,
    lastUpdated,
  ];
  
  @override
  String toString() {
    return 'PersonalAccountInfo(address: $address, anaDebt: $anaDebt, stakedAna: $stakedAna, claimablePrana: $claimablePrana, stakedPrana: $stakedPrana, lastUpdated: $lastUpdated)';
  }
}