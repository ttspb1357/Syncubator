import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/skin_model.dart';
import '../services/skin_service.dart';
import '../utils/api_constants.dart';

class SkinProvider extends ChangeNotifier {
  final SkinService _skinService;
  Timer? _pollTimer;

  SkinProvider({SkinService? skinService})
      : _skinService = skinService ?? SkinService();

  SkinModel? _skin;
  SkinModel? get skin => _skin;

  void startMonitoring() {
    if (_pollTimer != null) return;
    _fetchOnce();
    _pollTimer = Timer.periodic(ApiConstants.pollInterval, (_) => _fetchOnce());
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchOnce() async {
    try {
      _skin = await _skinService.fetchStatus();
      notifyListeners();
    } catch (e) {
      debugPrint('Skin poll error: $e');
    }
  }

  Future<void> setMonitoring(bool enabled) async {
    try {
      if (_skin != null) {
        _skin = _skin!.copyWith(monitoringEnabled: enabled);
        notifyListeners();
      }
      await _skinService.setMonitoring(enabled);
    } catch (e) {
      debugPrint('Error setting skin monitoring: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    _skinService.dispose();
    super.dispose();
  }
}
