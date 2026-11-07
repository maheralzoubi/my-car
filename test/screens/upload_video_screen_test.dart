import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/upload_video_screen.dart';

import 'helpers/screen_harness.dart';

const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) => pumpScreen(
  tester,
  const UploadVideoScreen(),
  locale: locale,
  size: size,
  pushed: pushed,
);

/// Title (0) and description (1).
Finder get _fields => find.byType(TextFormField);

Finder _publish([Locale l = en]) => find.text(tr('publish_tutorial', l));

/// The publish button is the last thing in the form; ensureVisible leaves it
/// on the clipped bottom edge, so scroll to the end before tapping.
Future<void> _tapPublish(WidgetTester tester, [Locale l = en]) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -4000),
  );
  await tester.pumpAndSettle();
  await tester.tap(_publish(l));
  await tester.pump();
}

Future<void> _fillValid(WidgetTester tester) async {
  await tester.enterText(_fields.at(0), 'Replace an O2 sensor');
  await tester.enterText(_fields.at(1), 'Step-by-step bank 1 sensor 1 swap');
}

const _videoPath = '/tmp/fake/brake_job.mp4';

/// Answers image_picker calls with [reply] (a file path, or null for
/// "cancelled") and records them.
List<MethodCall> _mockPicker(
  WidgetTester tester,
  Future<Object?> Function(MethodCall) reply,
) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_imagePicker, (
    c,
  ) {
    calls.add(c);
    return reply(c);
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _imagePicker,
      null,
    ),
  );
  return calls;
}

