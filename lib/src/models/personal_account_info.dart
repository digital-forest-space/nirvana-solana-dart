import 'package:equatable/equatable.dart';

/// User's personal account information in Nirvana protocol
class PersonalAccountInfo extends Equatable {
  final String address;
  final double anaDebt;
  final double stakedAna;
  final double claimablePrana;
  final double stakedPrana;

  /// Claimable ANA revenue share (from simulation)
  final double? claimableAna;

  /// Claimable NIRV revenue share (from simulation)
  final double? claimableNirv;

  final DateTime lastUpdated;

  const PersonalAccountInfo({
    required this.address,
    required this.anaDebt,
    required this.stakedAna,
    required this.claimablePrana,
    required this.stakedPrana,
    this.claimableAna,
    this.claimableNirv,
    required this.lastUpdated,
  });

  /// Create a copy with claimable revenue share values
  PersonalAccountInfo withClaimableRevshare({
    required double claimableAna,
    required double claimableNirv,
  }) {
    return PersonalAccountInfo(
      address: address,
      anaDebt: anaDebt,
      stakedAna: stakedAna,
      claimablePrana: claimablePrana,
      stakedPrana: stakedPrana,
      claimableAna: claimableAna,
      claimableNirv: claimableNirv,
      lastUpdated: lastUpdated,
    );
  }

  @override
  List<Object?> get props => [
    address,
    anaDebt,
    stakedAna,
    claimablePrana,
    stakedPrana,
    claimableAna,
    claimableNirv,
    lastUpdated,
  ];

  @override
  String toString() {
    return 'PersonalAccountInfo(address: $address, anaDebt: $anaDebt, stakedAna: $stakedAna, claimablePrana: $claimablePrana, stakedPrana: $stakedPrana, claimableAna: $claimableAna, claimableNirv: $claimableNirv, lastUpdated: $lastUpdated)';
  }
}
