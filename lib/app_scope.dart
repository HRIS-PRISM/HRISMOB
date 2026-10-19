import 'package:flutter/widgets.dart';

import 'services/hris_repository.dart';
import 'services/session_controller.dart';

/// Makes the session and the data repository available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.repository,
    required super.child,
  });

  final SessionController session;
  final HrisRepository repository;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      session != oldWidget.session || repository != oldWidget.repository;
}
