import '../models/climate_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class ClimateService {
  final ApiService _apiService;

  ClimateService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<ClimateModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return ClimateModel(
        currentTemp: 32.5,
        currentHumidity: 58.0,
        currentPressure: 1013.2,
        targetTemp: 32.0,
        targetHumidity: 60.0,
        heaterStatus: 'OFF',
        humidifierStatus: 'OFF',
        controlEnabled: true,
      );
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    // The integrated status returns a nested 'climate' object
    final climateJson = json['climate'] as Map<String, dynamic>? ?? {};
    return ClimateModel.fromJson(climateJson);
  }

  Future<void> updateSettings({
    double? targetTemp,
    double? targetHum,
    bool? enabled,
    int? activeHeater,
  }) async {
    if (ApiConstants.useMockData) return;
    final body = <String, dynamic>{};
    if (targetTemp != null) body['target_temp'] = targetTemp;
    if (targetHum != null) body['target_hum'] = targetHum;
    if (enabled != null) body['enabled'] = enabled;
    if (activeHeater != null) body['active_heater'] = activeHeater;

    await _apiService.postJson(
      ApiConstants.climateSettingsEndpoint,
      body: body,
    );
  }

  /// Re-initializes the climate sensor hardware (TMP117 x2, BME68x,
  /// MS8607) on the Pi — for when a reading is stuck/missing after a
  /// wiring hiccup.
  Future<void> restartSensors() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.climateRestartEndpoint);
  }
}
