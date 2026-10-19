import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/app.dart';
import 'package:hrismob/app_scope.dart';
import 'package:hrismob/mock/mock_services.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/bulletin.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/hris_repository.dart';
import 'package:hrismob/services/session_controller.dart';
import 'package:hrismob/utils/attendance_rules.dart';
import 'package:hrismob/utils/formatters.dart';
import 'package:hrismob/widgets/home_widgets.dart';

class _WidgetMfaAuthService implements AuthService {
  @override
  bool get isMock => false;

  @override
  Future<void> clearCredentials() async {}

  @override
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) async => MfaChallenge(
    challengeId: 'challenge-1',
    maskedEmail: 'm***@example.test',
    codeExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  @override
  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  }) async {
    if (code != '123456') {
      throw const AuthException(
        'Invalid code. 4 attempts left.',
        attemptsLeft: 4,
      );
    }
    return const AuthenticatedSession(
      employee: Employee(
        employeeNumber: 'SAMPLE1001',
        role: UserRole.staff,
        pageAccess: {'attendance-user-state'},
        firstName: 'Maria',
        middleName: 'Lopez',
        lastName: 'Reyes',
      ),
    );
  }

  @override
  Future<MfaChallenge> resendMfa(MfaChallenge challenge) async =>
      challenge.refreshed(codeLifetime: const Duration(minutes: 5));

  @override
  Future<AuthenticatedSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}

class _LiveHomeRepository extends MockHrisRepository {
  _LiveHomeRepository({this.fail = false, this.empty = false})
    : super(latency: Duration.zero);

  bool fail;
  final bool empty;
  int bulletinLoads = 0;
  int invalidations = 0;

  @override
  bool get isMock => false;

  @override
  bool get homeEventsAreLive => true;

  @override
  void invalidateHomeEvents() {
    invalidations++;
    if (invalidations > 1) fail = false;
  }

  @override
  Future<List<Bulletin>> fetchBulletins() async {
    bulletinLoads++;
    if (fail) throw StateError('offline');
    if (empty) return const [];
    final now = DateTime.now();
    return [
      Bulletin(
        id: 'live-1',
        kind: BulletinKind.holiday,
        title: 'Live Institution Holiday',
        start: DateTime(now.year, now.month, now.day),
      ),
    ];
  }
}

class _ImageHomeRepository extends MockHrisRepository {
  _ImageHomeRepository(this.items) : super(latency: Duration.zero);

  final List<Bulletin> items;

  @override
  Future<List<Bulletin>> fetchBulletins() async => items;
}

