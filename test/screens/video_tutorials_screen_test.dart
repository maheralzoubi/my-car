import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/video_player_screen.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/video_tutorials_screen.dart';

import 'helpers/screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
  RecordingObserver? observer,
}) async {
  await pumpScreen(
    tester,
    const VideoTutorialsScreen(),
    locale: locale,
    size: size,
    pushed: pushed,
    observer: observer,
  );
  // Card fade-in (TweenAnimationBuilder, up to ~800 ms).
  await tester.pump(const Duration(seconds: 1));
}

Finder get _filterRows => find.byWidgetPredicate(
  (w) => w is ListView && w.scrollDirection == Axis.horizontal,
);

/// A chip in the code filter row (0) or difficulty row (1).
Finder _chip(int row, String label) =>
    find.descendant(of: _filterRows.at(row), matching: find.text(label));

Finder get _list => find.byWidgetPredicate(
  (w) => w is ListView && w.scrollDirection == Axis.vertical,
);

Future<void> _tapChip(WidgetTester tester, int row, String label) async {
  await tester.tap(_chip(row, label));
  await tester.pump(const Duration(seconds: 1));
}

/// Tutorial titles currently built in the list.
List<String> _titles(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: _list,
        matching: find.byWidgetPredicate((w) => w is Text && w.maxLines == 2),
      ),
    )
    .map((t) => t.data ?? '')
    .toList();

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        expect(find.text(tr('video_tutorials', locale)), findsOneWidget);
        expect(_chip(0, tr('all', locale)), findsOneWidget);
        expect(_chip(0, tr('tutorial_filter_general', locale)), findsOneWidget);
        expect(_chip(1, tr('all_levels', locale)), findsOneWidget);
        expect(_chip(1, tr('difficulty_beginner', locale)), findsOneWidget);
        expect(find.text(tr('upload', locale)), findsOneWidget);
        expect(_titles(tester), isNotEmpty);
        expect(
          directionAt(tester, find.byType(VideoTutorialsScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      expect(englishLeaks(tester), isEmpty);
    });
  });

  group('filters', () {
    testWidgets('code filter narrows the list', (tester) async {
      await _pump(tester, size: const Size(390, 2400));
      final all = _titles(tester).length;
      await _tapChip(tester, 0, 'P0420');
      final filtered = _titles(tester);
      expect(filtered, hasLength(1));
      expect(filtered.length, lessThan(all));
    });

    testWidgets('difficulty filter narrows the list', (tester) async {
      await _pump(tester, size: const Size(390, 2400));
      await _tapChip(tester, 1, tr('difficulty_beginner'));
      final beginner = _titles(tester);
      expect(beginner, hasLength(2));
      // Every visible difficulty badge is "Beginner".
      expect(
        find.descendant(
          of: _list,
          matching: find.text(tr('difficulty_beginner')),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('no match shows the empty state', (tester) async {
      await _pump(tester);
      await _tapChip(tester, 0, 'P0420');
      await _tapChip(tester, 1, tr('difficulty_beginner'));

      expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
      expect(find.text(tr('no_tutorials_found')), findsOneWidget);
    });

    testWidgets('"All" resets the code filter', (tester) async {
      await _pump(tester, size: const Size(390, 2400));
      final all = _titles(tester).length;
      await _tapChip(tester, 0, 'P0301');
      await _tapChip(tester, 0, tr('all'));
      expect(_titles(tester), hasLength(all));
    });

    testWidgets('filters work in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      await _tapChip(tester, 0, tr('tutorial_filter_general', ar));
      expectNoException(tester);
      expect(_titles(tester), hasLength(1));
    });

    testWidgets('search box filters tutorials', (tester) async {
      await _pump(tester, size: const Size(390, 2400));
      await tester.enterText(
        find.descendant(
          of: find.byType(VideoTutorialsScreen),
          matching: find.byType(TextField),
        ),
        'MAF',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_titles(tester), hasLength(1));
    });
  });

  group('cards', () {
    testWidgets('bookmark toggles on the card', (tester) async {
      await _pump(tester);
      final before = find.byIcon(Icons.bookmark).evaluate().length;
      await tester.tap(find.byIcon(Icons.bookmark_border).first);
      await tester.pump();
      expect(find.byIcon(Icons.bookmark).evaluate().length, before + 1);
    });

    testWidgets('tapping a card opens the player with that tutorial', (
      tester,
    ) async {
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);
      final title = _titles(tester).first;

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      expect(observer.pushedNames.last, AppRoutes.videoPlayer);
      final args = observer.pushed.last.settings.arguments as Map;
      expect(args['title'], title);
    });

    testWidgets('upload button opens /upload-video', (tester) async {
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);
      await tester.tap(find.text(tr('upload')));
      await tester.pumpAndSettle();
      expect(observer.pushedNames.last, AppRoutes.uploadVideo);
    });

    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check of the tutorials fixes (search, sample labelling).
  group('double-check', () {
    Finder search() => find.descendant(
      of: find.byType(VideoTutorialsScreen),
      matching: find.byType(TextField),
    );

    Future<void> type(WidgetTester tester, String q) async {
      await tester.enterText(search(), q);
      await tester.pump(const Duration(seconds: 1));
    }

    for (final locale in [en, ar]) {
      testWidgets('catalogue is labelled as sample content '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale);
        expect(find.text(tr('tutorial_sample_notice', locale)), findsOneWidget);
        // No invented instructors / channels from the old demo data.
        for (final fake in [
          'Mike Johnson',
          'Sarah Miller',
          'CarRepairPro',
          'AutoTechTV',
        ]) {
          expect(find.textContaining(fake), findsNothing, reason: fake);
        }
      });
    }

    testWidgets('search is case-insensitive, matches codes, and clears', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 2400));
      final all = _titles(tester).length;
      await type(tester, 'p0420');
      expect(_titles(tester), [tr('tut_title_o2_sensor')]);
      await type(tester, '  oxygen  ');
      expect(_titles(tester), [tr('tut_title_o2_sensor')]);
      await type(tester, '');
      expect(_titles(tester), hasLength(all));
    });

    testWidgets('search with no match shows the empty state', (tester) async {
      await _pump(tester);
      await type(tester, 'zzz-no-such-tutorial');
      expect(_titles(tester), isEmpty);
      expect(find.text(tr('no_tutorials_found')), findsOneWidget);
      expectNoException(tester);
    });

    testWidgets('search combines with the filters', (tester) async {
      await _pump(tester, size: const Size(390, 2400));
      await _tapChip(tester, 1, tr('difficulty_beginner'));
      await type(tester, 'MAF');
      expect(_titles(tester), [tr('tut_title_maf')]);
      await _tapChip(tester, 0, 'P0420');
      expect(_titles(tester), isEmpty);
    });

    testWidgets('Arabic search matches the Arabic titles', (tester) async {
      await _pump(tester, locale: ar, size: const Size(390, 2400));
      await type(tester, 'الأكسجين');
      expect(_titles(tester), [tr('tut_title_o2_sensor', ar)]);
      expect(englishLeaks(tester), isEmpty);
    });

    for (final locale in [en, ar]) {
      testWidgets('opening a sample tutorial passes localized, labelled data '
          '(${locale.languageCode})', (tester) async {
        final observer = RecordingObserver();
        await _pump(tester, locale: locale, observer: observer);
        await _tapChip(tester, 0, tr('tutorial_filter_general', locale));
        await tester.tap(find.text(tr('tut_title_check_engine', locale)));
        await tester.pumpAndSettle();
        final args = observer.pushed.last.settings.arguments as Map;
        expect(args['title'], tr('tut_title_check_engine', locale));
        expect(args['instructor'], tr('tutorial_sample_author', locale));
        expect(args['uploadedBy'], tr('tutorial_sample_badge', locale));
        expect(args['code'], tr('tutorial_filter_general', locale));
      });
    }

    testWidgets(
      'Arabic: the player opened from the list has no English',
      (tester) async {
        await pumpScreen(
          tester,
          const VideoTutorialsScreen(),
          locale: ar,
          routes: {AppRoutes.videoPlayer: VideoPlayerScreen.fromContext},
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text(tr('tut_title_o2_sensor', ar)));
        await tester.pumpAndSettle();
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        expect(englishLeaks(tester, allow: {'CARDIAG'}), isEmpty);
      },
    );

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), incl. empty state', (tester) async {
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          await type(tester, 'zzz');
          expectNoException(tester);
        });
      }
    }
  });
}
