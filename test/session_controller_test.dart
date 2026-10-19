import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/session_controller.dart';

const _employee = Employee(
  employeeNumber: 'EMP1001',
  role: UserRole.staff,
  firstName: 'Test',
  lastName: 'Employee',
);

class _FakeAuthService implements AuthService {
  AuthResult signInResult = const AuthenticatedSession(employee: _employee);
  AuthenticatedSession verified = const AuthenticatedSession(
    employee: _employee,
  );
  AuthenticatedSession? restored;
  bool throwOnSignOut = false;
  bool credentialsCleared = false;
  Completer<AuthResult>? delayedSignIn;

  @override
  bool get isMock => false;

  @override
  Future<void> clearCredentials() async => credentialsCleared = true;

  @override
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) async => delayedSignIn?.future ?? signInResult;

  @override
  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  }) async => verified;

  @override
  Future<MfaChallenge> resendMfa(MfaChallenge challenge) async =>
      challenge.refreshed(codeLifetime: const Duration(minutes: 5));

  @override
  Future<AuthenticatedSession?> restoreSession() async => restored;

  @override
  Future<void> signOut() async {
    if (throwOnSignOut) throw StateError('offline');
  }
}

void main() {
  test('controller keeps MFA pending until verification succeeds', () async {
    final auth = _FakeAuthService()
      ..signInResult = MfaChallenge(
        challengeId: 'challenge-1',
        maskedEmail: 'e***@example.test',
        codeExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    final controller = SessionController(auth);

    await controller.signIn(employeeNumber: 'EMP1001', password: 'secret');
    expect(controller.employee, isNull);
    expect(controller.challenge?.challengeId, 'challenge-1');

    await controller.verifyMfa('123456');
    expect(controller.employee, _employee);
    expect(controller.challenge, isNull);
  });

  test('restored employee remains explicitly provisional', () async {
    final auth = _FakeAuthService()
      ..restored = const AuthenticatedSession(
        employee: _employee,
        isProvisional: true,
      );
    final controller = SessionController(auth);

    await controller.restoreSession();
    expect(controller.isSignedIn, isTrue);
    expect(controller.isProvisional, isTrue);

    controller.markServerValidated();
    expect(controller.isProvisional, isFalse);
  });

  test('server validation is ignored without an active session', () {
    final controller = SessionController(_FakeAuthService());
    controller.markServerValidated();
    expect(controller.isSignedIn, isFalse);
    expect(controller.isProvisional, isFalse);
  });

  test('duplicate authentication submissions are rejected', () async {
    final auth = _FakeAuthService()..delayedSignIn = Completer<AuthResult>();
    final controller = SessionController(auth);
    final first = controller.signIn(
      employeeNumber: 'EMP1001',
      password: 'secret',
    );

    await expectLater(
      controller.signIn(employeeNumber: 'EMP1001', password: 'secret'),
      throwsA(isA<AuthException>()),
    );
    auth.delayedSignIn!.complete(
      const AuthenticatedSession(employee: _employee),
    );
    await first;
  });

  test('logout clears controller state even when the service throws', () async {
    final auth = _FakeAuthService()..throwOnSignOut = true;
    final controller = SessionController(auth);
    await controller.signIn(employeeNumber: 'EMP1001', password: 'secret');

    await expectLater(controller.signOut(), throwsStateError);
    expect(controller.isSignedIn, isFalse);
  });

  test('server invalidation clears credentials and returns to login', () async {
    final auth = _FakeAuthService();
    final controller = SessionController(auth);
    await controller.signIn(employeeNumber: 'EMP1001', password: 'secret');

    await controller.invalidateSession();
    expect(auth.credentialsCleared, isTrue);
    expect(controller.isSignedIn, isFalse);
  });
}
