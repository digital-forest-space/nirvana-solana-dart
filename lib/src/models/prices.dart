import 'package:equatable/equatable.dart';

/// Nirvana token prices
class NirvanaPrices extends Equatable {
  final double ana;
  final double floor;
  final double prana;
  final DateTime updatedAt;

  const NirvanaPrices({
    required this.ana,
    required this.floor,
    required this.prana,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [ana, floor, prana, updatedAt];

  @override
  String toString() {
    return 'NirvanaPrices(ana: $ana, floor: $floor, prana: $prana, updatedAt: $updatedAt)';
  }

  Map<String, dynamic> toJson() => {
    'ANA': ana,
    'floor': floor,
    'prANA': prana,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
