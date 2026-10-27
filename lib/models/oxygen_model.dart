class OxygenModel {
  final int level;
  final bool moving;
  final double measuredPercent;
  final double voltage;
  final String sensorStatus;
  final double targetPercent;
  final bool controlEnabled;

  OxygenModel({
    required this.level,
    required this.moving,
    required this.measuredPercent,
    required this.voltage,
    required this.sensorStatus,
    required this.targetPercent,
    required this.controlEnabled,
  });

  factory OxygenModel.fromJson(Map<String, dynamic> json) {
    return OxygenModel(
      level: json['level'] as int? ?? 0,
      moving: json['moving'] as bool? ?? false,
      measuredPercent: (json['measured_percent'] as num? ?? 0.0).toDouble(),
      voltage: (json['voltage'] as num? ?? 0.0).toDouble(),
      sensorStatus: json['sensor_status'] as String? ?? 'UNKNOWN',
      targetPercent: (json['target_percent'] as num? ?? 25.0).toDouble(),
      controlEnabled: json['control_enabled'] as bool? ?? false,
    );
  }

  OxygenModel copyWith({
    int? level,
    bool? moving,
    double? measuredPercent,
    double? voltage,
    String? sensorStatus,
    double? targetPercent,
    bool? controlEnabled,
  }) {
    return OxygenModel(
      level: level ?? this.level,
      moving: moving ?? this.moving,
      measuredPercent: measuredPercent ?? this.measuredPercent,
      voltage: voltage ?? this.voltage,
      sensorStatus: sensorStatus ?? this.sensorStatus,
      targetPercent: targetPercent ?? this.targetPercent,
      controlEnabled: controlEnabled ?? this.controlEnabled,
    );
  }
}
