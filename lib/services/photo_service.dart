import '../models/photo_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class PhotoService {
  final ApiService _apiService;

  PhotoService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  // Demo mode keeps the light state locally so the button can be tried.
  bool _mockOn = false;

  Future<PhotoModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return PhotoModel(isOn: _mockOn);
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final photoJson = json['photo'] as Map<String, dynamic>? ?? {};
    return PhotoModel.fromJson(photoJson);
  }

  Future<void> setOn(bool on) async {
    if (ApiConstants.useMockData) {
      _mockOn = on;
      return;
    }
    await _apiService.postJson(ApiConstants.photoEndpoint, body: {'on': on});
  }

  void dispose() => _apiService.dispose();
}
