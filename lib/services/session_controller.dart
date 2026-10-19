import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/auth_result.dart';
import '../models/employee.dart';
import 'auth_service.dart';

/// Holds the signed-in employee and notifies the app when it changes.
class SessionController extends ChangeNotifier {
  SessionController(this._auth);

  final AuthService _auth;

  Employee? _employee;
  MfaChallenge? _challenge;
  bool _isBusy = false;
  bool _isProvisional = false;
  bool _isDefaultPassword = false;
  Timer? _expiryTimer;

  Employee? get employee => _employee;
  MfaChallenge? get challenge => _challenge;
  bool get isSignedIn => _employee != null;
  bool get isMock => _auth.isMock;
  bool get isBusy => _isBusy;
  bool get isProvisional => _isProvisional;
  bool get isDefaultPassword => _isDefaultPassword;

  Future<void> restoreSession() async {
    if (_isBusy) return;
    _setBusy(true);
    try {
      final restored = await _auth.restoreSession();
      if (restored != null) _accept(restored);
    } finally {
      _setBusy(false);
    }
  }

  /// Throws [AuthException] with a user-facing message on failure.
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) async {
    _beginOperation();
    try {
      final result = await _auth.signIn(
        employeeNumber: employeeNumber,
        password: password,
      );
      switch (result) {
        case AuthenticatedSession():
          _accept(result);
        case MfaChallenge():
          _employee = null;
          _challenge = result;
          _isProvisional = false;
          notifyListeners();
      }
      return result;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> verifyMfa(String code) async {
    final pending = _challenge;
    if (pending == null) {
      throw const AuthException('Your sign-in expired. Please log in again.');
    }
    _beginOperation();
    try {
      _accept(await _auth.verifyMfa(challenge: pending, code: code));
    } on AuthException catch (error) {
      if (error.restart || error.sessionInvalid) cancelMfa();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> resendMfa() async {
    final pending = _challenge;
    if (pending == null) {
      throw const AuthException('Your sign-in expired. Please log in again.');
    }
    _beginOperation();
    try {
      _challenge = await _auth.resendMfa(pending);
      notifyListeners();
    } on AuthException catch (error) {
      if (error.restart || error.sessionInvalid) cancelMfa();
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void cancelMfa() {
    _challenge = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } finally {
      clearSession();
    }
  }

  /// Clears in-memory state after local logout has already removed credentials.
  void clearSession() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _employee = null;
    _challenge = null;
    _isProvisional = false;
    _isDefaultPassword = false;
    notifyListeners();
  }

  /// Used when an approved protected request reports `SESSION_INVALID`, an
  /// unauthorized response, or an invalid token.
  Future<void> invalidateSession() async {
    try {
      await _auth.clearCredentials();
    } finally {
      clearSession();
    }
  }

  /// Records that the active restored session succeeded on the backend.
  /// Token ownership is checked by the authenticated client before this is
  /// called, so an older request cannot validate a newer session.
  void markServerValidated() {
    if (_employee == null || !_isProvisional) return;
    _isProvisional = false;
    notifyListeners();
  }

  void _accept(AuthenticatedSession session) {
    _employee = session.employee;
    _challenge = null;
    _isProvisional = session.isProvisional;
    _isDefaultPassword = session.isDefaultPassword;
    _scheduleExpiry(session.expiresAt);
    notifyListeners();
  }

  void _scheduleExpiry(DateTime? expiresAt) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      _expireLocalSession();
      return;
    }
    _expiryTimer = Timer(remaining, _expireLocalSession);
  }

  Future<void> _expireLocalSession() async {
    await invalidateSession();
  }

  void _beginOperation() {
    if (_isBusy) {
      throw const AuthException(
        'An authentication request is already in progress.',
      );
    }
    _setBusy(true);
  }

  void _setBusy(bool value) {
    if (_isBusy == value) return;
    _isBusy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
