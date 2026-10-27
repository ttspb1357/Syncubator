import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../utils/api_constants.dart';

class AlarmProvider extends ChangeNotifier {
  final AlarmService _alarmService;
  Timer? _pollTimer;

  AlarmProvider({AlarmService? alarmService})
      : _alarmService = alarmService ?? AlarmService();

  AlarmsModel _alarms = AlarmsModel.empty();
  Map<String, double>? _limits;
  bool _isAcknowledging = false;
  String? _lastErrorMessage;

  AlarmsModel get alarms => _alarms;
  Map<String, double>? get limits => _limits;
  bool get isAcknowledging => _isAcknowledging;
  String? get lastErrorMessage => _lastErrorMessage;

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
      _alarms = await _alarmService.fetchStatus();
      notifyListeners();
    } catch (e) {
      // Deliberately quiet: a dropped poll shouldn't blank the banner and
      // make a live alarm disappear. The last known alarm state stays on
      // screen until a poll succeeds again.
      debugPrint('Alarm poll error: $e');
    }
  }

  /// Acknowledges [id], or every raised alarm when [id] is null, then
  /// re-fetches immediately so the UI reflects it without waiting a tick.
  Future<void> acknowledge({String? id}) async {
    _isAcknowledging = true;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      await _alarmService.acknowledge(id: id);
    } catch (e) {
      _lastErrorMessage = 'Could not acknowledge: $e';
    }
    _isAcknowledging = false;
    await _fetchOnce();
  }

  bool _isSendingSos = false;
  bool get isSendingSos => _isSendingSos;

  /// Raises or cancels SOS, then re-fetches so every part of the UI shows
  /// the Pi's state rather than a guess. Returns false (with
  /// [lastErrorMessage] set) if the Pi could not be reached, so the caller
  /// can say so: a call for help that silently failed is the worst outcome.
  Future<bool> setSos(bool active) async {
    _isSendingSos = true;
    _lastErrorMessage = null;
    notifyListeners();
    var ok = true;
    try {
      await _alarmService.setSos(active);
    } catch (e) {
      ok = false;
      _lastErrorMessage =
          active ? 'SOS could not be sent: $e' : 'SOS could not be cancelled: $e';
    }
    _isSendingSos = false;
    await _fetchOnce();
    return ok;
  }

  Future<void> loadLimits() async {
    try {
      _limits = await _alarmService.fetchLimits();
      _lastErrorMessage = null;
    } catch (e) {
      _lastErrorMessage = 'Could not load limits: $e';
    }
    notifyListeners();
  }

  Future<void> updateLimits(Map<String, double> newLimits) async {
    try {
      await _alarmService.updateLimits(newLimits);
      _limits = {...?_limits, ...newLimits};
      _lastErrorMessage = null;
    } catch (e) {
      _lastErrorMessage = 'Could not save limits: $e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    _alarmService.dispose();
    super.dispose();
  }
}
