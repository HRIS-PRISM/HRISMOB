import '../models/auth_result.dart';

/// Signs employees in and out.
///
/// Phase 3 uses `MockAuthService`. The real implementation must go through
/// the existing HRIS backend, which alone decides whether credentials, OTP,
/// role and page access are valid.
abstract class AuthService {
  /// True when sign-in is simulated and nothing is checked by the HRIS.
  bool get isMock;

  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  });

  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  });

  Future<MfaChallenge> resendMfa(MfaChallenge challenge);

  /// Restores local credentials without claiming server-side validity.
  Future<AuthenticatedSession?> restoreSession();

  /// Deletes local credentials without making a backend request.
  Future<void> clearCredentials();

  Future<void> signOut();
}

/// Sign-in failure with a message that is safe to show the user.
class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
    this.attemptsLeft,
    this.restart = false,
    this.sessionInvalid = false,
  });

  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  final int? attemptsLeft;
  final bool restart;
  final bool sessionInvalid;

  @override
  String toString() => message;
}
