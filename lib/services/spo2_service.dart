import 'dart:math' as math;

import '../models/spo2_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class Spo2Service {
  final ApiService _apiService;

  Spo2Service({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<Spo2Model> fetchStatus() async {
    if (ApiConstants.useMockData) {
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      return Spo2Model(
        status: 'OK',
        spo2: 96 + (DateTime.now().second % 3),
        pulse: 138 + (DateTime.now().second % 6),
        pi: 2.4,
        signal: 8,
        pleth: List.generate(
          60,
          (i) => (64 + 40 * math.sin((t + i / 60.0) * 2 * math.pi * 2.3)).round(),
        ),
        monitoringEnabled: false,
      );
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final spo2Json = json['spo2'] as Map<String, dynamic>? ?? {};
    return Spo2Model.fromJson(spo2Json);
  }

  /// Turns SpO2 / pulse / probe alarms on or off on the Pi. Live readings
  /// are shown either way.
  Future<void> setMonitoring(bool enabled) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.spo2SettingsEndpoint,
      body: {'monitoring_enabled': enabled},
    );
  }

  void dispose() => _apiService.dispose();
}
