/// Live reading from the Contec CMS60C pulse oximeter, as reported by the
/// Pi under `/status` -> `spo2`.
class Spo2Model {
  /// OK, NO_FINGER, NO_DATA or NOT_CONNECTED.
  final String status;

  /// Null whenever there is no valid reading (empty probe, no data).
  final int? spo2;
  final int? pulse;
  final double? pi;

  /// Signal strength, 0-15.
  final int signal;

  /// The last second of the pulse waveform, values 0-127.
  final List<int> pleth;

  /// SpO2 / pulse / probe alarms are only raised while this is on.
  final bool monitoringEnabled;

  Spo2Model({
    required this.status,
    required this.spo2,
    required this.pulse,
    required this.pi,
    required this.signal,
    required this.pleth,
    required this.monitoringEnabled,
  });

  bool get hasReading => status == 'OK' && spo2 != null && pulse != null;

  factory Spo2Model.fromJson(Map<String, dynamic> json) {
    return Spo2Model(
      status: json['status'] as String? ?? 'NOT_CONNECTED',
      spo2: (json['spo2'] as num?)?.toInt(),
      pulse: (json['pulse'] as num?)?.toInt(),
      pi: (json['pi'] as num?)?.toDouble(),
      signal: (json['signal'] as num?)?.toInt() ?? 0,
      pleth: (json['pleth'] as List<dynamic>? ?? const [])
          .map((v) => (v as num).toInt())
          .toList(),
      monitoringEnabled: json['monitoring_enabled'] as bool? ?? false,
    );
  }

  Spo2Model copyWith({bool? monitoringEnabled}) {
    return Spo2Model(
      status: status,
      spo2: spo2,
      pulse: pulse,
      pi: pi,
      signal: signal,
      pleth: pleth,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
    );
  }
}
