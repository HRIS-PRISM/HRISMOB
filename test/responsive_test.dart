// Layout checks on representative Android screen sizes.
//
// Any RenderFlex overflow or other layout error is reported by the test
// framework and fails the test, so every screen and section below is
// rendered and scrolled through at each size.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/app.dart';
import 'package:hrismob/app_scope.dart';
import 'package:hrismob/mock/mock_services.dart';
import 'package:hrismob/models/bulletin.dart';
import 'package:hrismob/services/session_controller.dart';
import 'package:hrismob/widgets/home_widgets.dart';

class _ResponsiveImageRepository extends MockHrisRepository {
  _ResponsiveImageRepository(this.item) : super(latency: Duration.zero);

  final Bulletin item;

  @override
  Future<List<Bulletin>> fetchBulletins() async => [item];
}

final Uint8List _responsivePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class ScreenCase {
  const ScreenCase(
    this.name,
    this.width,
    this.height, {
    this.textScale = 1.0,
    this.dpr = 2.75,
  });

  final String name;
  final double width; // logical pixels (dp)
  final double height;
  final double textScale;
  final double dpr;

  bool get wide => width >= 600;

  @override
  String toString() =>
      '$name ${width.toInt()}x${height.toInt()} dp${textScale == 1.0 ? '' : ', text x$textScale'}';
}

const cases = [
  ScreenCase('narrow', 320, 568, dpr: 2), // small/older phones
  ScreenCase('standard', 360, 640, dpr: 3), // common baseline
  ScreenCase('standard-large', 411, 891, dpr: 2.625), // Pixel-class phones
  ScreenCase('wide', 480, 1000, dpr: 2.25), // large phones
  ScreenCase('landscape', 891, 411, dpr: 2.625), // phone rotated (rail)
  ScreenCase(
    'narrow+largest font',
    320,
    568,
    textScale: 2.0,
    dpr: 2,
  ), // clamped to 1.4
  ScreenCase('standard+large font', 360, 640, textScale: 1.3, dpr: 3),
];

const accounts = [
  'SAMPLE1001',
  'SAMPLE1002',
  'SAMPLE2001',
  'SAMPLE2002',
  'SAMPLE3001',
  'SAMPLE4001',
];

/// Accounts allowed to open the full Attendance page (web page-access rules).
const attendanceAllowed = {
  'SAMPLE1001',
  'SAMPLE1002',
  'SAMPLE2001',
  'SAMPLE3001',
  'SAMPLE4001',
};

