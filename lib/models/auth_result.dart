import 'employee.dart';

sealed class AuthResult {
  const AuthResult();
}

class AuthenticatedSession extends AuthResult {
  const AuthenticatedSession({
    required this.employee,
    this.isDefaultPassword = false,
    this.isProvisional = false,
    this.expiresAt,
  });

  final Employee employee;
  final bool isDefaultPassword;

  /// A restored token has passed only local structural/expiry checks. The
  /// backend has not confirmed that its server-side session row is active.
  final bool isProvisional;

  /// Local expiry metadata limits token use but is not proof that the backend
  /// session is active. Mock sessions intentionally have no expiry.
  final DateTime? expiresAt;
}

class MfaChallenge extends AuthResult {
  const MfaChallenge({
    required this.challengeId,
    required this.maskedEmail,
    required this.codeExpiresAt,
  });

  final String challengeId;
  final String maskedEmail;
  final DateTime codeExpiresAt;

  MfaChallenge refreshed({required Duration codeLifetime}) => MfaChallenge(
    challengeId: challengeId,
    maskedEmail: maskedEmail,
    codeExpiresAt: DateTime.now().add(codeLifetime),
  );
}
