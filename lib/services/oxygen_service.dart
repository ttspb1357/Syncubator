import '../models/oxygen_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class OxygenService {
  final ApiService _apiService;

  OxygenService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<OxygenModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return OxygenModel(
        level: 2,
        moving: false,
        measuredPercent: 21.0 + (DateTime.now().second % 5),
        voltage: 1.4,
        sensorStatus: 'OK',
        targetPercent: 25.0,
        controlEnabled: false,
      );
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final oxygenJson = json['oxygen'] as Map<String, dynamic>? ?? {};
    return OxygenModel.fromJson(oxygenJson);
  }

  Future<void> setLevel(int level) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.oxygenLevelEndpoint,
      body: {'level': level},
    );
  }

  /// Configures automatic inflow control — target O2 percentage and
  /// whether the Pi's hysteresis loop is allowed to drive the valve
  /// on its own (same on/off-band pattern as climate control). Only
  /// the provided fields are updated.
  Future<void> updateSettings({double? targetPercent, bool? enabled}) async {
    if (ApiConstants.useMockData) return;
    final body = <String, dynamic>{};
    if (targetPercent != null) body['target_percent'] = targetPercent;
    if (enabled != null) body['enabled'] = enabled;
    await _apiService.postJson(
      ApiConstants.oxygenSettingsEndpoint,
      body: body,
    );
  }

  /// Re-initializes the ADS1115 O2 concentration sensor on the Pi (not
  /// the valve servo, which has its own move mechanism via [setLevel]) —
  /// for when the reading is stuck/missing after a wiring hiccup.
  Future<void> restartSensor() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.oxygenRestartEndpoint);
  }

  void dispose() => _apiService.dispose();
}
