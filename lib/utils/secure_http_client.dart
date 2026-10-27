import 'dart:async';
import 'package:http/http.dart' as http;

import 'secure_http_client_io.dart'
  if (dart.library.html) 'secure_http_client_web.dart';

/// Provides the shared HTTP client for JSON requests and the MJPEG stream.
/// Native builds pin the Pi certificate; web builds use the browser client.
///
class SecureHttpClient {
  SecureHttpClient._();

  static http.Client? _client;
  static Completer<http.Client>? _initializing;

  /// Call this once, early in main(), before runApp(). Awaiting this in
  /// main() guarantees the client is ready before any screen tries to use
  /// SecureHttpClient.instance.
  static Future<void> init() async {
    if (_client != null) return;
    if (_initializing != null) {
      await _initializing!.future;
      return;
    }
    _initializing = Completer<http.Client>();
    await initializePlatformClient(_initializing!);
    _client = await _initializing!.future;
  }

  /// The shared trusted client. Throws a clear error if init() wasn't
  /// awaited first, rather than silently falling back to an untrusted
  /// client that would just fail TLS validation anyway.
  static http.Client get instance {
    final client = _client;
    if (client == null) {
      throw StateError(
        'SecureHttpClient.init() must be awaited in main() before '
            'SecureHttpClient.instance is used anywhere in the app.',
      );
    }
    return client;
  }
}