// Tests for the shared components in lib/core/widgets: layout safety with
// long text (EN + AR, small phone), RTL mirroring, interaction, and
// screen-reader semantics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/core.dart';

import '../screens/helpers/screen_harness.dart';

const _long =
    'Exhaust gas recirculation sensor A circuit range performance problem';
const _longAr =
    'نطاق دائرة مستشعر إعادة تدوير غاز العادم أ مشكلة في الأداء والاستجابة';

Widget _page(List<Widget> children) => Scaffold(
  body: SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: children,
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in [en, ar]) {
    final text = locale == ar ? _longAr : _long;

    testWidgets('[${locale.languageCode}] long text never overflows on a '
        'small phone', (tester) async {
      await pumpScreen(
        tester,
        _page([
          ScreenHeader(
            title: text,
            actions: [
              IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
              IconButton(icon: const Icon(Icons.share), onPressed: () {}),
            ],
          ),
          SectionTitle(
            text,
            trailing: TextButton(onPressed: () {}, child: const Text('All')),
          ),
          SettingsTile(
            leading: const IconBox.neutral(Icons.notifications_none_rounded),
            title: text,
            subtitle: text,
            onTap: () {},
          ),
          SettingsTile.toggle(
            leading: const IconBox.neutral(Icons.dark_mode_outlined),
            title: text,
            subtitle: text,
            value: true,
            onChanged: (_) {},
          ),
          Row(
            spacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: StatTile(
                    icon: const IconBox(Icons.bolt_rounded, size: 28),
                    label: text,
                    value: '123456789',
                    unit: 'km/h',
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Flexible(
                child: StatusBadge(
                  label: text,
                  level: StatusLevel.critical,
                  showIcon: true,
                ),
              ),
            ],
          ),
          AppButton(label: text, icon: Icons.bluetooth, onPressed: () {}),
          AppCard(accent: AppPalette.light.warn, child: Text(text)),
          SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: text,
              message: text,
              action: OutlinedButton(
                onPressed: () {},
                child: const Text('Retry'),
              ),
            ),
          ),
        ]),
        locale: locale,
        size: smallPhone,
      );
      expectNoException(tester);
    });
  }

  testWidgets('ScreenHeader: back pops, arrow mirrors in RTL, title is a '
      'header', (tester) async {
    await pumpScreen(
      tester,
      _page([const ScreenHeader(title: 'History')]),
      pushed: true,
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('History')),
      isSemantics(label: 'History', isHeader: true),
    );
    handle.dispose();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text(launcherText), findsOneWidget);

    // A screen with nothing to go back to (a tab root) shows no back button.
    await pumpScreen(tester, _page([const ScreenHeader(title: 'Home')]));
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await pumpScreen(
      tester,
      _page([const ScreenHeader(title: 'السجل')]),
      locale: ar,
      pushed: true,
    );
    final arrow = tester.getCenter(find.byIcon(Icons.arrow_back_rounded));
    final titleCenter = tester.getCenter(find.text('السجل'));
    expect(
      arrow.dx,
      greaterThan(titleCenter.dx),
      reason: 'back sits at the start (right) in RTL',
    );
  });

  testWidgets('SettingsTile.toggle: tapping the tile toggles; semantics carry '
      'title + toggled state', (tester) async {
    var value = false;
    await pumpScreen(
      tester,
      StatefulBuilder(
        builder: (context, setState) => _page([
          SettingsTile.toggle(
            title: 'Speed alerts',
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ]),
      ),
    );

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(SettingsTile)),
      matchesSemantics(
        label: 'Speed alerts',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.text('Speed alerts'));
    await tester.pumpAndSettle();
    expect(value, isTrue);

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(value, isFalse);
    handle.dispose();
  });

  testWidgets('AppSwitch: disabled ignores taps', (tester) async {
    await pumpScreen(
      tester,
      _page([const AppSwitch(value: false, onChanged: null)]),
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(AppSwitch)),
      isSemantics(
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expectNoException(tester);
    handle.dispose();
  });

  testWidgets('AppButton: taps, loading and disabled states', (tester) async {
    var taps = 0;
    Future<void> pump({bool loading = false, bool enabled = true}) =>
        pumpScreen(
          tester,
          _page([
            AppButton(
              label: 'Connect',
              isLoading: loading,
              onPressed: enabled ? () => taps++ : null,
            ),
          ]),
        );

    await pump();
    await tester.tap(find.byType(AppButton));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Connect'), findsOneWidget);

    await pump(loading: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(taps, 1, reason: 'loading ignores taps');

    await pump(enabled: false);
    await tester.tap(find.byType(AppButton));
    expect(taps, 1, reason: 'disabled ignores taps');
  });

  testWidgets('StatTile reads as one node; its icon is hidden from screen '
      'readers', (tester) async {
    await pumpScreen(
      tester,
      _page([
        const StatTile(
          icon: IconBox(Icons.route_rounded, size: 28),
          label: 'Trips',
          value: '42',
        ),
      ]),
    );
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.text('Trips'));
    expect(node.label, contains('Trips'));
    expect(node.label, contains('42'));
    expect(node.label, isNot(contains('🚗')));
    handle.dispose();
  });

  for (final (name, theme, palette) in [
    ('light', AppTheme.light, AppPalette.light),
    ('dark', AppTheme.dark, AppPalette.dark),
  ]) {
    testWidgets('[$name] StatusLevel maps to the palette status colors', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(StatusLevel.ok.colorOf(ctx), palette.ok);
      expect(StatusLevel.warning.colorOf(ctx), palette.warn);
      expect(StatusLevel.critical.colorOf(ctx), palette.crit);
      expect(StatusLevel.info.colorOf(ctx), palette.primary);
      expect(StatusLevel.critical.softOf(ctx), palette.critSoft);
      expect(ctx.colors, palette, reason: 'theme carries its palette');
    });
  }

  test('ThemeController loads, saves and falls back to system', () async {
    String? stored = 'dark';
    final c = ThemeController(
      read: () async => stored,
      write: (v) async => stored = v,
    );
    await c.load();
    expect(c.value, ThemeMode.dark);
    await c.set(ThemeMode.light);
    expect((c.value, stored), (ThemeMode.light, 'light'));
    stored = 'nonsense';
    await c.load();
    expect(c.value, ThemeMode.system);
  });
  testWidgets('AppCard accent styles: tint / outline / strong', (tester) async {
    final c = AppPalette.dark.warn; // harness theme is dark
    const p = AppPalette.dark;
    await pumpScreen(
      tester,
      _page([
        const AppCard(key: Key('none'), child: Text('n')),
        AppCard(key: const Key('tint'), accent: c, child: const Text('t')),
        AppCard(
          key: const Key('outline'),
          accent: c,
          accentStyle: AppCardAccent.outline,
          child: const Text('o'),
        ),
        AppCard(
          key: const Key('strong'),
          accent: c,
          accentStyle: AppCardAccent.strong,
          child: const Text('s'),
        ),
      ]),
    );
    (Color, Color) look(String k) {
      final m = tester.widget<Material>(
        find
            .descendant(of: find.byKey(Key(k)), matching: find.byType(Material))
            .first,
      );
      final side = (m.shape! as RoundedRectangleBorder).side;
      return (m.color!, side.color);
    }

    expect(look('none'), (p.surface, p.border));
    expect(look('tint'), (
      c.withValues(alpha: 0.14),
      c.withValues(alpha: 0.32),
    ));
    expect(look('outline'), (p.surface, c.withValues(alpha: 0.45)));
    expect(look('strong'), (c.withValues(alpha: 0.14), c));
  });

  testWidgets('ScreenHeader(close: true) shows ✕ and pops', (tester) async {
    await pumpScreen(
      tester,
      _page([const ScreenHeader(title: 'Edit', close: true)]),
      pushed: true,
    );
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text(launcherText), findsOneWidget);
  });

  testWidgets('SettingsTile.toggle disabled: fades once, ignores taps', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      _page([
        const SettingsTile.toggle(title: 'Loop', value: false, onChanged: null),
      ]),
    );
    final fades = tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byType(SettingsTile),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity)
        .where((o) => o < 1)
        .toList();
    expect(fades, [
      0.5,
    ], reason: 'row fades once, the switch does not fade again');
    await tester.tap(find.text('Loop'));
    await tester.pumpAndSettle();
    expectNoException(tester);
  });

  testWidgets('AppButton stays full strength while loading', (tester) async {
    await pumpScreen(
      tester,
      _page([const AppButton(label: 'Save', isLoading: true, onPressed: null)]),
    );
    final o = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(Opacity),
      ),
    );
    expect(o.opacity, 1);
  });
}
