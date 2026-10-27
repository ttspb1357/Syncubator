import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/lid_model.dart';
import '../services/api_service.dart';
import '../services/lid_service.dart';

class LidProvider extends ChangeNotifier {
  final LidService _service;
  Timer? _pollTimer;

  LidProvider({LidService? service}) : _service = service ?? LidService();

  LidModel _lid = const LidModel.initial();
  bool _sending = false;
  String? _lastErrorMessage;

  LidModel get lid => _lid;
  bool get isSending => _sending;
  String? get lastErrorMessage => _lastErrorMessage;

  void startMonitoring() {
    if (_pollTimer != null) return;
    _fetch();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _fetch());
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetch() async {
    try {
      _lid = await _service.fetchStatus();
      notifyListeners();
    } catch (_) {
      // A dropped poll keeps the last known state on screen.
    }
  }

  Future<void> open() => _send('open');
  Future<void> close() => _send('close');

  Future<void> _send(String action) async {
    if (_sending) return;
    _sending = true;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      await _service.move(action);
    } on DeviceUnreachableException catch (e) {
      _lastErrorMessage = e.toString();
    } on ApiResponseException catch (e) {
      _lastErrorMessage = e.toString();
    } catch (e) {
      _lastErrorMessage = 'Unexpected error: $e';
    }
    _sending = false;
    // Show the Pi's answer straight away instead of waiting for the next poll.
    await _fetch();
  }

  @override
  void dispose() {
    stopMonitoring();
    _service.dispose();
    super.dispose();
  }
}