Future<void> pumpAt(WidgetTester tester, ScreenCase c) async {
  tester.view.physicalSize = Size(c.width * c.dpr, c.height * c.dpr);
  tester.view.devicePixelRatio = c.dpr;
  tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    HrisMobileApp(
      session: SessionController(MockAuthService(latency: Duration.zero)),
      repository: MockHrisRepository(
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

Future<void> pumpImageAt(WidgetTester tester, ScreenCase c) async {
  tester.view.physicalSize = Size(c.width * c.dpr, c.height * c.dpr);
  tester.view.devicePixelRatio = c.dpr;
  tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final now = DateTime.now();
  final item = Bulletin(
    id: 'responsive-image',
    kind: BulletinKind.holiday,
    title: 'Responsive Holiday Image',
    start: DateTime(now.year, now.month, now.day),
    imageUrl: Uri.parse('https://hris.example.test/uploads/responsive.png'),
    about:
        '<p><b>Responsive</b> <i>formatted</i> <u>details</u></p>'
        '<ol>${List.generate(40, (index) => '<li>Responsive detail item ${index + 1}</li>').join()}</ol>'
        '<ul><li>Final nested marker</li></ul>',
  );
  await tester.pumpWidget(
    AppScope(
      session: SessionController(MockAuthService(latency: Duration.zero)),
      repository: _ResponsiveImageRepository(item),
      child: MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: BulletinCarousel(
                emptyText: 'Empty',
                imageProviderBuilder: (_) => MemoryImage(_responsivePng),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester, String emp) async {
  await tester.enterText(find.byType(TextFormField).at(0), emp);
  await tester.enterText(find.byType(TextFormField).at(1), 'anything');
  final button = find.text('Sign In');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// A destination in whichever navigation the screen size uses.
Finder dest(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail),
  matching: find.text(label),
);

/// Scrolls the page (the outermost vertical scrollable) from top to bottom,
/// building every section on the way.
Future<void> scrollThrough(WidgetTester tester, {Finder? never}) async {
  final scrollable = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  final step = position.viewportDimension * 0.8;
  for (var offset = 0.0; ; offset += step) {
    position.jumpTo(offset.clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
    if (never != null) expect(never, findsNothing);
    if (offset >= position.maxScrollExtent) break;
  }
  position.jumpTo(0);
  await tester.pumpAndSettle();
}

/// Scrolls the page down until [target] is built, then brings it into view.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  for (
    var offset = 0.0;
    target.evaluate().isEmpty && offset <= position.maxScrollExtent;
  ) {
    offset += position.viewportDimension * 0.5;
    position.jumpTo(offset.clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

Size screenOf(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

void main() {
  for (final c in [cases[0], cases[4], cases[5]]) {
    testWidgets('$c carousel image remains responsive', (tester) async {
      await pumpImageAt(tester, c);
      expect(
        find.byKey(const ValueKey('bulletin-image-responsive-image')),
        findsOneWidget,
      );
      expect(find.text('Responsive Holiday Image'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final c in [cases[0], cases[4], cases[5]]) {
    testWidgets('$c long carousel details remain scrollable', (tester) async {
      await pumpImageAt(tester, c);
      await tester.tap(find.text('Responsive Holiday Image'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      final scrollView = find.descendant(
        of: sheet,
        matching: find.byType(SingleChildScrollView),
      );
      expect(sheet, findsOneWidget);
      expect(scrollView, findsOneWidget);
      expect(
        find.byKey(const ValueKey('bulletin-description')),
        findsOneWidget,
      );
      final description = tester.widget<Text>(
        find.byKey(const ValueKey('bulletin-description')),
      );
      expect(description.textSpan!.toPlainText(), contains('40. Responsive'));
      expect(description.textSpan!.toPlainText(), contains('• Final nested'));
      expect(
        find.byKey(const ValueKey('bulletin-detail-image')),
        findsOneWidget,
      );
      final availableModalWidth = c.width > 640 ? 640.0 : c.width;
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('bulletin-detail-sheet-content')),
            )
            .width,
        availableModalWidth,
      );
      for (var i = 0; i < 8; i++) {
        await tester.drag(scrollView, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rotating keeps the open page and the applied filter', (
    tester,
  ) async {
    await pumpAt(tester, cases[2]); // portrait, bottom navigation
    await signIn(tester, 'SAMPLE1001');
    await tester.tap(dest('Attendance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JAN'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search')));
    await tester.pumpAndSettle();
    expect(find.text('Back to today'), findsOneWidget);

    // Rotate to landscape: navigation rail, same page, same filter.
    tester.view.physicalSize = Size(
      cases[2].height * cases[2].dpr,
      cases[2].width * cases[2].dpr,
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('My Attendance Records'), findsOneWidget);
    expect(find.text('Back to today'), findsOneWidget);
  });

  for (final c in cases) {
    group('$c', () {
      testWidgets('Login fits, scrolls with the keyboard open, and signs in', (
        tester,
      ) async {
        await pumpAt(tester, c);
        expect(find.text('WELCOME BACK'), findsOneWidget);
        await tester.showKeyboard(find.byType(TextFormField).at(0));
        // Simulate the on-screen keyboard taking the lower part of the screen.
        tester.view.viewInsets = FakeViewPadding(
          bottom: c.height * 0.4 * c.dpr,
        );
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await signIn(tester, 'SAMPLE1001');
        expect(find.text('Hello, Maria Lopez Reyes'), findsOneWidget);
      });

      for (final emp in accounts) {
        testWidgets('$emp: Home, navigation and Today card', (tester) async {
          await pumpAt(tester, c);
          await signIn(tester, emp);

          // Today card for every role.
          await scrollTo(tester, find.text('OFFICIAL TIME'));
          expect(find.text('Today'), findsOneWidget);
          expect(find.text('TIME IN'), findsOneWidget);
          expect(find.text('OFFICIAL TIME'), findsOneWidget);

          // Navigation pattern by width; destinations by role and access.
          expect(
            find.byType(NavigationRail),
            c.wide ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(NavigationBar),
            c.wide ? findsNothing : findsOneWidget,
          );
          expect(dest('Home'), findsOneWidget);
          expect(dest('Profile'), findsOneWidget);
          expect(
            dest('Attendance'),
            attendanceAllowed.contains(emp) ? findsOneWidget : findsNothing,
          );

          // General Panel is navigation, never a Home card.
          await scrollThrough(tester, never: find.text('General Panel'));

          await tester.tap(dest('Profile'));
          await tester.pumpAndSettle();
          await scrollTo(tester, find.text('Personal Information'));
          await scrollThrough(tester);

          await tester.tap(dest('Home'));
          await tester.pumpAndSettle();
          await scrollTo(tester, find.text('Today'));
        });
      }

      testWidgets('Job Order Home: carousel, Time Logs, Up Next, calendar', (
        tester,
      ) async {
        await pumpAt(tester, c);
        await signIn(tester, 'SAMPLE1002');
        await scrollTo(tester, find.text('HOLIDAY')); // newest carousel slide
        await scrollThrough(tester);
        await scrollTo(tester, find.text('MON'));
        expect(find.text('MON'), findsOneWidget);
        // Month navigation buttons stay comfortably tappable.
        final prev = find.byTooltip('Previous month').last;
        expect(tester.getSize(prev).width, greaterThanOrEqualTo(36));
        await tester.ensureVisible(prev);
        await tester.pumpAndSettle();
        await tester.tap(prev);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Next month').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next month').last);
        await tester.pumpAndSettle();
      });

      testWidgets('Attendance: filter, month grid, Search, results, details', (
        tester,
      ) async {
        await pumpAt(tester, c);
        await signIn(tester, 'SAMPLE1001');
        await tester.tap(dest('Attendance'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('search')), findsNothing); // collapsed
        await tester.tap(find.text('Attendance Filter'));
        await tester.pumpAndSettle();

        // Month cells: tappable size, 6 per row when they fit, else 4.
        final jan = find
            .ancestor(of: find.text('JAN'), matching: find.byType(Material))
            .first;
        final cell = tester.getSize(jan);
        expect(cell.width, greaterThanOrEqualTo(40));
        expect(cell.height, greaterThanOrEqualTo(40));
        final sixPerRow =
            tester.getTopLeft(find.text('JUN')).dy ==
            tester.getTopLeft(find.text('JAN')).dy;
        final fourPerRow =
            tester.getTopLeft(find.text('APR')).dy ==
                tester.getTopLeft(find.text('JAN')).dy &&
            tester.getTopLeft(find.text('MAY')).dy >
                tester.getTopLeft(find.text('JAN')).dy;
        expect(sixPerRow || fourPerRow, isTrue);

        // Last month (December of last year in January): inside the
        // sample history, so the search returns records.
        final now = DateTime.now();
        final last = DateTime(now.year, now.month - 1);
        if (last.year != now.year) {
          await tester.tap(find.byKey(const ValueKey('year')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('${last.year}').last);
          await tester.pumpAndSettle();
        }
        final monthLabel = const [
          'JAN',
          'FEB',
          'MAR',
          'APR',
          'MAY',
          'JUN',
          'JUL',
          'AUG',
          'SEP',
          'OCT',
          'NOV',
          'DEC',
        ][last.month - 1];
        await tester.ensureVisible(find.text(monthLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(monthLabel));
        await tester.pumpAndSettle();
        expect(find.textContaining('Tap Search to apply.'), findsOneWidget);

        // Date fields open the picker and it fits the screen.
        final from = find
            .ancestor(of: find.text('From'), matching: find.byType(InkWell))
            .first;
        await tester.ensureVisible(from);
        await tester.pumpAndSettle();
        await tester.tap(from);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final search = find.byKey(const ValueKey('search'));
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        expect(tester.getSize(search).height, greaterThanOrEqualTo(48));
        await tester.tap(search);
        await tester.pumpAndSettle();

        // Collapsed, and scrolled so the results are on screen.
        expect(search, findsNothing);
        final summary = tester.getTopLeft(find.text('RECORD SUMMARY'));
        expect(summary.dy, inInclusiveRange(0, screenOf(tester).height - 80));
        expect(find.textContaining('records found'), findsOneWidget);

        // Record details.
        await scrollTo(tester, find.text('View'));
        await tester.tap(find.text('View').first);
        await tester.pumpAndSettle();
        expect(find.text('EMPLOYEE ID'), findsOneWidget);
        expect(find.text('DEVICE'), findsOneWidget);
        await scrollThrough(tester);

        // Clear applies at once.
        await tester.tap(find.text('Attendance Filter'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(find.text('Back to today'), findsNothing);
      });

      testWidgets('Access denied page fits (administrator without access)', (
        tester,
      ) async {
        await pumpAt(tester, c);
        await signIn(tester, 'SAMPLE2002');
        expect(dest('Attendance'), findsNothing);
        await scrollTo(tester, find.text('Today'));
        await scrollThrough(tester);
      });
    });
  }
}
