import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/oxygen_model.dart';
import '../services/oxygen_service.dart';
import '../utils/api_constants.dart';

class OxygenProvider extends ChangeNotifier {
  final OxygenService _oxygenService;
  Timer? _pollTimer;

  OxygenProvider({OxygenService? oxygenService})
      : _oxygenService = oxygenService ?? OxygenService();

  OxygenModel? _oxygen;
  bool _isRestarting = false;
  OxygenModel? get oxygen => _oxygen;
  bool get isRestarting => _isRestarting;

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
      final fetched = await _oxygenService.fetchStatus();
      _oxygen = fetched;
      notifyListeners();
    } catch (e) {
      debugPrint('Oxygen poll error: $e');
    }
  }

  Future<void> setLevel(int level) async {
    try {
      // Optimistic update
      if (_oxygen != null) {
        _oxygen = _oxygen!.copyWith(level: level, moving: true);
        notifyListeners();
      }
      await _oxygenService.setLevel(level);
    } catch (e) {
      debugPrint('Error setting oxygen level: $e');
    }
  }

  Future<void> updateSettings({double? targetPercent, bool? enabled}) async {
    try {
      if (_oxygen != null) {
        _oxygen = _oxygen!.copyWith(
          targetPercent: targetPercent,
          controlEnabled: enabled,
        );
        notifyListeners();
      }
      await _oxygenService.updateSettings(
        targetPercent: targetPercent,
        enabled: enabled,
      );
    } catch (e) {
      debugPrint('Error updating oxygen settings: $e');
    }
  }

  /// Re-initializes the O2 concentration sensor hardware on the Pi, then
  /// immediately re-fetches so the UI reflects it without waiting for the
  /// next poll tick.
  Future<void> restartSensor() async {
    _isRestarting = true;
    notifyListeners();
    try {
      await _oxygenService.restartSensor();
    } catch (e) {
      debugPrint('Oxygen restart error: $e');
    }
    _isRestarting = false;
    await _fetchOnce();
  }

  @override
  void dispose() {
    stopMonitoring();
    _oxygenService.dispose();
    super.dispose();
  }
}
