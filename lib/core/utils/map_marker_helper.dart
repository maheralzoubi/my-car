import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Renders a custom map pin using Flutter's canvas.
///
/// The pin is a filled circle with a Material icon inside it, plus a
/// downward-pointing triangle at the bottom (classic map-pin shape).
abstract final class MapMarkerHelper {
  MapMarkerHelper._();

  static Future<BitmapDescriptor> buildPin({
    required Color color,
    required IconData icon,
    double circleSize = 72,
    Color iconColor = Colors.white,
  }) async {
    final pointerH = circleSize * 0.32;
    final totalH = circleSize + pointerH;
    final cx = circleSize / 2;
    final cy = circleSize / 2;
    final r = circleSize / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, circleSize, totalH),
    );

    // ── drop shadow ────────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy + 3),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    // ── circle fill ────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);

    // ── white border ───────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // ── pointer triangle ───────────────────────────────────────────────────
    final tipX = cx;
    final tipY = totalH;
    final baseY = circleSize - 4.0;
    final halfBase = circleSize * 0.14;

    final pointer = Path()
      ..moveTo(tipX - halfBase, baseY)
      ..lineTo(tipX, tipY)
      ..lineTo(tipX + halfBase, baseY)
      ..close();

    canvas.drawPath(pointer, Paint()..color = color);
    canvas.drawPath(
      pointer,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // ── icon ───────────────────────────────────────────────────────────────
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: circleSize * 0.48,
          fontFamily: icon.fontFamily,
          color: iconColor,
        ),
      )
      ..layout();
    tp.paint(
      canvas,
      Offset((circleSize - tp.width) / 2, (circleSize - tp.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      circleSize.toInt(),
      totalH.toInt(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
