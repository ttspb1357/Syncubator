import '../utils/api_constants.dart';
import 'api_service.dart';

/// System-level controls for the Pi itself, distinct from sensor/hardware
/// services. Currently just exiting the on-screen kiosk Chromium, for when
/// an operator needs to reach the Pi's own desktop (e.g. to change Wi-Fi)
/// directly from the touchscreen, without a keyboard or remote SSH access.
class SystemService {
  final ApiService _apiService;

  SystemService({ApiService? apiService}) : _apiService = apiService ?? ApiService();

  Future<void> exitKiosk() async {
    if (ApiConstants.useMockData) return;
    await _apiService.postJson(ApiConstants.systemExitKioskEndpoint);
  }

  void dispose() => _apiService.dispose();
}
