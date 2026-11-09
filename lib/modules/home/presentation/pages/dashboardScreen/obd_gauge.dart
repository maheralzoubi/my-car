import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ── Public widget ──────────────────────────────────────────────────────────────

class OBDGauge extends StatelessWidget {
  const OBDGauge({
    super.key,
    required this.value,
    required this.max,
    required this.label,
    required this.unit,
    required this.color,
    this.dangerAt,   // value above which the arc turns red
    this.decimals = 0,
  });

  final double? value;
  final double max;
  final String label;
  final String unit;
  final Color color;
  final double? dangerAt;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final fraction = value != null ? (value! / max).clamp(0.0, 1.0) : 0.0;
    final inDanger = dangerAt != null && value != null && value! >= dangerAt!;
    final displayColor = inDanger ? const Color(0xFFFF1744) : color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1.35,
          child: CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              color: color,
              dangerFraction: dangerAt != null ? dangerAt! / max : null,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(top: 20.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value != null
                          ? value!.toStringAsFixed(decimals)
                          : '--',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w900,
                        color: displayColor,
                        height: 1,
                      ),
                    ),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: displayColor.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: const Color(0xFFE8EAED).withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Painter ────────────────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.color,
    this.dangerFraction,
  });

  final double fraction;
  final Color color;
  final double? dangerFraction;

  // Arc spans 240° — starts at 8 o'clock (150°), ends at 4 o'clock.
  static const double _startDeg = 150.0;
  static const double _sweepDeg = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.60;
    final r  = size.width * 0.41;

    final startRad = _startDeg * pi / 180;
    final sweepRad = _sweepDeg * pi / 180;
    final trackW   = r * 0.16;
    final rect     = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // ── 1. Background track ─────────────────────────────────────────────────
    canvas.drawArc(
      rect, startRad, sweepRad, false,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackW
        ..strokeCap = StrokeCap.round,
    );

    // ── 2. Danger zone tint (behind value arc, shows track in red tint) ─────
    if (dangerFraction != null) {
      final dangerStart = startRad + sweepRad * dangerFraction!;
      final dangerSweep = sweepRad * (1.0 - dangerFraction!);
      canvas.drawArc(
        rect, dangerStart, dangerSweep, false,
        Paint()
          ..color = const Color(0xFFFF1744).withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackW,
      );
    }

    // ── 3. Value arc ────────────────────────────────────────────────────────
    if (fraction > 0) {
      final fillSweep = sweepRad * fraction;

      if (dangerFraction != null && fraction > dangerFraction!) {
        // Normal segment
        final normalSweep = sweepRad * dangerFraction!;
        canvas.drawArc(
          rect, startRad, normalSweep, false,
          _arcPaint(color, trackW, cap: StrokeCap.butt),
        );
        // Danger segment
        canvas.drawArc(
          rect,
          startRad + normalSweep,
          fillSweep - normalSweep,
          false,
          _arcPaint(const Color(0xFFFF1744), trackW),
        );
      } else {
        canvas.drawArc(
          rect, startRad, fillSweep, false,
          _arcPaint(color, trackW),
        );
      }
    }

    // ── 4. Tick marks ───────────────────────────────────────────────────────
    const tickCount = 9; // 0, 1/8 … 8/8
    for (var i = 0; i <= tickCount; i++) {
      final tickFrac  = i / tickCount.toDouble();
      final angle     = startRad + sweepRad * tickFrac;
      final isMajor   = i % 2 == 0;
      final outerR    = r - trackW / 2 - 2;
      final innerR    = outerR - (isMajor ? r * 0.14 : r * 0.08);
      final inDanger  = dangerFraction != null && tickFrac >= dangerFraction!;

      canvas.drawLine(
        Offset(cx + outerR * cos(angle), cy + outerR * sin(angle)),
        Offset(cx + innerR * cos(angle), cy + innerR * sin(angle)),
        Paint()
          ..color = (inDanger
                  ? const Color(0xFFFF1744)
                  : const Color(0xFFFFFFFF))
              .withValues(alpha: isMajor ? 0.55 : 0.25)
          ..strokeWidth = isMajor ? 2.0 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── 5. Centre hub ────────────────────────────────────────────────────────
    final hubColor = fraction > 0 && dangerFraction != null && fraction > dangerFraction!
        ? const Color(0xFFFF1744)
        : color;
    canvas.drawCircle(
      Offset(cx, cy), r * 0.13,
      Paint()..color = hubColor.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      Offset(cx, cy), r * 0.06,
      Paint()..color = hubColor,
    );
  }

  Paint _arcPaint(Color c, double width, {StrokeCap cap = StrokeCap.round}) =>
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = cap;

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color    != color    ||
      old.dangerFraction != dangerFraction;
}
