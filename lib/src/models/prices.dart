import 'package:equatable/equatable.dart';

/// Nirvana token prices
class NirvanaPrices extends Equatable {
  final double anaMarket;
  final double anaFloor;
  final double prana;
  final DateTime lastUpdated;
  
  const NirvanaPrices({
    required this.anaMarket,
    required this.anaFloor,
    required this.prana,
    required this.lastUpdated,
  });
  
  @override
  List<Object?> get props => [anaMarket, anaFloor, prana, lastUpdated];
  
  @override
  String toString() {
    return 'NirvanaPrices(anaMarket: $anaMarket, anaFloor: $anaFloor, prana: $prana, lastUpdated: $lastUpdated)';
  }
}