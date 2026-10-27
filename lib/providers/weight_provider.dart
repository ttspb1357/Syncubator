import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/weight_model.dart';
import '../services/api_service.dart';
import '../services/weight_service.dart';
import '../utils/api_constants.dart';

enum WeightConnectionStatus { loading, connected, offline, error }

class WeightProvider extends ChangeNotifier {
  final WeightService _weightService;
  Timer? _pollTimer;

  WeightProvider({WeightService? weightService})
      : _weightService = weightService ?? WeightService();

  WeightModel? _currentWeight;
  WeightConnectionStatus _status = WeightConnectionStatus.loading;
  String? _lastErrorMessage;
  bool _isRestarting = false;

  /// Over the public site (browser -> Cloudflare -> tunnel -> Pi) the link
  /// stalls for several seconds now and then while the Pi itself is fine.
  /// Keep showing the last reading through such stalls and only report the
  /// device offline once no poll has succeeded for this long. (The
  /// climate/oxygen cards already ride through stalls by simply keeping
  /// their last value.)
  static const Duration _offlineAfter = Duration(seconds: 30);
  DateTime? _lastSuccess;

  WeightModel? get currentWeight => _currentWeight;
  WeightConnectionStatus get status => _status;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get isRestarting => _isRestarting;

  void startMonitoring() {
    if (_pollTimer != null) return;
    _fetchOnce();
    _pollTimer = Timer.periodic(
      ApiConstants.pollInterval,
          (_) => _fetchOnce(),
    );
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchOnce() async {
    try {
      final weight = await _weightService.fetchCurrentWeight();
      _currentWeight = weight;
      _status = WeightConnectionStatus.connected;
      _lastErrorMessage = null;
      _lastSuccess = DateTime.now();
    } on DeviceUnreachableException catch (e) {
      _lastErrorMessage = e.toString();
      final last = _lastSuccess;
      final silentFor = last == null
          ? _offlineAfter // never succeeded: report it on the first failure
          : DateTime.now().difference(last);
      if (silentFor >= _offlineAfter) {
        _status = WeightConnectionStatus.offline;
      }
    } on ApiResponseException catch (e) {
      _status = WeightConnectionStatus.error;
      _lastErrorMessage = e.toString();
    } catch (e) {
      _status = WeightConnectionStatus.error;
      _lastErrorMessage = 'Unexpected error: $e';
    }
    notifyListeners();
  }

  /// Re-initializes the load cell hardware on the Pi, then immediately
  /// re-fetches so the UI reflects the restarted sensors without waiting
  /// for the next poll tick.
  Future<void> restartSensors() async {
    _isRestarting = true;
    notifyListeners();
    try {
      await _weightService.restartSensors();
    } catch (e) {
      _status = WeightConnectionStatus.error;
      _lastErrorMessage = 'Restart failed: $e';
    }
    _isRestarting = false;
    await _fetchOnce();
  }

  @override
  void dispose() {
    stopMonitoring();
    _weightService.dispose();
    super.dispose();
  }
}