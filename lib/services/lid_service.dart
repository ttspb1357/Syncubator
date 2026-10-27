import '../models/lid_model.dart';
import '../utils/api_constants.dart';
import 'api_service.dart';

class LidService {
  final ApiService _apiService;

  LidService({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  // Demo mode keeps the lid state locally so the buttons can be tried.
  String _mockPosition = 'closed';
  String? _mockMoving;

  Future<LidModel> fetchStatus() async {
    if (ApiConstants.useMockData) {
      return LidModel(position: _mockPosition, moving: _mockMoving);
    }
    final json = await _apiService.getJson(ApiConstants.statusEndpoint);
    final lidJson = json['lid'] as Map<String, dynamic>? ?? {};
    return LidModel.fromJson(lidJson);
  }

  /// [action] is "open" (actuator retracts for 6 s) or "close" (extends for
  /// 6 s). The Pi refuses Open while the lid is open, and any command while
  /// it is moving.
  Future<void> move(String action) async {
    if (ApiConstants.useMockData) {
      _mockMoving = action == 'open' ? 'opening' : 'closing';
      if (action == 'open') _mockPosition = 'open';
      Future.delayed(const Duration(seconds: 6), () {
        _mockMoving = null;
        _mockPosition = action == 'open' ? 'open' : 'closed';
      });
      return;
    }
    await _apiService.postJson(ApiConstants.lidMoveEndpoint, body: {'action': action});
  }

  void dispose() => _apiService.dispose();
}
