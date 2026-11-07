// Shared pump helpers for the home-screen widget tests.
//
// Screens are pumped inside the same shell the app uses (ScreenUtilInit with
// the 390x844 design size + MaterialApp with the app's localizations and dark
// theme) at a real phone surface size. Named routes resolve to a [RouteStub]
// that records the route name and its arguments, so navigation targets can be
// asserted without building (and wiring the dependencies of) the real
// destination screen. Pass [routes] to build real destinations instead.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/theme/app_theme.dart';

const Locale en = Locale('en');
const Locale ar = Locale('ar');

/// The localized string for [key], resolved the same way the screens do via
/// `context.tr`. Looked up at runtime so tests keep passing when the copy in
/// app_localizations.dart changes.
String tr(String key, [Locale locale = en]) => AppLocalizations(locale).tr(key);

/// Registers real fonts so text is measured with real glyph widths: every
/// font the app bundles (FontManifest.json — the theme's family, which
/// covers Arabic and Latin, plus the icon fonts) and the Roboto family
/// shipped with the Flutter SDK. The default test font draws every glyph as
/// a 1em square, which makes ordinary titles "overflow" at phone width when
/// they fit comfortably on a device. Call from `setUpAll`. Each source is
/// skipped if it can't be found.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledFonts();
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
  final engineDir = File(Platform.resolvedExecutable).parent;
  final cache = engineDir.parent.parent.parent;
  final candidates = [
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      Directory('$root/bin/cache/artifacts/material_fonts'),
    Directory('${cache.path}/artifacts/material_fonts'),
  ];
  final dir = candidates.firstWhere(
    (d) => d.existsSync(),
    orElse: () => Directory(''),
  );
  if (dir.path.isEmpty) return;

  final loader = FontLoader('Roboto');
  for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    final f = File('${dir.path}/Roboto-$weight.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await loader.load();
}

/// Loads every family listed in the test asset bundle's FontManifest.json
/// (what `flutter test` builds from the pubspec `fonts:` section).
Future<void> _loadBundledFonts() async {
  final List<dynamic> manifest;
  try {
    manifest =
        json.decode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
  } catch (_) {
    return; // No bundled fonts.
  }
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(family['family'] as String);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    try {
      await loader.load();
    } catch (_) {
      // A missing asset just leaves that family on the test font.
    }
  }
}

/// Logical phone sizes.
const Size phonePortrait = Size(390, 844);
const Size smallPhone = Size(360, 640);

/// Makes the test surface [logical] logical pixels at 3x DPR.
void setPhoneSurface(WidgetTester tester, [Size logical = phonePortrait]) {
  tester.view.physicalSize = logical * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Placeholder destination for named routes that a test does not build for
/// real. Shows `route:<name>` so the push is visible in the tree.
class RouteStub extends StatelessWidget {
  const RouteStub({super.key, required this.name, this.arguments});

  final String name;
  final Object? arguments;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('route:$name')));
}

/// Records every route pushed / popped through the app navigator.
class RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> popped = [];

  List<String?> get pushedNames => pushed.map((r) => r.settings.name).toList();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

/// Text shown by the launcher page that sits under a screen pumped with
/// `pushed: true`, so a back navigation can be detected.
const String launcherText = 'LAUNCHER';

class _Launcher extends StatefulWidget {
  const _Launcher({required this.child});
  final Widget child;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/under-test'),
          builder: (_) => widget.child,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(launcherText)));
}

/// Builds the app shell around [child].
Widget buildHarness(
  Widget child, {
  Locale locale = en,
  Map<String, WidgetBuilder> routes = const {},
  RecordingObserver? observer,
  bool pushed = false,
  ThemeData? theme,
}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    splitScreenMode: true,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.dark,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      navigatorObservers: [if (observer != null) observer],
      home: pushed ? _Launcher(child: child) : child,
      onGenerateRoute: (settings) => MaterialPageRoute<dynamic>(
        settings: settings,
        builder:
            routes[settings.name] ??
            (_) => RouteStub(
              name: settings.name ?? '',
              arguments: settings.arguments,
            ),
      ),
    ),
  );
}

/// Pumps [child] at phone size inside the app shell and settles one frame.
///
/// [theme] defaults to the dark theme; pass `AppTheme.light` to check the
/// light theme (every redesigned screen must work in both).
///
/// With [pushed], [child] is pushed on top of a launcher page (so its back
/// button has somewhere to go); the push transition is completed here.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Locale locale = en,
  Size size = phonePortrait,
  Map<String, WidgetBuilder> routes = const {},
  RecordingObserver? observer,
  bool pushed = false,
  ThemeData? theme,
}) async {
  setPhoneSurface(tester, size);
  await tester.pumpWidget(
    buildHarness(
      child,
      locale: locale,
      routes: routes,
      observer: observer,
      pushed: pushed,
      theme: theme,
    ),
  );
  await tester.pump();
  if (pushed) {
    // Post-frame push + the page transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Text direction in effect at [finder].
TextDirection directionAt(WidgetTester tester, Finder finder) =>
    Directionality.of(tester.element(finder.first));

/// Asserts no exception (layout overflow included) was reported.
void expectNoException(WidgetTester tester) =>
    expect(tester.takeException(), isNull);

/// Unmounts the tree and drains timers so repeating animations / delayed
/// futures don't trip the "Timer is still pending" check.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// Taps the widget found by [finder] after scrolling it into view, then
/// pumps one frame.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Finds a [Text] whose (plain) data equals [text].
Finder textExact(String text) => find.text(text);

/// Finds [Icon]s by [icon] data.
Finder icon(IconData data) => find.byIcon(data);

/// Visible English copy in a non-English UI: every [Text] containing a Latin
/// word of 3+ letters that is not in [allow] (case-insensitive). Codes like
/// P0420 and units like "km" don't count.
List<String> englishLeaks(WidgetTester tester, {Set<String> allow = const {}}) {
  final allowed = {
    'km',
    'obd',
    'cardiag',
    'elm',
    'vin',
    'dtc',
    'gps',
    'mph',
    'abs',
    ...allow.map((a) => a.toLowerCase()),
  };
  final word = RegExp(r'[A-Za-z]{3,}');
  final leaks = <String>{};
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final s = t.data ?? t.textSpan?.toPlainText() ?? '';
    if (word.allMatches(s).any((m) => !allowed.contains(m[0]!.toLowerCase()))) {
      leaks.add(s);
    }
  }
  return leaks.toList();
}

/// `skip:` value for a test that asserts correct behaviour the app does not
/// have yet. `testWidgets` only takes a bool, so the reason lives here
/// (format: 'BUG: what, file:line', or 'REGRESSION: what, file:line' for a
/// defect found while verifying a fix) and is grep-able.
///
/// Run the bug tests (to confirm they still fail, or pass after a fix) with
/// `flutter test --dart-define=RUN_BUG_TESTS=true test/screens`.
bool bug(String reason) {
  assert(reason.startsWith('BUG:') || reason.startsWith('REGRESSION:'));
  return !const bool.fromEnvironment('RUN_BUG_TESTS');
}

/// Drops RenderFlex overflow reports (and only those) for the current test.
/// For behaviour tests on screens with a known, separately-tested layout
/// BUG, so the logic is still exercised at phone size.
void ignoreOverflowErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}
