import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/video_player_screen.dart';

import 'helpers/screen_harness.dart';

// The player is a mock UI (no video plugin): play/pause and the scrubber only
// change local state, so they are tested as such.

Map<String, dynamic> _tutorial() => {
  'id': '1',
  'title': 'How to Replace Oxygen Sensor',
  'code': 'P0420',
  'duration': '15 min',
  'difficulty': 'Intermediate',
  'views': '125K',
  'rating': 4.8,
  'thumbnail': '🔧',
  'instructor': 'Mike Johnson',
};

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? tutorial,
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) => pumpScreen(
  tester,
  VideoPlayerScreen(tutorial: tutorial ?? _tutorial()),
  locale: locale,
  size: size,
  pushed: pushed,
);

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        expect(find.text('How to Replace Oxygen Sensor'), findsOneWidget);
        expect(find.text('Mike Johnson'), findsOneWidget);
        expect(find.text(tr('like', locale)), findsOneWidget);
        expect(find.text(tr('description_label', locale)), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(
          directionAt(tester, find.byType(VideoPlayerScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    for (final locale in [en, ar]) {
      testWidgets('light theme renders (${locale.languageCode})', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          VideoPlayerScreen(tutorial: _tutorial()),
          locale: locale,
          theme: AppTheme.light,
        );
        expectNoException(tester);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expectNoException(tester);
        expect(find.text(tr('related_videos', locale)), findsOneWidget);
      });
    }

    testWidgets('empty tutorial map renders placeholders', (tester) async {
      await _pump(tester, tutorial: {});
      expectNoException(tester);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('route builder tolerates missing / wrong arguments', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.pushNamed(
              ctx,
              AppRoutes.videoPlayer,
              arguments: 'not a map',
            ),
            child: const Text('go'),
          ),
        ),
        routes: {AppRoutes.videoPlayer: VideoPlayerScreen.fromContext},
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expectNoException(tester);
      expect(find.byType(VideoPlayerScreen), findsOneWidget);
    });
  });

  group('player controls', () {
    testWidgets('play / pause toggles', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('scrubbing moves the position label', (tester) async {
      await _pump(tester);
      expect(find.text('0:00'), findsOneWidget);

      final slider = find.byType(Slider);
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + rect.width * 0.9, rect.center.dy));
      await tester.pump();

      expect(tester.widget<Slider>(slider).value, greaterThan(50));
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('picture-in-picture dialog opens and cancels', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
      await tester.pumpAndSettle();
      expect(find.text(tr('pip_mode')), findsOneWidget);
      expect(find.text(tr('pip_prompt')), findsOneWidget);

      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();
      expect(find.text(tr('pip_mode')), findsNothing);
    });

    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check: the player has no video source (sample catalogue,
  // no tutorial backend), so its controls must not pretend otherwise.
  group('double-check', () {
    testWidgets('play on a sample tutorial says there is no video instead of '
        'pretending to play', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      final explained =
          find.byType(SnackBar).evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty;
      expect(explained, isTrue);
    });

    testWidgets(
      '"Enable" picture-in-picture does not silently pretend to work',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tr('enable_pip')));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets('play explains that sample tutorials have no video', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(find.text(tr('video_playback_unavailable')), findsOneWidget);
    });

    testWidgets('"Enable" picture-in-picture says it is not available', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('enable_pip')));
      await tester.pumpAndSettle();
      expect(find.text(tr('pip_mode')), findsNothing);
      expect(find.text(tr('pip_unavailable')), findsOneWidget);
    });

    for (final locale in [en, ar]) {
      testWidgets('like / save / subscribe / share give honest feedback '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale);
        for (final target in [
          find.text(tr('like', locale)),
          find.text(tr('save', locale)),
          find.text(tr('subscribe', locale)),
          find.byIcon(Icons.share_rounded),
        ]) {
          await tapVisible(tester, target);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(tr('tutorial_action_unavailable', locale)),
            ),
            findsOneWidget,
            reason: '$target',
          );
          ScaffoldMessenger.of(
            tester.element(find.byType(VideoPlayerScreen)),
          ).removeCurrentSnackBar();
          await tester.pumpAndSettle();
        }
      });
    }

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), scrolled to the end', (tester) async {
          await _pump(
            tester,
            locale: locale,
            size: size,
            tutorial: {
              ..._tutorial(),
              'title':
                  'A very long sample tutorial title that wraps over several '
                  'lines on a small phone',
            },
          );
          expectNoException(tester);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -4000),
          );
          await tester.pumpAndSettle();
          expectNoException(tester);
        });
      }
    }
  });
}
