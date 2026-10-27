import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:syncubator/utils/secure_http_client.dart';
import '../utils/api_constants.dart';

/// Thrown when the Pi is unreachable (network error, timeout, refused
/// connection). The UI layer uses this to show an "offline" state
/// instead of a generic error.
class DeviceUnreachableException implements Exception {
  final String message;
  DeviceUnreachableException(this.message);

  @override
  String toString() => message;
}

/// Thrown when the Pi responds, but with a non-200 status or a body
/// that doesn't parse as expected.
class ApiResponseException implements Exception {
  final String message;
  ApiResponseException(this.message);

  @override
  String toString() => message;
}

/// Generic HTTP helper shared by all feature-specific services
/// (WeightService now, SensorService/BedService/DeviceService later).
class ApiService {
  final http.Client _client;
  final bool _ownsClient;

  ApiService({http.Client? client})
    : _client = client ??
      (ApiConstants.useMockData ? http.Client() : SecureHttpClient.instance),
      _ownsClient = client != null || ApiConstants.useMockData;

  /// Browsers serialise concurrent GETs to the *same* URL behind a single
  /// HTTP-cache entry lock: the second /status waits until the first has
  /// completed. Five providers polling /status at ~6 req/s through a
  /// ~0.5 s round trip (the public site) can only drain ~2 req/s that way,
  /// so the queue and the latency grow without bound and every poll ends
  /// up timing out. A per-request timestamp gives each poll its own URL, so
  /// they run in parallel. Native builds have no such cache; leave the URL
  /// untouched there.
  static Uri _pollUri(String url) {
    final uri = Uri.parse(url);
    if (!kIsWeb) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      '_': DateTime.now().microsecondsSinceEpoch.toString(),
    });
  }

  Future<Map<String, dynamic>> getJson(String url) async {
    try {
      final response = await _client
          .get(_pollUri(url))
          .timeout(ApiConstants.requestTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiResponseException(
        'Unexpected response (${response.statusCode}) from $url',
      );
    } on http.ClientException catch (e) {
      throw DeviceUnreachableException('Could not reach device: $e');
    } on Exception catch (e) {
      // Catches TimeoutException and SocketException-style failures too.
      if (e is ApiResponseException) rethrow;
      throw DeviceUnreachableException('Could not reach device: $e');
    }
  }

  Future<Map<String, dynamic>> postJson(
      String url, {
        Map<String, dynamic>? body,
      }) async {
    try {
      final response = await _client
          .post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      )
          .timeout(ApiConstants.requestTimeout);

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiResponseException(
        'Unexpected response (${response.statusCode}) from $url',
      );
    } on http.ClientException catch (e) {
      throw DeviceUnreachableException('Could not reach device: $e');
    } on Exception catch (e) {
      if (e is ApiResponseException) rethrow;
      throw DeviceUnreachableException('Could not reach device: $e');
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
