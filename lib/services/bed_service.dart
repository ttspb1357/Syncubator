import '../models/bed_model.dart';
import '../utils/api_constants.dart';
import '../services/api_service.dart';

class BedService {
  final ApiService _apiService;

  BedService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<void> move(String direction) async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(
      ApiConstants.bedMoveEndpoint,
      body: {'direction': direction},
    );
  }

  /// Re-initializes the ToF distance sensor hardware on the Pi (not just a
  /// re-fetch) — for when the reading is stuck/missing after a wiring
  /// hiccup.
  Future<void> restartSensor() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.bedRestartEndpoint);
  }

  Future<BedModel> getStatus() async {
    if (ApiConstants.useMockData) {
      return BedModel(action: BedAction.idle, distance: 1.5);
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final bedJson = json['bed'] as Map<String, dynamic>? ?? {};
    return BedModel.fromJson(bedJson);
  }

  void dispose() => _apiService.dispose();
}
