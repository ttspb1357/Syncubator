import 'dart:math';
import '../models/weight_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class WeightService {
  final ApiService _apiService;
  final Random _random = Random();

  WeightService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<WeightModel> fetchCurrentWeight() async {
    if (ApiConstants.useMockData) {
      await Future.delayed(const Duration(milliseconds: 300));
      final simulated = 3.2 + (_random.nextDouble() - 0.5) * 0.05;
      return WeightModel(
        value: double.parse(simulated.toStringAsFixed(3)),
        unit: 'g',
        cells: [800.1, 800.2, 800.3, 800.4],
        timestamp: DateTime.now(),
      );
    }

    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final weightJson = json['weight'] as Map<String, dynamic>? ?? {};
    return WeightModel.fromJson(weightJson);
  }

  Future<void> tare() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.weightTareEndpoint);
  }

  /// Re-initializes the load cell hardware on the Pi (not just a re-fetch)
  /// — for when a cell is stuck/unresponsive after a wiring hiccup.
  Future<void> restartSensors() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.weightRestartEndpoint);
  }

  void dispose() => _apiService.dispose();
}
