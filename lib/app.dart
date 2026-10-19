import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/hris_repository.dart';
import 'services/session_controller.dart';
import 'theme/app_theme.dart';
import 'theme/responsive.dart';

class HrisMobileApp extends StatelessWidget {
  const HrisMobileApp({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final HrisRepository repository;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: session,
      repository: repository,
      child: MaterialApp(
        title: 'HRIS Mobile',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // Honour the system font size up to the largest scale the layouts
        // are designed and tested for.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: Responsive.maxTextScale,
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final employee = session.employee;
            // Keyed by employee so nothing from a previous session is reused.
            return employee == null
                ? const LoginScreen()
                : HomeShell(
                    key: ValueKey(employee.employeeNumber),
                    employee: employee,
                  );
          },
        ),
      ),
    );
  }
}
