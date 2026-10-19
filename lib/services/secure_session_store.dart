import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/employee.dart';

class StoredSession {
  const StoredSession({
    required this.token,
    required this.employee,
    required this.isDefaultPassword,
  });

  final String token;
  final Employee employee;
  final bool isDefaultPassword;
}

abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'hrismob.auth.session.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) throw const FormatException();
      final json = value.map((key, value) => MapEntry(key.toString(), value));
      final token = json['token'];
      final employeeJson = json['employee'];
      if (token is! String || token.isEmpty || employeeJson is! Map) {
        throw const FormatException();
      }
      return StoredSession(
        token: token,
        employee: Employee.fromStoredJson(
          employeeJson.map((key, value) => MapEntry(key.toString(), value)),
        ),
        isDefaultPassword: json['isDefaultPassword'] == true,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) => _storage.write(
    key: _key,
    value: jsonEncode({
      'token': session.token,
      'employee': session.employee.toStoredJson(),
      'isDefaultPassword': session.isDefaultPassword,
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
