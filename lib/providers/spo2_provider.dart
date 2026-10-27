import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/spo2_model.dart';
import '../services/spo2_service.dart';
import '../utils/api_constants.dart';

class Spo2Provider extends ChangeNotifier {
  final Spo2Service _spo2Service;
  Timer? _pollTimer;

  Spo2Provider({Spo2Service? spo2Service})
      : _spo2Service = spo2Service ?? Spo2Service();

  Spo2Model? _spo2;
  Spo2Model? get spo2 => _spo2;

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
      _spo2 = await _spo2Service.fetchStatus();
      notifyListeners();
    } catch (e) {
      debugPrint('SpO2 poll error: $e');
    }
  }

  Future<void> setMonitoring(bool enabled) async {
    try {
      if (_spo2 != null) {
        _spo2 = _spo2!.copyWith(monitoringEnabled: enabled);
        notifyListeners();
      }
      await _spo2Service.setMonitoring(enabled);
    } catch (e) {
      debugPrint('Error setting SpO2 monitoring: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    _spo2Service.dispose();
    super.dispose();
  }
}
