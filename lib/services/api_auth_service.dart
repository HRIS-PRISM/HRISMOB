import 'dart:convert';

import '../models/auth_result.dart';
import '../models/employee.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'secure_session_store.dart';

class ApiAuthService implements AuthService {
  ApiAuthService(this._client, this._store);

  final ApiClient _client;
  final SessionStore _store;

  @override
  bool get isMock => false;

  @override
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) async {
    final response = await _post('/login', {
      'employeeNumber': employeeNumber.trim(),
      'password': password,
    });
    if (!response.isSuccessful) throw _errorFrom(response);

    try {
      if (response.body['mfaRequired'] == true) {
        final challengeId = _requiredString(response.body, 'challengeId');
        final maskedEmail = _requiredString(response.body, 'maskedEmail');
        final lifetime = _positiveSeconds(response.body, 'codeExpiresIn');
        return MfaChallenge(
          challengeId: challengeId,
          maskedEmail: maskedEmail,
          codeExpiresAt: DateTime.now().add(lifetime),
        );
      }
      return await _saveCompletedSession(response.body);
    } on FormatException {
      throw const AuthException(
        'The server returned an incomplete sign-in response.',
      );
    }
  }

  @override
  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  }) async {
    final response = await _post('/verify-2fa-code', {
      'challengeId': challenge.challengeId,
      'code': code.trim(),
    });
    if (!response.isSuccessful) throw _errorFrom(response);
    if (response.body['verified'] != true) {
      throw const AuthException('The server did not confirm verification.');
    }
    return _saveCompletedSession(response.body);
  }

  @override
  Future<MfaChallenge> resendMfa(MfaChallenge challenge) async {
    final response = await _post('/send-2fa-code', {
      'challengeId': challenge.challengeId,
    });
    if (!response.isSuccessful) {
      final error = _errorFrom(response);
      // The backend deletes an expired challenge (400) and a challenge that
      // exhausted its send allowance (429 without a cooldown). Those resend
      // responses do not include `restart`, but retrying the same ID cannot
      // succeed and must return the user to password sign-in.
      if (response.statusCode == 400 ||
          (response.statusCode == 429 && error.retryAfterSeconds == null)) {
        throw AuthException(
          error.message,
          statusCode: error.statusCode,
          retryAfterSeconds: error.retryAfterSeconds,
          attemptsLeft: error.attemptsLeft,
          restart: true,
          sessionInvalid: error.sessionInvalid,
        );
      }
      throw error;
    }
    try {
      return challenge.refreshed(
        codeLifetime: _positiveSeconds(response.body, 'codeExpiresIn'),
      );
    } on FormatException {
      throw const AuthException(
        'The server returned an incomplete resend response.',
      );
    }
  }

  @override
  Future<AuthenticatedSession?> restoreSession() async {
    final stored = await _store.read();
    if (stored == null) return null;
    final expiresAt = _jwtExpiry(stored.token);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      await _store.clear();
      return null;
    }
    return AuthenticatedSession(
      employee: stored.employee,
      isDefaultPassword: stored.isDefaultPassword,
      isProvisional: true,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> clearCredentials() => _store.clear();

  @override
  Future<void> signOut() async {
    try {
      final stored = await _store.read();
      if (stored != null) {
        await _client.post('/logout', bearerToken: stored.token);
      }
    } catch (_) {
      // Local sign-out must succeed even when the backend cannot be reached.
    } finally {
      await _store.clear();
    }
  }

  Future<ApiResponse> _post(String path, Map<String, Object?> body) async {
    try {
      return await _client.post(path, body: body);
    } on ApiNetworkException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<AuthenticatedSession> _saveCompletedSession(
    Map<String, Object?> json,
  ) async {
    try {
      final token = _requiredString(json, 'token');
      final expiresAt = _jwtExpiry(token);
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const FormatException('Invalid token expiry');
      }
      final employee = Employee.fromAuthJson(json);
      final session = AuthenticatedSession(
        employee: employee,
        isDefaultPassword: json['isDefaultPassword'] == true,
        expiresAt: expiresAt,
      );
      await _store.write(
        StoredSession(
          token: token,
          employee: employee,
          isDefaultPassword: session.isDefaultPassword,
        ),
      );
      return session;
    } on FormatException {
      await _store.clear();
      throw const AuthException(
        'The server returned an incomplete sign-in response.',
      );
    }
  }

  static AuthException _errorFrom(ApiResponse response) {
    final body = response.body;
    final message =
        _optionalString(body['error']) ??
        _optionalString(body['message']) ??
        'Authentication failed. Please try again.';
    final headerRetry = int.tryParse(response.headers['retry-after'] ?? '');
    return AuthException(
      message,
      statusCode: response.statusCode,
      retryAfterSeconds: _optionalInt(body['retryAfter']) ?? headerRetry,
      attemptsLeft: _optionalInt(body['attemptsLeft']),
      restart: body['restart'] == true,
      sessionInvalid:
          body['code'] == 'SESSION_INVALID' ||
          response.statusCode == 401 ||
          response.statusCode == 403,
    );
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = _optionalString(json[key]);
    if (value == null) throw const FormatException();
    return value;
  }

  static Duration _positiveSeconds(Map<String, Object?> json, String key) {
    final seconds = _optionalInt(json[key]);
    if (seconds == null || seconds <= 0) throw const FormatException();
    return Duration(seconds: seconds);
  }

  static String? _optionalString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final exp = _optionalInt(payload['exp']);
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }
}
