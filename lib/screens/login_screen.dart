import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../mock/mock_data.dart';
import '../models/auth_result.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Sign-in screen. Labels, hints and messages follow web `Login.jsx`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeNumber = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  final _passwordFocus = FocusNode();
  final _otpFocus = FocusNode();

  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  String? _dashWarning;
  DateTime? _loginBlockedUntil;
  DateTime? _resendBlockedUntil;
  Timer? _ticker;

  @override
  void dispose() {
    _employeeNumber.dispose();
    _password.dispose();
    _otp.dispose();
    _passwordFocus.dispose();
    _otpFocus.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    if (!valid) {
      setState(() => _error = 'Please fill all credentials');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppScope.of(context).session.signIn(
        employeeNumber: _employeeNumber.text,
        password: _password.text,
      );
      if (result is MfaChallenge && mounted) {
        _password.clear();
        _otp.clear();
        _startTicker();
        _otpFocus.requestFocus();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loginBlockedUntil = _until(e.retryAfterSeconds);
        });
        if (e.retryAfterSeconds != null) _startTicker();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppScope.of(context).session.verifyMfa(_otp.text);
      _otp.clear();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.restart) _loginBlockedUntil = _until(e.retryAfterSeconds);
        });
        if (e.retryAfterSeconds != null) _startTicker();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppScope.of(context).session.resendMfa();
      if (mounted) {
        setState(() => _resendBlockedUntil = null);
        _startTicker();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _resendBlockedUntil = _until(e.retryAfterSeconds);
        });
        if (e.retryAfterSeconds != null) _startTicker();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _backToLogin() {
    AppScope.of(context).session.cancelMfa();
    _otp.clear();
    setState(() {
      _error = null;
      _resendBlockedUntil = null;
    });
  }

  DateTime? _until(int? seconds) => seconds == null || seconds <= 0
      ? null
      : DateTime.now().add(Duration(seconds: seconds));

  int _remaining(DateTime? until) {
    if (until == null) return 0;
    final seconds = until.difference(DateTime.now()).inSeconds;
    return seconds < 0 ? 0 : seconds + 1;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  void _useSampleAccount(String employeeNumber) {
    setState(() {
      _employeeNumber.text = employeeNumber;
      _error = null;
      _dashWarning = null;
    });
    _passwordFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final isMock = session.isMock;
    final challenge = session.challenge;
    final loginWait = _remaining(_loginBlockedUntil);
    final resendWait = _remaining(_resendBlockedUntil);
    final size = MediaQuery.sizeOf(context);
    // Short screens (small phones, landscape) get a smaller logo and tighter
    // spacing so the form starts higher up.
    final short = size.height < 640;
    final logo = short ? 72.0 : 104.0;
    final gap = short ? AppSpacing.lg : AppSpacing.xl;
    final side = size.width < 360 ? AppSpacing.lg : AppSpacing.xl;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(horizontal: side, vertical: gap),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isMock) ...[
                        const MockNotice(
                          message:
                              'Development mode: sign-in is simulated. Credentials are '
                              'not checked by the HRIS and all data is fictional.',
                        ),
                        SizedBox(height: gap),
                      ],
                      Center(child: HrisLogo(size: logo)),
                      const SizedBox(height: AppSpacing.lg),
                      const _Header(),
                      SizedBox(height: gap),
                      if (challenge == null) ...[
                        const _FieldLabel('Employee Number'),
                        TextFormField(
                          controller: _employeeNumber,
                          enabled: !_loading,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.characters,
                          autofillHints: const [AutofillHints.username],
                          inputFormatters: [
                            // Login.jsx: letters and digits only, upper-case, max 20.
                            FilteringTextInputFormatter.allow(
                              RegExp('[0-9A-Za-z-]'),
                            ),
                            _DashRemover(onDash: _onDash),
                            _UpperCase(),
                            LengthLimitingTextInputFormatter(20),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'Enter your employee number',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your employee number'
                              : null,
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
                        ),
                        if (_dashWarning != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _dashWarning!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.errorFg,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        const _FieldLabel('Password'),
                        TextFormField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          enabled: !_loading,
                          obscureText: _obscurePassword,
                          enableSuggestions: false,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your password'
                              : null,
                          onFieldSubmitted: (_) => _signIn(),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Default password must be entered in ALL CAPS with NO SPACES.',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Color(0x73800020),
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'Enter the verification code sent to',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          challenge.maskedEmail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.crimsonDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _FieldLabel('Verification Code'),
                        TextFormField(
                          key: const ValueKey('otp'),
                          controller: _otp,
                          focusNode: _otpFocus,
                          enabled: !_loading,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'Enter 6-digit code',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                          ),
                          validator: (v) => v == null || v.length != 6
                              ? 'Enter the 6-digit verification code'
                              : null,
                          onFieldSubmitted: (_) => _verifyCode(),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _remaining(challenge.codeExpiresAt) > 0
                              ? 'Code expires in ${_durationLabel(_remaining(challenge.codeExpiresAt))}'
                              : 'Code expired. Request a new one.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (_error != null) ...[
                        _ErrorBox(message: _error!),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      FilledButton.icon(
                        onPressed:
                            _loading || (challenge == null && loginWait > 0)
                            ? null
                            : challenge == null
                            ? _signIn
                            : _verifyCode,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                challenge == null
                                    ? Icons.login
                                    : Icons.verified,
                              ),
                        label: Text(
                          _loading
                              ? challenge == null
                                    ? 'Signing in…'
                                    : 'Verifying…'
                              : challenge == null
                              ? loginWait > 0
                                    ? 'Try again in ${_durationLabel(loginWait)}'
                                    : 'Sign In'
                              : 'Verify Code',
                        ),
                      ),
                      if (challenge != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(
                          onPressed: _loading || resendWait > 0
                              ? null
                              : _resendCode,
                          child: Text(
                            resendWait > 0
                                ? 'Resend in ${_durationLabel(resendWait)}'
                                : 'Resend code',
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _backToLogin,
                          child: const Text('Back to sign in'),
                        ),
                      ],
                      if (isMock && challenge == null) ...[
                        SizedBox(height: gap),
                        _SampleAccounts(
                          enabled: !_loading,
                          onSelected: _useSampleAccount,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onDash(bool hadDash) {
    final warning = hadDash
        ? 'Hyphens (dashes) are not allowed in the employee number.'
        : null;
    if (warning != _dashWarning) setState(() => _dashWarning = warning);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'WELCOME BACK',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            color: AppColors.crimson.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Human Resources\nInformation System',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: AppColors.crimsonDark,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: 44,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [AppColors.crimson, Color(0xFFE84A4A)],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: Color(0x8C4B0000),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.errorFg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.errorFg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Development-only list of fictional accounts, one per demonstrated case.
class _SampleAccounts extends StatelessWidget {
  const _SampleAccounts({required this.enabled, required this.onSelected});

  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'SAMPLE ACCOUNTS (MOCK)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.noticeFg,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap an account to fill in its employee number, then enter any password.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            for (final account in mockAccounts)
              ListTile(
                enabled: enabled,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.accentFaint,
                  child: Text(
                    account.employee.initials,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                title: Text(
                  '${account.employee.employeeNumber} · ${account.employee.role.value}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(account.description),
                onTap: () => onSelected(account.employee.employeeNumber),
              ),
          ],
        ),
      ),
    );
  }
}

/// Removes hyphens and reports whether the last edit contained one,
/// like `handleEmployeeNumberChange` in Login.jsx.
class _DashRemover extends TextInputFormatter {
  _DashRemover({required this.onDash});

  final ValueChanged<bool> onDash;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final hadDash = newValue.text.contains('-');
    WidgetsBinding.instance.addPostFrameCallback((_) => onDash(hadDash));
    if (!hadDash) return newValue;
    final text = newValue.text.replaceAll('-', '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
