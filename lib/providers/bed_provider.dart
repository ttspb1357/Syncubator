import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bed_model.dart';
import '../services/api_service.dart';
import '../services/bed_service.dart';

enum BedCommandStatus { idle, sending, error }

class BedProvider extends ChangeNotifier {
  final BedService _bedService;
  Timer? _pollTimer;

  BedProvider({BedService? bedService})
      : _bedService = bedService ?? BedService();

  BedModel _bed = BedModel(action: BedAction.idle, distance: 0.0);
  BedCommandStatus _commandStatus = BedCommandStatus.idle;
  String? _lastErrorMessage;
  bool _isRestarting = false;

  BedModel get bed => _bed;
  BedCommandStatus get commandStatus => _commandStatus;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get isRestarting => _isRestarting;

  void startMonitoring() {
    if (_pollTimer != null) return;
    _fetchStatus();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
          (_) => _fetchStatus(),
    );
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchStatus() async {
    try {
      _bed = await _bedService.getStatus();
      notifyListeners();
    } catch (_) {
      // Silently fail for background status polling
    }
  }

  Future<void> raise() => _sendCommand("up");
  Future<void> lower() => _sendCommand("down");

  Future<void> _sendCommand(String direction) async {
    _commandStatus = BedCommandStatus.sending;
    _lastErrorMessage = null;
    notifyListeners();

    try {
      await _bedService.move(direction);
      _commandStatus = BedCommandStatus.idle;
    } on DeviceUnreachableException catch (e) {
      _commandStatus = BedCommandStatus.error;
      _lastErrorMessage = e.toString();
    } on ApiResponseException catch (e) {
      _commandStatus = BedCommandStatus.error;
      _lastErrorMessage = e.toString();
    } catch (e) {
      _commandStatus = BedCommandStatus.error;
      _lastErrorMessage = 'Unexpected error: $e';
    }
    notifyListeners();
  }

  /// Re-initializes the bed distance sensor hardware on the Pi, then
  /// immediately re-fetches so the UI reflects it without waiting for the
  /// next poll tick.
  Future<void> restartSensor() async {
    _isRestarting = true;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      await _bedService.restartSensor();
    } catch (e) {
      _lastErrorMessage = 'Restart failed: $e';
    }
    _isRestarting = false;
    await _fetchStatus();
  }

  @override
  void dispose() {
    stopMonitoring();
    _bedService.dispose();
    super.dispose();
  }
}
