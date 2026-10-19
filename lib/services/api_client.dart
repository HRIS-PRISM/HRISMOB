import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

class ApiNetworkException implements Exception {
  const ApiNetworkException(this.message);

  final String message;
}

/// Small JSON client for the existing HRIS backend.
///
/// It never logs request bodies or headers because authentication requests
/// contain credentials and session tokens.
class ApiClient {
  ApiClient(
    this._baseUri, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _httpClient;
  final Duration timeout;

  Future<ApiResponse> post(
    String path, {
    Map<String, Object?> body = const {},
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    };

    try {
      final response = await _httpClient
          .post(_resolve(path), headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      return ApiResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: _decodeObject(response.body),
      );
    } on TimeoutException {
      throw const ApiNetworkException(
        'The request timed out. Please try again.',
      );
    } on SocketException {
      throw const ApiNetworkException('Connection error. Please try again.');
    } on http.ClientException {
      throw const ApiNetworkException('Connection error. Please try again.');
    } on FormatException {
      throw const ApiNetworkException(
        'The server returned an invalid response.',
      );
    }
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, String> query = const {},
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    };

    try {
      final uri = _resolve(path)
          .replace(queryParameters: query.isEmpty ? null : query);
      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(timeout);
      return ApiResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: _decodeObject(response.body),
      );
    } on TimeoutException {
      throw const ApiNetworkException(
        'The request timed out. Please try again.',
      );
    } on SocketException {
      throw const ApiNetworkException('Connection error. Please try again.');
    } on http.ClientException {
      throw const ApiNetworkException('Connection error. Please try again.');
    } on FormatException {
      throw const ApiNetworkException(
        'The server returned an invalid response.',
      );
    }
  }

  Uri _resolve(String path) {
    final root = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$suffix');
  }

  static Map<String, Object?> _decodeObject(String raw) {
    if (raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Expected a JSON object');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  void close() => _httpClient.close();
}
