class WeightModel {
  final double value;
  final String unit;
  final List<double> cells;
  final DateTime timestamp;

  WeightModel({
    required this.value,
    required this.unit,
    required this.cells,
    required this.timestamp,
  });

  factory WeightModel.fromJson(Map<String, dynamic> json) {
    return WeightModel(
      value: (json['total'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? 'g',
      cells: (json['cells'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      timestamp: DateTime.now(),
    );
  }
}
