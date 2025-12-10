import 'package:equatable/equatable.dart';

/// Nirvana token prices
class NirvanaPrices extends Equatable {
  final double ana;
  final double floor;
  final double prana;
  final DateTime lastUpdated;

  const NirvanaPrices({
    required this.ana,
    required this.floor,
    required this.prana,
    required this.lastUpdated,
  });

  @override
  List<Object?> get props => [ana, floor, prana, lastUpdated];

  @override
  String toString() {
    return 'NirvanaPrices(ana: $ana, floor: $floor, prana: $prana, lastUpdated: $lastUpdated)';
  }
}
