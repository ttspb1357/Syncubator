import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/photo_model.dart';
import '../services/api_service.dart';
import '../services/photo_service.dart';

class PhotoProvider extends ChangeNotifier {
  final PhotoService _service;
  Timer? _pollTimer;

  PhotoProvider({PhotoService? service}) : _service = service ?? PhotoService();

  PhotoModel _photo = const PhotoModel.initial();
  bool _sending = false;
  String? _lastErrorMessage;

  PhotoModel get photo => _photo;
  bool get isSending => _sending;
  String? get lastErrorMessage => _lastErrorMessage;

  void startMonitoring() {
    if (_pollTimer != null) return;
    _fetch();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _fetch());
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetch() async {
    try {
      _photo = await _service.fetchStatus();
      notifyListeners();
    } catch (_) {
      // A dropped poll keeps the last known state on screen.
    }
  }

  Future<void> turnOn() => _send(true);
  Future<void> turnOff() => _send(false);

  Future<void> _send(bool on) async {
    if (_sending) return;
    _sending = true;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      await _service.setOn(on);
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
