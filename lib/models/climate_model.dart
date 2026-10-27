class ClimateModel {
  final double currentTemp;
  final double currentHumidity;
  final double currentPressure;
  final double targetTemp;
  final double targetHumidity;
  final String heaterStatus;
  final String humidifierStatus;
  final bool controlEnabled;

  ClimateModel({
    required this.currentTemp,
    required this.currentHumidity,
    required this.currentPressure,
    required this.targetTemp,
    required this.targetHumidity,
    required this.heaterStatus,
    required this.humidifierStatus,
    required this.controlEnabled,
  });

  factory ClimateModel.fromJson(Map<String, dynamic> json) {
    return ClimateModel(
      currentTemp: (json['temp'] as num?)?.toDouble() ?? 0.0,
      currentHumidity: (json['humidity'] as num?)?.toDouble() ?? 0.0,
      currentPressure: (json['pressure'] as num?)?.toDouble() ?? 0.0,
      targetTemp: (json['target_temp'] as num?)?.toDouble() ?? 30.0,
      targetHumidity: (json['target_hum'] as num?)?.toDouble() ?? 60.0,
      heaterStatus: (json['heater_on'] == true) ? 'ON' : 'OFF',
      humidifierStatus: (json['humidifier_on'] == true) ? 'ON' : 'OFF',
      controlEnabled: json['control_enabled'] as bool? ?? false,
    );
  }

  ClimateModel copyWith({
    double? currentTemp,
    double? currentHumidity,
    double? currentPressure,
    double? targetTemp,
    double? targetHumidity,
    String? heaterStatus,
    String? humidifierStatus,
    bool? controlEnabled,
  }) {
    return ClimateModel(
      currentTemp: currentTemp ?? this.currentTemp,
      currentHumidity: currentHumidity ?? this.currentHumidity,
      currentPressure: currentPressure ?? this.currentPressure,
      targetTemp: targetTemp ?? this.targetTemp,
      targetHumidity: targetHumidity ?? this.targetHumidity,
      heaterStatus: heaterStatus ?? this.heaterStatus,
      humidifierStatus: humidifierStatus ?? this.humidifierStatus,
      controlEnabled: controlEnabled ?? this.controlEnabled,
    );
  }
}
