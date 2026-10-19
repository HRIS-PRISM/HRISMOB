import 'package:flutter/foundation.dart';

enum AuthMode { mock, real }

/// Build-time configuration for the app.
///
/// Values are supplied with `--dart-define` so no server address is
/// hard-coded in source. Examples:
///
/// ```sh
/// # Android emulator (backend on this PC)
/// flutter run --dart-define=AUTH_MODE=real \
///   --dart-define=API_BASE_URL=http://10.0.2.2:5000 \
///   --dart-define=ALLOW_INSECURE_HTTP=true
///
/// # Physical device on the same LAN
/// flutter run --dart-define=API_BASE_URL=http://<pc-lan-ip>:5000
/// ```
///
/// Production must use HTTPS.
class AppConfig {
  const AppConfig._();

  /// Base URL of the existing HRIS Node.js API. Empty when not provided.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String _authMode = String.fromEnvironment(
    'AUTH_MODE',
    defaultValue: 'mock',
  );
  static const bool allowInsecureHttp = bool.fromEnvironment(
    'ALLOW_INSECURE_HTTP',
  );

  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;

  static AuthMode get authMode {
    final mode = switch (_authMode.trim().toLowerCase()) {
      'mock' => AuthMode.mock,
      'real' => AuthMode.real,
      _ => throw StateError('AUTH_MODE must be either mock or real.'),
    };
    if (kReleaseMode && mode != AuthMode.real) {
      throw StateError('Release builds require AUTH_MODE=real.');
    }
    return mode;
  }

  static Uri get validatedApiBaseUri {
    if (!hasApiBaseUrl) {
      throw StateError('Real authentication requires API_BASE_URL.');
    }
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw StateError('API_BASE_URL must be an absolute HTTP(S) URL.');
    }
    if (kReleaseMode && uri.scheme.toLowerCase() != 'https') {
      throw StateError('Release builds require an HTTPS API_BASE_URL.');
    }
    if (!kReleaseMode &&
        uri.scheme.toLowerCase() == 'http' &&
        !allowInsecureHttp) {
      throw StateError('Development HTTP requires ALLOW_INSECURE_HTTP=true.');
    }
    return uri;
  }
}
