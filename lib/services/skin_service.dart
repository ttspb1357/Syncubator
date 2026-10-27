import '../models/skin_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class SkinService {
  final ApiService _apiService;

  SkinService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<SkinModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return SkinModel(
        status: 'OK',
        temp: 36.5 + (DateTime.now().second % 5) / 10.0,
        monitoringEnabled: false,
      );
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final skinJson = json['skin'] as Map<String, dynamic>? ?? {};
    return SkinModel.fromJson(skinJson);
  }

  /// Turns skin temperature / probe alarms on or off on the Pi. The live
  /// reading is shown either way.
  Future<void> setMonitoring(bool enabled) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.skinSettingsEndpoint,
      body: {'monitoring_enabled': enabled},
    );
  }

  void dispose() => _apiService.dispose();
}
