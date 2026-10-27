import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncubator/utils/api_constants.dart';
import '../utils/app_colors.dart';
import '../utils/secure_http_client.dart';
import 'sensor_restart_button.dart';

/// IMPORTANT: Image.network / NetworkImage cannot render an MJPEG stream
/// ("multipart/x-mixed-replace"). Flutter's image codec expects a single
/// complete image file, not a continuous multipart boundary stream — so the
/// old implementation would show a blank frame or bounce into errorBuilder.
/// This widget instead opens the stream manually, extracts each JPEG frame
/// between the 0xFFD8 (SOI) / 0xFFD9 (EOI) markers — mirroring the same
/// logic your Flask gen_frames() uses to produce them — and repaints with
/// Image.memory on every new frame.
class CameraStreamCard extends StatefulWidget {
  /// Called whenever the stream's actual connection state changes, so a
  /// parent screen can show real status instead of a hardcoded label.
  final ValueChanged<bool>? onConnectionChanged;

  const CameraStreamCard({super.key, this.onConnectionChanged});

  @override
  State<CameraStreamCard> createState() => _CameraStreamCardState();
}

class _CameraStreamCardState extends State<CameraStreamCard> {
  bool _isExpanded = false;
  bool _hasError = false;
  Uint8List? _currentFrame;

  StreamSubscription<List<int>>? _subscription;
  final List<int> _buffer = [];

  DateTime _lastFrameAt = DateTime.now();
  Timer? _watchdog;
  bool? _reportedConnected;
  bool _isManualRestarting = false;

  static const _staleFrameTimeout = Duration(seconds: 5);

  void _reportConnected(bool connected) {
    if (_reportedConnected == connected) return; // only fire on real transitions
    _reportedConnected = connected;
    widget.onConnectionChanged?.call(connected);
  }

  @override
  void initState() {
    super.initState();
    if (!ApiConstants.useMockData) {
      _connect();
    }
  }

  @override
  void dispose() {
    // Report disconnected directly (skip _reportConnected's mounted-safe
    // setState path) since the widget is on its way out.
    widget.onConnectionChanged?.call(false);
    _teardown();
    super.dispose();
  }

  void _teardown() {
    _watchdog?.cancel();
    _watchdog = null;
    _subscription?.cancel();
    _subscription = null;
    // The live client is shared and certificate-pinned; it is owned by
    // SecureHttpClient for the lifetime of the app.
    _buffer.clear();
  }

  Future<void> _connect() async {
    if (ApiConstants.useMockData) return;
    _teardown();
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _currentFrame = null;
    });

    final client = SecureHttpClient.instance;

    try {
      // The kiosk takes the camera's full rate over localhost. Anywhere else
      // (public site, phone) the stream shares one connection with every
      // status poll, so ask the Pi for fewer frames to keep those replies
      // from queueing behind video on a slow link.
      final feed = ApiConstants.isKioskDisplay
          ? '${ApiConstants.baseUrl}/video_feed'
          : '${ApiConstants.baseUrl}/video_feed?fps=${ApiConstants.remoteCameraFps}';
      final request = http.Request('GET', Uri.parse(feed));
      final response = await client.send(request).timeout(ApiConstants.requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Stream returned HTTP ${response.statusCode}');
      }

      _lastFrameAt = DateTime.now();

      _subscription = response.stream.listen(
        _onChunk,
        onError: (_) => _fail(),
        onDone: _fail,
        cancelOnError: true,
      );

      // Watchdog: if the connection stays open but frames stop arriving
      // (e.g. rpicam-vid died on the Pi side, or Wi-Fi dropped mid-stream),
      // flag it as an error instead of freezing on the last frame forever.
      _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
        if (DateTime.now().difference(_lastFrameAt) > _staleFrameTimeout) {
          _fail();
        }
      });

    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    _watchdog?.cancel();
    _reportConnected(false);
    if (mounted) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _onChunk(List<int> chunk) {
    _buffer.addAll(chunk);

    // Pull out every complete JPEG frame currently sitting in the buffer.
    while (true) {
      final start = _indexOfMarker(_buffer, 0xFF, 0xD8, 0);
      if (start == -1) {
        // No frame start found yet. Keep at most the trailing byte in case
        // it's a split 0xFF that completes with 0xD8 on the next chunk.
        if (_buffer.length > 1) {
          final last = _buffer.last;
          _buffer
            ..clear()
            ..add(last);
        }
        return;
      }
      final end = _indexOfMarker(_buffer, 0xFF, 0xD9, start + 2);
      if (end == -1) {
        // Frame start found but not finished yet; drop any garbage before it
        // and wait for more chunks to complete it.
        if (start > 0) _buffer.removeRange(0, start);
        return;
      }

      final frame = Uint8List.fromList(_buffer.sublist(start, end + 2));
      _buffer.removeRange(0, end + 2);
      _lastFrameAt = DateTime.now();
      _reportConnected(true);

      if (mounted) {
        setState(() {
          _currentFrame = frame;
          _hasError = false;
        });
      }
    }
  }

  int _indexOfMarker(List<int> data, int b0, int b1, int from) {
    for (int i = from; i < data.length - 1; i++) {
      if (data[i] == b0 && data[i + 1] == b1) return i;
    }
    return -1;
  }

  void _retry() => _connect();

  /// Unlike [_retry] (only reachable once the stream has already failed
  /// and shows the error placeholder), this is always available in the
  /// header — for forcing a fresh connection when the feed is technically
  /// "connected" but frozen on a stale frame, not just when it's visibly
  /// broken.
  Future<void> _handleManualRestart() async {
    setState(() => _isManualRestarting = true);
    await _connect();
    if (mounted) setState(() => _isManualRestarting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.videocam_rounded, color: Colors.red, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Live Feed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const Spacer(),
                SensorRestartButton(
                  isRestarting: _isManualRestarting,
                  onPressed: _handleManualRestart,
                ),
                IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: Icon(_isExpanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: AspectRatio(
              aspectRatio: _isExpanded ? 4 / 3 : 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black),
                  if (ApiConstants.useMockData)
                    const _CameraDemoPlaceholder()
                  else if (_hasError)
                    _CameraErrorPlaceholder(onRetry: _retry)
                  else if (_currentFrame != null)
                    Image.memory(
                      _currentFrame!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  else
                    const _CameraConnectingPlaceholder(),
                  if (!_hasError && _currentFrame != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 8),
                            SizedBox(width: 4),
                            Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraConnectingPlaceholder extends StatelessWidget {
  const _CameraConnectingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54),
        ),
      ),
    );
  }
}

class _CameraErrorPlaceholder extends StatelessWidget {
  final VoidCallback onRetry;
  const _CameraErrorPlaceholder({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_rounded, color: Colors.white.withValues(alpha: 0.5), size: 48),
          const SizedBox(height: 12),
          Text(
            "Connecting to stream...",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Retry"),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _CameraDemoPlaceholder extends StatelessWidget {
  const _CameraDemoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Text(
          'Camera unavailable in demo mode',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}
