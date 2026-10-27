import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/alarm_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class AlarmService {
  final ApiService _apiService;

  AlarmService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  /// Alarms ride along in the full `/status` payload, so this costs no
  /// extra request beyond what the other providers already poll.
  Future<AlarmsModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return AlarmsModel.empty(
          sosActive: _mockSosSince != null, sosSince: _mockSosSince, sosFrom: _sosSource);
    }

    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final alarmsJson = json['alarms'] as Map<String, dynamic>? ?? {};
    return AlarmsModel.fromJson(alarmsJson,
        sos: json['sos'] as Map<String, dynamic>?);
  }

  /// Demo mode keeps the SOS locally so the button can still be tried.
  DateTime? _mockSosSince;

  static String get _sosSource {
    if (ApiConstants.isKioskDisplay) return 'kiosk';
    return kIsWeb ? 'web' : 'phone';
  }

  /// Raises ([active] true) or cancels the SOS on the incubator. While
  /// raised, the Pi sounds its buzzer continuously and every screen shows
  /// the SOS banner.
  Future<void> setSos(bool active) async {
    if (ApiConstants.useMockData) {
      _mockSosSince = active ? (_mockSosSince ?? DateTime.now()) : null;
      return;
    }
    await _apiService.postJson(
      ApiConstants.sosEndpoint,
      body: {'active': active, 'from': _sosSource},
    );
  }

  /// Silences the buzzer for the backend's silence window. Pass [id] for a
  /// single alarm, or omit it to acknowledge everything currently raised.
  ///
  /// This does not clear an alarm whose condition is still true — it will
  /// sound again when the silence expires.
  Future<void> acknowledge({String? id}) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.alarmsAcknowledgeEndpoint,
      body: id == null ? {} : {'id': id},
    );
  }

  Future<Map<String, double>> fetchLimits() async {
    if (ApiConstants.useMockData) {
      return {
        'air_temp_low': 30.0,
        'air_temp_high': 38.0,
        'humidity_low': 30.0,
        'humidity_high': 85.0,
        'o2_low': 18.0,
        'o2_high': 40.0,
        'spo2_low': 90.0,
        'spo2_high': 98.0,
        'pulse_low': 100.0,
        'pulse_high': 180.0,
        'skin_temp_low': 36.0,
        'skin_temp_high': 37.5,
      };
    }
    final json = await _apiService.getJson(ApiConstants.alarmsLimitsEndpoint);
    return json.map((key, value) =>
        MapEntry(key, (value as num?)?.toDouble() ?? 0.0));
  }

  /// Sends any subset of limits. The backend rejects unknown keys rather
  /// than ignoring them, so a typo surfaces as an error instead of
  /// silently leaving the old threshold in force.
  Future<void> updateLimits(Map<String, double> limits) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.alarmsLimitsEndpoint,
      body: limits,
    );
  }

  void dispose() => _apiService.dispose();
}
