import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'mock/mock_services.dart';
import 'services/api_auth_service.dart';
import 'services/api_client.dart';
import 'services/authenticated_api_client.dart';
import 'services/auth_service.dart';
import 'services/hris_repository.dart';
import 'services/hybrid_hris_repository.dart';
import 'services/secure_session_store.dart';
import 'services/session_controller.dart';
import 'services/upload_image_url_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AuthService auth;
  final HrisRepository repository;
  switch (AppConfig.authMode) {
    case AuthMode.mock:
      auth = MockAuthService();
      repository = MockHrisRepository();
    case AuthMode.real:
      final apiClient = ApiClient(AppConfig.validatedApiBaseUri);
      final store = SecureSessionStore();
      auth = ApiAuthService(apiClient, store);
      final session = SessionController(auth);
      await session.restoreSession();
      repository = HybridHrisRepository(
        mockRepository: MockHrisRepository(),
        api: AuthenticatedApiClient(apiClient, store, session),
        imageUrls: UploadImageUrlResolver(AppConfig.validatedApiBaseUri),
      );
      runApp(HrisMobileApp(session: session, repository: repository));
      return;
  }
  final session = SessionController(auth);
  await session.restoreSession();

  runApp(HrisMobileApp(session: session, repository: repository));
}
