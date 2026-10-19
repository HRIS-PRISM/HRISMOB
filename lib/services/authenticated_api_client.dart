import 'api_client.dart';
import 'secure_session_store.dart';
import 'session_controller.dart';

class ProtectedApiException implements Exception {
  const ProtectedApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds the active bearer token and coordinates protected-response session
/// state without exposing credentials to feature repositories.
class AuthenticatedApiClient {
  AuthenticatedApiClient(this._client, this._store, this._session);

  final ApiClient _client;
  final SessionStore _store;
  final SessionController _session;

  Future<ApiResponse> get(
    String path, {
    Map<String, String> query = const {},
  }) =>
      _request((token) => _client.get(path, query: query, bearerToken: token));

  /// Authenticated JSON POST for approved read-only feature endpoints.
  Future<ApiResponse> post(
    String path, {
    Map<String, Object?> body = const {},
  }) => _request((token) => _client.post(path, body: body, bearerToken: token));

  Future<ApiResponse> _request(
    Future<ApiResponse> Function(String token) send,
  ) async {
    final captured = await _store.read();
    if (captured == null || captured.token.isEmpty) {
      await _session.invalidateSession();
      throw const ProtectedApiException(
        'Your session has expired. Please sign in again.',
      );
    }

    final ApiResponse response;
    try {
      response = await send(captured.token);
    } on ApiNetworkException catch (error) {
      throw ProtectedApiException(error.message);
    }

    final stillCurrent = (await _store.read())?.token == captured.token;
    if (_isInvalidSession(response)) {
      if (stillCurrent) await _session.invalidateSession();
      throw const ProtectedApiException(
        'Your session has expired. Please sign in again.',
      );
    }
    if (!response.isSuccessful) {
      throw const ProtectedApiException(
        'HRIS data is unavailable. Please try again.',
      );
    }
    if (stillCurrent) _session.markServerValidated();
    return response;
  }

  static bool _isInvalidSession(ApiResponse response) {
    if (response.body['code'] == 'SESSION_INVALID' ||
        response.statusCode == 401) {
      return true;
    }
    final error = response.body['error'];
    return response.statusCode == 403 &&
        error is String &&
        error.trim().toLowerCase() == 'invalid token';
  }
}
