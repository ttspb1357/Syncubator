import 'package:flutter/foundation.dart' show kIsWeb;

/// Central place for all Raspberry Pi / Flask API configuration.
class ApiConstants {
  ApiConstants._();

  /// When true, all services return fake/simulated data instead of
  /// hitting the network.
  /// Override with `--dart-define=USE_MOCK_DATA=false` for a hardware build.
  static const bool useMockData = bool.fromEnvironment(
    'USE_MOCK_DATA',
    defaultValue: true,
  );

  /// Compile-time override for the API origin. Native builds default to the
  /// Pi's LAN address. On web, pass an EMPTY value
  /// (`--dart-define=API_BASE_URL=`) to use the origin the page was loaded
  /// from, so one build works on the kiosk (https://127.0.0.1) and on the
  /// public site (https://syncubator.in) without rebuilding.
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://192.168.0.116',
  );

  static String get baseUrl {
    if (kIsWeb && _configuredBaseUrl.isEmpty) return Uri.base.origin;
    return _configuredBaseUrl;
  }

  /// True only when this build is the web app running inside the Pi's own
  /// kiosk Chromium (it loads https://127.0.0.1). The public site
  /// (syncubator.in) and the Android app are the same code, but kiosk-only
  /// actions such as "exit to desktop" must not be offered there: they act
  /// on the incubator's physical screen, not on the device in your hand.
  static bool get isKioskDisplay {
    if (!kIsWeb) return false;
    final host = Uri.base.host;
    return host == '127.0.0.1' || host == 'localhost';
  }

  static String get statusEndpoint => '$baseUrl/status';
  static String get weightTareEndpoint => '$baseUrl/weight/tare';
  static String get weightRestartEndpoint => '$baseUrl/weight/restart';
  static String get climateSettingsEndpoint => '$baseUrl/climate/settings';
  static String get climateRestartEndpoint => '$baseUrl/climate/restart';
  static String get bedMoveEndpoint => '$baseUrl/bed/move';
  static String get lidMoveEndpoint => '$baseUrl/lid/move';
  static String get photoEndpoint => '$baseUrl/photo';
  static String get bedRestartEndpoint => '$baseUrl/bed/restart';
  static String get oxygenLevelEndpoint => '$baseUrl/oxygen/level';
  static String get oxygenRestartEndpoint => '$baseUrl/oxygen/restart';
  static String get oxygenSettingsEndpoint => '$baseUrl/oxygen/settings';
  static String get spo2SettingsEndpoint => '$baseUrl/spo2/settings';
  static String get skinSettingsEndpoint => '$baseUrl/skin/settings';
  static String get systemExitKioskEndpoint => '$baseUrl/system/exit_kiosk';

  /// Alarm state itself is read from [statusEndpoint]'s `alarms` key, the
  /// same way climate/oxygen/bed are — these two are only for acting on
  /// alarms rather than reading them.
  static String get alarmsAcknowledgeEndpoint => '$baseUrl/alarms/acknowledge';
  static String get alarmsLimitsEndpoint => '$baseUrl/alarms/limits';

  /// Raise or cancel SOS. Its state is read from [statusEndpoint]'s `sos` key.
  static String get sosEndpoint => '$baseUrl/sos';

  /// Frame rate requested from /video_feed when not on the kiosk (see
  /// CameraStreamCard). 5 fps at 640x480 is roughly 0.8 Mbit/s.
  static const int remoteCameraFps = 5;

  /// How often the app polls for a fresh reading.
  static const Duration pollInterval = Duration(seconds: 1);

  /// How long to wait before considering the Pi unreachable. 3 s was fine on
  /// the LAN but too tight for the public site, where each request goes
  /// browser -> Cloudflare -> tunnel -> Pi and back.
  static const Duration requestTimeout = Duration(seconds: 8);
}