Future<void> _pickVideo(WidgetTester tester, [Locale l = en]) async {
  await tapVisible(tester, find.text(tr('tap_select_video', l)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'upload_tutorial',
          'video_file',
          'tap_select_video',
          'thumbnail',
          'tutorial_title_label',
          'description_label',
          'related_code',
          'difficulty_level',
          'estimated_cost',
          'publish_tutorial',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(_fields, findsNWidgets(2));
        expect(
          directionAt(tester, find.byType(UploadVideoScreen)),
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
      // Container formats are proper names.
      expect(englishLeaks(tester, allow: {'MP4', 'MOV', 'AVI'}), isEmpty);
    });
  });

  group('form', () {
    testWidgets('empty title and description are rejected', (tester) async {
      await _pump(tester);
      await _tapPublish(tester);

      expect(find.text(tr('tutorial_title_required')), findsOneWidget);
      expect(find.text(tr('tutorial_desc_required')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('selecting a difficulty highlights it', (tester) async {
      await _pump(tester);
      Color? colorOf(String key) =>
          tester.widget<Text>(find.text(tr(key))).style?.color;
      // Intermediate is the default.
      expect(colorOf('difficulty_intermediate'), Colors.white);
      await tapVisible(tester, find.text(tr('difficulty_beginner')));
      expect(colorOf('difficulty_beginner'), Colors.white);
      expect(colorOf('difficulty_intermediate'), isNot(Colors.white));
    });

    testWidgets('selecting a cost range moves the radio mark', (tester) async {
      await _pump(tester);
      final free = find.text(tr('cost_free'));
      await tapVisible(tester, free);
      final row = find.ancestor(of: free, matching: find.byType(Row)).first;
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    // Rewritten in the verifier pass. The old version expected a fake upload
    // (progress → "uploaded successfully" → done pops) and contradicted
    // 'publishing without a video file is rejected'. There is no tutorial
    // server, so a valid submission (video picked + form filled) must say
    // "Coming soon" instead of claiming success.
    testWidgets('picked video + valid form: honest "Coming soon" dialog, '
        'no fake upload', (tester) async {
      final calls = _mockPicker(tester, (_) async => _videoPath);
      await _pump(tester, pushed: true);
      await _pickVideo(tester);
      expect(calls.single.method, 'pickVideo');
      expect(find.text('brake_job.mp4'), findsOneWidget);

      await _fillValid(tester);
      await _tapPublish(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(tr('tutorial_upload_unavailable_title')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(tr('tutorial_upload_unavailable')),
        ),
        findsOneWidget,
      );
      expect(find.text(tr('success')), findsNothing);
      expect(find.text(tr('tutorial_uploaded')), findsNothing);

      await tester.tap(find.text(tr('ok')));
      await tester.pumpAndSettle();
      // Stays on the form (nothing was published), entries intact.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(UploadVideoScreen), findsOneWidget);
      expect(find.text('brake_job.mp4'), findsOneWidget);
      expect(find.text('Replace an O2 sensor'), findsOneWidget);
    });

    // Rewritten twin of the old 'dismissing the success dialog…' BUG test:
    // same intent (dismissing the result leaves a usable form) against the
    // real dialog.
    testWidgets('dismissing the "Coming soon" dialog leaves a usable form', (
      tester,
    ) async {
      _mockPicker(tester, (_) async => _videoPath);
      await _pump(tester);
      await _pickVideo(tester);
      await _fillValid(tester);
      await _tapPublish(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(tr('tutorial_upload_unavailable_title')),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(5, 5)); // modal barrier
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_publish(), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.ancestor(of: _publish(), matching: find.byType(ElevatedButton)),
      );
      expect(button.onPressed, isNotNull);

      // And it can be submitted again.
      await tester.tap(_publish());
      await tester.pumpAndSettle();
      expect(
        find.text(tr('tutorial_upload_unavailable_title')),
        findsOneWidget,
      );
    });

    // Was 'closing mid-upload does not throw'; there is no upload any more,
    // the async step left is the picker.
    testWidgets('closing while the picker is open does not throw', (
      tester,
    ) async {
      final pending = Completer<Object?>();
      _mockPicker(tester, (_) => pending.future);
      await _pump(tester, pushed: true);
      await tester.tap(find.text(tr('tap_select_video')));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      pending.complete(_videoPath);
      await tester.pumpAndSettle();
      expectNoException(tester);
      expect(find.text(launcherText), findsOneWidget);
    });

    testWidgets('publishing without a video file is rejected', (tester) async {
      await _pump(tester);
      await _fillValid(tester);
      await _tapPublish(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(tr('tutorial_uploaded')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('video_required')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('tapping the video area opens a picker', (tester) async {
      final calls = _mockPicker(tester, (_) async => null);

      await _pump(tester);
      await tester.tap(find.text(tr('tap_select_video')));
      await tester.pumpAndSettle();
      expect(calls, isNotEmpty);
    });
  });

  // Independent re-check of the upload fix.
  group('double-check', () {
    testWidgets('cancelling the picker keeps the video missing', (
      tester,
    ) async {
      _mockPicker(tester, (_) async => null);
      await _pump(tester);
      await _pickVideo(tester);
      await _fillValid(tester);
      await _tapPublish(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('video_required')), findsOneWidget);
    });

    testWidgets('picking a video clears the "video required" error', (
      tester,
    ) async {
      _mockPicker(tester, (_) async => _videoPath);
      await _pump(tester);
      await _tapPublish(tester);
      await tester.pumpAndSettle();
      expect(find.text(tr('video_required')), findsOneWidget);
      await _pickVideo(tester);
      expect(find.text(tr('video_required')), findsNothing);
      expect(find.text('brake_job.mp4'), findsOneWidget);
    });

    testWidgets('video but empty title/description is still rejected', (
      tester,
    ) async {
      _mockPicker(tester, (_) async => _videoPath);
      await _pump(tester);
      await _pickVideo(tester);
      await _tapPublish(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('tutorial_title_required')), findsOneWidget);
      expect(find.text(tr('tutorial_desc_required')), findsOneWidget);
    });

    testWidgets('thumbnail picker is wired and shows the picked file', (
      tester,
    ) async {
      final calls = _mockPicker(tester, (_) async => '/tmp/fake/thumb.jpg');
      await _pump(tester);
      await tapVisible(tester, find.text(tr('select_thumbnail')));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'pickImage');
      expect(find.text('thumb.jpg'), findsOneWidget);
    });

    testWidgets('a failing picker shows a localized error (ar)', (
      tester,
    ) async {
      _mockPicker(
        tester,
        (_) async => throw PlatformException(code: 'photo_access_denied'),
      );
      await _pump(tester, locale: ar);
      await _pickVideo(tester, ar);
      expectNoException(tester);
      expect(find.text(tr('media_pick_failed', ar)), findsOneWidget);
      expect(englishLeaks(tester, allow: {'MP4', 'MOV', 'AVI'}), isEmpty);
    });

    testWidgets('Arabic: the whole publish flow has no English', (
      tester,
    ) async {
      _mockPicker(tester, (_) async => '/tmp/fake/فيديو.mp4');
      await _pump(tester, locale: ar);
      await _pickVideo(tester, ar);
      await tester.enterText(_fields.at(0), 'تغيير حساس الأكسجين');
      await tester.enterText(_fields.at(1), 'شرح خطوة بخطوة');
      await _tapPublish(tester, ar);
      await tester.pumpAndSettle();
      expect(
        find.text(tr('tutorial_upload_unavailable_title', ar)),
        findsOneWidget,
      );
      expect(englishLeaks(tester, allow: {'MP4', 'MOV', 'AVI'}), isEmpty);
    });

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), errors + long file name', (
          tester,
        ) async {
          _mockPicker(
            tester,
            (_) async =>
                '/tmp/fake/a_really_long_video_file_name_from_the_camera_roll_'
                '2026_11_07_14_33_02_final_final_v2.mp4',
          );
          await _pump(tester, locale: locale, size: size);
          await _tapPublish(tester, locale);
          await tester.pumpAndSettle();
          expectNoException(tester);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, 4000),
          );
          await tester.pumpAndSettle();
          await _pickVideo(tester, locale);
          expectNoException(tester);
        });
      }
    }
  });

  group('navigation', () {
    testWidgets('close button pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });
}
