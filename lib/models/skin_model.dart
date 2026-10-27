/// Skin temperature from the YSI-400 probe, as reported by the Pi under
/// `/status` -> `skin`.
class SkinModel {
  /// OK, PROBE_OFF, SHORT, RANGE or NOT_CONNECTED.
  final String status;

  /// Degrees C. Null whenever there is no valid reading.
  final double? temp;

  /// Skin temperature alarms are only raised while this is on.
  final bool monitoringEnabled;

  SkinModel({
    required this.status,
    required this.temp,
    required this.monitoringEnabled,
  });

  bool get hasReading => status == 'OK' && temp != null;

  factory SkinModel.fromJson(Map<String, dynamic> json) {
    return SkinModel(
      status: json['status'] as String? ?? 'NOT_CONNECTED',
      temp: (json['temp'] as num?)?.toDouble(),
      monitoringEnabled: json['monitoring_enabled'] as bool? ?? false,
    );
  }

  SkinModel copyWith({bool? monitoringEnabled}) {
    return SkinModel(
      status: status,
      temp: temp,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
    );
  }
}