final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<void> pumpImageCarousel(
  WidgetTester tester, {
  required List<Bulletin> items,
  required ImageProvider<Object> Function(Uri url) imageProviderBuilder,
  Size physicalSize = const Size(720, 1280),
  double devicePixelRatio = 2,
  double textScale = 1,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    AppScope(
      session: SessionController(MockAuthService(latency: Duration.zero)),
      repository: _ImageHomeRepository(items),
      child: MaterialApp(
        home: Scaffold(
          body: BulletinCarousel(
            key: UniqueKey(),
            emptyText: 'Empty',
            imageProviderBuilder: imageProviderBuilder,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpApp(WidgetTester tester, {HrisRepository? repository}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    HrisMobileApp(
      session: SessionController(MockAuthService(latency: Duration.zero)),
      // Fixed time of day (12:30 PM today) so "Today" results are stable.
      repository:
          repository ??
          MockHrisRepository(
            latency: Duration.zero,
            clock: () {
              final n = DateTime.now();
              return DateTime(n.year, n.month, n.day, 12, 30);
            },
          ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpMfaApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    HrisMobileApp(
      session: SessionController(_WidgetMfaAuthService()),
      repository: MockHrisRepository(latency: Duration.zero),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester, String employeeNumber) async {
  await tester.enterText(find.byType(TextFormField).at(0), employeeNumber);
  await tester.enterText(find.byType(TextFormField).at(1), 'anything');
  await tester.tap(find.text('Sign In'));
  await tester.pumpAndSettle();
}

Finder navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

String rangeText(DateRange r) =>
    '${formatIsoDate(r.start)} → ${formatIsoDate(r.end)}';

Future<void> pickQuick(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('quick')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> pickYear(WidgetTester tester, int year) async {
  await tester.tap(find.byKey(const ValueKey('year')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$year').last);
  await tester.pumpAndSettle();
}

Future<void> openFilter(WidgetTester tester) async {
  if (find.byKey(const ValueKey('search')).evaluate().isEmpty) {
    await tester.ensureVisible(find.text('Attendance Filter'));
    await tester.tap(find.text('Attendance Filter'));
    await tester.pumpAndSettle();
  }
}

Future<void> search(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('search')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('search')));
  await tester.pumpAndSettle();
}

Future<void> scrollHomeTo(WidgetTester tester, Finder target) async {
  // Drag along the page's left padding so inner scroll boxes (Time Logs)
  // don't take the gesture.
  for (var i = 0; i < 40 && target.evaluate().isEmpty; i++) {
    await tester.dragFrom(const Offset(6, 600), const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('carousel renders a validated image behind readable content', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpImageCarousel(
      tester,
      items: [
        Bulletin(
          id: 'image-1',
          kind: BulletinKind.holiday,
          title: 'Holiday With Image',
          start: DateTime(now.year, now.month, now.day),
          imageUrl: Uri.parse('https://hris.example.test/uploads/image.png'),
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('bulletin-image-image-1')),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.excludeFromSemantics, isTrue);
    expect(
      find.byKey(const ValueKey('bulletin-gradient-overlay')),
      findsOneWidget,
    );
    expect(find.text('Holiday With Image'), findsOneWidget);
    expect(find.text('HOLIDAY'), findsOneWidget);
  });

  testWidgets('missing and failed images retain the gradient and text', (
    tester,
  ) async {
    final now = DateTime.now();
    Bulletin item(String id, {Uri? imageUrl}) => Bulletin(
      id: id,
      kind: BulletinKind.suspension,
      title: 'Visible $id',
      start: DateTime(now.year, now.month, now.day),
      imageUrl: imageUrl,
    );

    await pumpImageCarousel(
      tester,
      items: [item('missing')],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
    );
    expect(find.byType(Image), findsNothing);
    expect(
      find.byKey(const ValueKey('bulletin-gradient-fallback')),
      findsOneWidget,
    );
    expect(find.text('Visible missing'), findsOneWidget);

    await pumpImageCarousel(
      tester,
      items: [
        item(
          'failed',
          imageUrl: Uri.parse('https://hris.example.test/uploads/bad.png'),
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(Uint8List.fromList([1, 2, 3])),
    );
    expect(
      find.byKey(const ValueKey('bulletin-gradient-fallback')),
      findsOneWidget,
    );
    expect(find.text('Visible failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image carousel still swipes and updates pagination', (
    tester,
  ) async {
    final now = DateTime.now();
    Bulletin item(String id, int offset) => Bulletin(
      id: id,
      kind: BulletinKind.holiday,
      title: 'Image $id',
      start: DateTime(now.year, now.month, now.day + offset),
      imageUrl: Uri.parse('https://hris.example.test/uploads/$id.png'),
    );
    await pumpImageCarousel(
      tester,
      items: [item('first', 0), item('second', 1)],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
    );
    expect(find.text('Image second'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('Image first'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('details render safe formatted text, lists, and image', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpImageCarousel(
      tester,
      items: [
        Bulletin(
          id: 'formatted-description',
          kind: BulletinKind.holiday,
          title: 'Formatted Notice',
          start: DateTime(now.year, now.month, now.day),
          imageUrl: Uri.parse(
            'https://hris.example.test/uploads/formatted.png',
          ),
          about:
              'Ordinary <b>bold <i>nested <u>combined</u></i></b><br>'
              '<ol><li>First</li><li>Second</li></ol>'
              '<ul><li>Bullet</li></ul>'
              'next &amp; safe<script>hidden</script>',
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
    );

    await tester.tap(find.text('Formatted Notice'));
    await tester.pumpAndSettle();

    final description = tester.widget<Text>(
      find.byKey(const ValueKey('bulletin-description')),
    );
    expect(
      description.textSpan!.toPlainText(),
      'Ordinary bold nested combined\n1. First\n2. Second\n• Bullet\n'
      'next & safe',
    );
    final spans = (description.textSpan! as TextSpan).children!
        .cast<TextSpan>();
    expect(
      spans.where((span) => span.style?.fontWeight == FontWeight.bold),
      isNotEmpty,
    );
    expect(
      spans.where((span) => span.style?.fontStyle == FontStyle.italic),
      isNotEmpty,
    );
    expect(
      spans.where((span) => span.style?.decoration == TextDecoration.underline),
      isNotEmpty,
    );
    expect(
      spans.where(
        (span) =>
            span.style?.fontWeight == FontWeight.bold &&
            span.style?.fontStyle == FontStyle.italic &&
            span.style?.decoration == TextDecoration.underline,
      ),
      isNotEmpty,
    );
    final detailImage = tester.widget<Image>(
      find.byKey(const ValueKey('bulletin-detail-image')),
    );
    expect(detailImage.fit, BoxFit.cover);
    expect(detailImage.excludeFromSemantics, isTrue);
    expect(
      find.byKey(const ValueKey('bulletin-detail-image-fallback')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bulletin-detail-sheet-content')))
          .width,
      360,
    );
    expect(find.textContaining('<b>'), findsNothing);
    expect(find.textContaining('hidden'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('detail image failure keeps fallback and description visible', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpImageCarousel(
      tester,
      items: [
        Bulletin(
          id: 'failed-detail-image',
          kind: BulletinKind.suspension,
          title: 'Failed Detail Image',
          start: DateTime(now.year, now.month, now.day),
          imageUrl: Uri.parse('https://hris.example.test/uploads/bad.png'),
          about: 'Still readable',
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(Uint8List.fromList([1, 2, 3])),
    );

    await tester.tap(find.text('Failed Detail Image'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bulletin-detail-image-fallback')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('bulletin-detail-sheet-content')))
          .width,
      360,
    );
    expect(find.textContaining('Still readable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail without an image omits the image area', (tester) async {
    final now = DateTime.now();
    await pumpImageCarousel(
      tester,
      items: [
        Bulletin(
          id: 'no-detail-image',
          kind: BulletinKind.holiday,
          title: 'No Detail Image',
          start: DateTime(now.year, now.month, now.day),
          about: 'A',
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
    );

    await tester.tap(find.text('No Detail Image'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bulletin-detail-image')), findsNothing);
    final description = tester.widget<Text>(
      find.byKey(const ValueKey('bulletin-description')),
    );
    expect(description.textSpan!.toPlainText(), 'A');
    final detailContent = tester.getSize(
      find.byKey(const ValueKey('bulletin-detail-sheet-content')),
    );
    expect(detailContent.width, 360);
    expect(detailContent.height, lessThan(640 * 0.85));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long description scrolls inside a bounded safe detail sheet', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpImageCarousel(
      tester,
      items: [
        Bulletin(
          id: 'long-description',
          kind: BulletinKind.suspension,
          title: 'Long Notice',
          start: DateTime(now.year, now.month, now.day),
          about: List.generate(
            80,
            (index) => 'Readable description line ${index + 1}',
          ).join('<br>'),
        ),
      ],
      imageProviderBuilder: (_) => MemoryImage(_onePixelPng),
      physicalSize: const Size(640, 1136),
      textScale: 2,
    );

    await tester.tap(find.text('Long Notice'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    final scrollView = find.descendant(
      of: sheet,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollView, findsOneWidget);
    final detailContent = tester.getSize(
      find.byKey(const ValueKey('bulletin-detail-sheet-content')),
    );
    expect(detailContent.width, 320);
    expect(detailContent.height, lessThanOrEqualTo(568 * 0.85));
    expect(find.textContaining('Readable description line 80'), findsOneWidget);
    await tester.drag(scrollView, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('login shows the web labels and the mock notice', (tester) async {
    await pumpApp(tester);
    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('EMPLOYEE NUMBER'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.textContaining('sign-in is simulated'), findsOneWidget);
  });

  testWidgets('empty sign-in shows required-field errors', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Please fill all credentials'), findsOneWidget);
    expect(find.text('Enter your employee number'), findsWidgets);
    expect(find.text('Enter your password'), findsWidgets);
  });

  testWidgets('unknown employee number is rejected', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'NOBODY');
    expect(find.text('User not found'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('employee number drops hyphens and is upper-cased', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'sample-1001');
    await tester.pump();
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText).at(0));
    expect(field.controller.text, 'SAMPLE1001');
    expect(
      find.text('Hyphens (dashes) are not allowed in the employee number.'),
      findsOneWidget,
    );
  });

  testWidgets('password visibility toggles', (tester) async {
    await pumpApp(tester);
    EditableText password() =>
        tester.widget<EditableText>(find.byType(EditableText).at(1));
    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
  });

  testWidgets('real auth UI requires MFA and handles an incorrect code', (
    tester,
  ) async {
    await pumpMfaApp(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'SAMPLE1001');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('m***@example.test'), findsOneWidget);
    expect(find.text('Verify Code'), findsOneWidget);
    expect(find.textContaining('sign-in is simulated'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('otp')), '000000');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid code. 4 attempts left.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('otp')), '123456');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Maria Lopez Reyes'), findsOneWidget);
  });

  testWidgets('staff: employee dashboard with Today card, then sign out', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');

    expect(find.text('Hello, Maria Lopez Reyes'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('TIME IN'), findsOneWidget);
    expect(find.text('OFFICIAL TIME'), findsOneWidget);
    expect(navLabel('Attendance'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.textContaining('Maria'), findsNothing);
  });

  testWidgets('pull to refresh reloads dashboard and profile without errors', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.fling(find.text('Today'), const Offset(0, 600), 1500);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('OFFICIAL TIME'), findsOneWidget);

    await tester.tap(navLabel('Profile'));
    await tester.pumpAndSettle();
    await tester.fling(
      find.text('Personal Information'),
      const Offset(0, 600),
      1500,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('First Name'), findsOneWidget);
  });

  testWidgets(
    'live Home labels mixed data and Retry reloads without fallback',
    (tester) async {
      final repository = _LiveHomeRepository(fail: true);
      await pumpApp(tester, repository: repository);
      await signIn(tester, 'SAMPLE1001');

      expect(
        find.text(
          'Holidays and suspensions are live. Attendance and Profile still use '
          'sample data. Announcements are unavailable.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Could not load holidays and suspensions.'),
        findsOneWidget,
      );
      expect(find.text('Sample Holiday'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Live Institution Holiday'), findsOneWidget);
      expect(repository.invalidations, 2);
      expect(repository.bulletinLoads, 2);
    },
  );

  testWidgets('live Home empty state and pull-to-refresh reload are explicit', (
    tester,
  ) async {
    final repository = _LiveHomeRepository(empty: true);
    await pumpApp(tester, repository: repository);
    await signIn(tester, 'SAMPLE1001');
    expect(
      find.text('No holidays or suspensions currently available.'),
      findsOneWidget,
    );

    await tester.fling(find.text('Today'), const Offset(0, 600), 1500);
    await tester.pumpAndSettle();
    expect(repository.invalidations, 2);
    expect(repository.bulletinLoads, 2);
  });

  testWidgets('staff without punches today sees "No record yet"', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1002');
    expect(find.text('No record yet'), findsOneWidget);
    expect(find.text('No official time assigned'), findsOneWidget);
  });

  // Every role gets the Home attendance card; the full Attendance page still
  // follows the web page-access rules.
  const roleCases = {
    // employee number: (Today status, may open the full Attendance page)
    'SAMPLE1001': ('Clocked in', true), // staff, granted
    'SAMPLE1002': ('No record yet', true), // staff, granted
    'SAMPLE2001': ('Clocked in', true), // administrator, granted
    'SAMPLE2002': ('No record yet', false), // administrator, not granted
    'SAMPLE3001': ('Clocked in', true), // superadmin, bypass
    'SAMPLE4001': ('No record yet', true), // technical, bypass
  };
  for (final MapEntry(key: emp, value: (status, canOpen))
      in roleCases.entries) {
    testWidgets('$emp: Home attendance card shown; full page '
        '${canOpen ? 'allowed' : 'hidden'}', (tester) async {
      await pumpApp(tester);
      await signIn(tester, emp);

      final card = find.ancestor(
        of: find.text('Today'),
        matching: find.byType(Card),
      );
      expect(card, findsOneWidget);
      expect(find.text('TIME IN'), findsOneWidget);
      expect(find.text('OFFICIAL TIME'), findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(RegExp('^($status)\$')),
        ),
        findsOneWidget,
      );
      // The card shows only the signed-in employee's own data.
      expect(find.textContaining('SAMPLE'), findsOneWidget);

      expect(navLabel('Attendance'), canOpen ? findsOneWidget : findsNothing);
      expect(
        find.descendant(
          of: card,
          matching: find.widgetWithText(TextButton, 'Attendance'),
        ),
        canOpen ? findsOneWidget : findsNothing,
      );
      // General Panel is the web sidebar menu: navigation, not a Home card.
      expect(find.text('General Panel'), findsNothing);
      if (canOpen) {
        await tester.tap(navLabel('Attendance'));
        await tester.pumpAndSettle();
        expect(find.text('My Attendance Records'), findsOneWidget);
      }
    });
  }

  testWidgets('technical: Attendance shows the web empty state', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE4001');
    expect(find.text('No record yet'), findsOneWidget);
    await tester.tap(navLabel('Attendance'));
    await tester.pumpAndSettle();
    expect(find.text('My Attendance Records'), findsOneWidget);
    expect(find.text('0 records found'), findsOneWidget);
    expect(find.text('No records found'), findsOneWidget);
    expect(find.text('Try adjusting your date range.'), findsOneWidget);
  });

  testWidgets('filter starts collapsed; choices wait for Search', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(navLabel('Attendance'));
    await tester.pumpAndSettle();

    // Collapsed by default: no controls, applied period shown.
    expect(find.byKey(const ValueKey('search')), findsNothing);
    expect(find.text('JAN'), findsNothing);
    expect(find.text(rangeText(todayRange(now))), findsWidgets);
    expect(find.text('Back to today'), findsNothing);

    // Picking a month only prepares the criteria.
    await openFilter(tester);
    final thisMonth = monthRange(now.year, now.month - 1);
    await tester.tap(find.text(monthsShort[now.month - 1]));
    await tester.pumpAndSettle();
    expect(
      find.text('Selected: ${rangeText(thisMonth)}. Tap Search to apply.'),
      findsOneWidget,
    );
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Back to today'), findsNothing); // not applied yet

    // Search applies, collapses and shows the results.
    await search(tester);
    expect(find.byKey(const ValueKey('search')), findsNothing);
    expect(find.text(rangeText(thisMonth)), findsWidgets);
    expect(find.text('Back to today'), findsOneWidget);
    expect(find.textContaining('records found'), findsOneWidget);
    expect(find.text('No records found'), findsNothing);
    expect(find.text('RECORD SUMMARY'), findsOneWidget);
  });

  testWidgets('Search across years, empty results, and Clear', (tester) async {
    final now = DateTime.now();
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(navLabel('Attendance'));
    await tester.pumpAndSettle();

    // Previous year, December (crosses the year boundary; in mock history).
    await openFilter(tester);
    await pickYear(tester, now.year - 1);
    await tester.tap(find.text('DEC'));
    await tester.pumpAndSettle();
    await search(tester);
    expect(
      find.text('${now.year - 1}-12-01 → ${now.year - 1}-12-31'),
      findsWidgets,
    );
    expect(find.text('No records found'), findsNothing);

    // Five years back: no sample data -> the web empty state.
    await openFilter(tester);
    await pickYear(tester, now.year - 5);
    await tester.tap(find.text('JAN'));
    await tester.pumpAndSettle();
    await search(tester);
    expect(find.text('0 records found'), findsOneWidget);
    expect(find.text('No records found'), findsOneWidget);
    expect(find.text('Try adjusting your date range.'), findsOneWidget);
    expect(
      find.textContaining('Sort'),
      findsNothing,
    ); // web hides sort when empty

    // Clear applies right away (web resetToToday).
    await openFilter(tester);
    await tester.tap(find.text('JAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text(rangeText(todayRange(now))), findsWidgets);
    expect(find.text('Back to today'), findsNothing);
  });

  testWidgets('Quick Dates waits for Search too', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(navLabel('Attendance'));
    await tester.pumpAndSettle();
    await openFilter(tester);
    await pickQuick(tester, 'Last 30 Days');
    final range = QuickPeriod.last30.range(DateTime.now());
    expect(
      find.textContaining('Selected: ${rangeText(range)}'),
      findsOneWidget,
    );
    await search(tester);
    expect(find.text(rangeText(range)), findsWidgets);
    expect(find.text('Breaktime Out'), findsWidgets);
  });

  testWidgets('record details use the web date format', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(navLabel('Attendance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    expect(find.text('EMPLOYEE ID'), findsOneWidget);
    expect(find.text(formatPunchDate(DateTime.now())), findsOneWidget);
  });

  testWidgets('regular staff Home: carousel, Today, My Attendance strip', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    // Newest first: the fictional holiday leads the carousel.
    expect(find.text('HOLIDAY'), findsWidgets);
    expect(find.text('Sample Holiday'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    await scrollHomeTo(tester, find.text('My Attendance'));
    expect(
      find.text('Vacation leave'),
      findsOneWidget,
    ); // regular staff keep leave codes
    expect(find.text('Time Logs'), findsNothing);
    expect(find.text('Up Next'), findsNothing);
  });

  testWidgets(
    'Job Order Home: Today, Time Logs, Up Next, calendar without leave',
    (tester) async {
      await pumpApp(tester);
      await signIn(tester, 'SAMPLE1002');
      expect(find.text('No record yet'), findsOneWidget);
      await scrollHomeTo(tester, find.text('Time Logs'));
      expect(find.text('View all'), findsOneWidget);
      await scrollHomeTo(tester, find.text('Up Next'));
      expect(find.text('in 3d'), findsOneWidget); // fictional announcement
      expect(find.text('Sample: Expired announcement'), findsNothing);
      await scrollHomeTo(tester, find.text('MON'));
      expect(find.text('My Attendance'), findsOneWidget);
      expect(find.text('Vacation leave'), findsNothing); // hideLeave
    },
  );

  testWidgets('admin Home: carousel and Today only (no staff widgets)', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE3001');
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sample Holiday'), findsWidgets); // first carousel slide
    await scrollHomeTo(
      tester,
      find.text('Administration panels are available in the web HRIS only.'),
    );
    expect(find.text('General Panel'), findsNothing);
    expect(find.text('My Attendance'), findsNothing);
    expect(find.text('Time Logs'), findsNothing);
    expect(find.text('Up Next'), findsNothing);
    expect(
      find.text('Administration panels are available in the web HRIS only.'),
      findsOneWidget,
    );
  });

  testWidgets('staff: Profile shows own data only', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(navLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Maria'), findsOneWidget);
    expect(find.text('Name Extension'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // no name extension
    expect(find.text('SAMPLE1001'), findsWidgets);
    expect(find.textContaining('SAMPLE1002'), findsNothing);
  });
}
