import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/obd_service.dart';

// ── Sensor channel definition ─────────────────────────────────────────────────

/// A series color stepped for each theme: the same hue, one step per surface.
typedef _SeriesColor = ({Color light, Color dark});

class _Channel {
  final String id;

  /// Localization key for the label; null for technical codes shown as-is
  /// (RPM, STFT B1, O2 B1S1…).
  final String? labelKey;
  final String label;
  final String unit;
  final _SeriesColor color;
  final double maxY;
  final double? Function(OBDLiveData) extract;

  const _Channel({
    required this.id,
    this.labelKey,
    required this.label,
    required this.unit,
    required this.color,
    required this.maxY,
    required this.extract,
  });
}

const _kMaxPoints = 60; // 60 samples × 3 s poll = last 3 minutes

/// Data-viz series colors (not theme tokens): the validated 8-slot categorical
/// palette from the design's data-viz guide, each hue stepped separately for
/// the light (white) and dark (deep-navy) card surface so lines read on both.
/// They carry no status meaning. Slots are assigned in a fixed order; the five
/// channels past eight reuse a slot (the legend names every line, so identity
/// never rests on color alone).
abstract final class _SeriesColors {
  static const _SeriesColor blue = (
    light: Color(0xFF2A78D6),
    dark: Color(0xFF3987E5),
  );
  static const _SeriesColor orange = (
    light: Color(0xFFEB6834),
    dark: Color(0xFFD95926),
  );
  static const _SeriesColor aqua = (
    light: Color(0xFF1BAF7A),
    dark: Color(0xFF199E70),
  );
  static const _SeriesColor yellow = (
    light: Color(0xFFEDA100),
    dark: Color(0xFFC98500),
  );
  static const _SeriesColor magenta = (
    light: Color(0xFFE87BA4),
    dark: Color(0xFFD55181),
  );
  static const _SeriesColor green = (
    light: Color(0xFF008300),
    dark: Color(0xFF008300),
  );
  static const _SeriesColor violet = (
    light: Color(0xFF6250D6),
    dark: Color(0xFF9085E9),
  );
  static const _SeriesColor red = (
    light: Color(0xFFE34948),
    dark: Color(0xFFE66767),
  );

  static Color resolve(BuildContext context, _SeriesColor c) =>
      Theme.of(context).brightness == Brightness.dark ? c.dark : c.light;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LiveGraphScreen extends StatefulWidget {
  const LiveGraphScreen({super.key});

  @override
  State<LiveGraphScreen> createState() => _LiveGraphScreenState();
}

class _LiveGraphScreenState extends State<LiveGraphScreen> {
  static final List<_Channel> _channels = [
    _Channel(
      id: 'rpm',
      label: 'RPM',
      unit: 'rpm',
      color: _SeriesColors.blue,
      maxY: 8000,
      extract: (d) => d.rpm,
    ),
    _Channel(
      id: 'speed',
      labelKey: 'dash_speed',
      label: 'Speed',
      unit: 'km/h',
      color: _SeriesColors.orange,
      maxY: 200,
      extract: (d) => d.speedKmh,
    ),
    _Channel(
      id: 'coolant',
      labelKey: 'dash_coolant',
      label: 'Coolant',
      unit: '°C',
      color: _SeriesColors.aqua,
      maxY: 130,
      extract: (d) => d.coolantTempC,
    ),
    _Channel(
      id: 'load',
      labelKey: 'dash_engine_load',
      label: 'Eng Load',
      unit: '%',
      color: _SeriesColors.yellow,
      maxY: 100,
      extract: (d) => d.engineLoad,
    ),
    _Channel(
      id: 'stft',
      label: 'STFT B1',
      unit: '%',
      color: _SeriesColors.magenta,
      maxY: 30,
      extract: (d) => d.fuelTrimShortPct,
    ),
    _Channel(
      id: 'ltft',
      label: 'LTFT B1',
      unit: '%',
      color: _SeriesColors.green,
      maxY: 30,
      extract: (d) => d.fuelTrimLongPct,
    ),
    _Channel(
      id: 'map',
      labelKey: 'dash_map',
      label: 'MAP',
      unit: 'kPa',
      color: _SeriesColors.violet,
      maxY: 150,
      extract: (d) => d.mapKpa,
    ),
    _Channel(
      id: 'timing',
      labelKey: 'timing',
      label: 'Timing',
      unit: '°',
      color: _SeriesColors.red,
      maxY: 40,
      extract: (d) => d.timingAdvanceDeg,
    ),
    _Channel(
      id: 'o2b1s1',
      label: 'O2 B1S1',
      unit: 'V',
      color: _SeriesColors.blue,
      maxY: 1.3,
      extract: (d) => d.o2B1S1Voltage,
    ),
    _Channel(
      id: 'o2b1s2',
      label: 'O2 B1S2',
      unit: 'V',
      color: _SeriesColors.aqua,
      maxY: 1.3,
      extract: (d) => d.o2B1S2Voltage,
    ),
    // Wide-band upstream sensor (0124/0134) and diesel channels; they only
    // collect points on cars that advertise those PIDs.
    _Channel(
      id: 'lambda',
      label: 'λ B1S1',
      unit: 'λ',
      color: _SeriesColors.violet,
      maxY: 2,
      extract: (d) => d.lambdaB1S1,
    ),
    _Channel(
      id: 'rail',
      labelKey: 'rail_pressure',
      label: 'Rail',
      unit: 'MPa',
      color: _SeriesColors.magenta,
      maxY: 250,
      extract: (d) =>
          d.fuelRailPressureKpa == null ? null : d.fuelRailPressureKpa! / 1000,
    ),
    _Channel(
      id: 'pedal',
      labelKey: 'accel_pedal',
      label: 'Pedal',
      unit: '%',
      color: _SeriesColors.yellow,
      maxY: 100,
      extract: (d) => d.acceleratorPedalPct,
    ),
  ];

  // Which channels are toggled on
  final Set<String> _active = {'rpm', 'speed', 'coolant'};

  // Ring buffer: id → list of (x, y) points
  final Map<String, Queue<FlSpot>> _buffers = {
    for (final c in _channels) c.id: Queue<FlSpot>(),
  };

  int _tick = 0;
  StreamSubscription<OBDLiveData>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = OBDService.instance.liveDataStream.listen(_onSample);
  }

  void _onSample(OBDLiveData data) {
    if (!mounted) return;
    setState(() {
      _tick++;
      for (final ch in _channels) {
        final val = ch.extract(data);
        if (val == null) continue;
        final q = _buffers[ch.id]!;
        q.add(FlSpot(_tick.toDouble(), val));
        if (q.length > _kMaxPoints) q.removeFirst();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String _label(_Channel ch) =>
      ch.labelKey == null ? ch.label : context.tr(ch.labelKey!);

  Color _color(_Channel ch) => _SeriesColors.resolve(context, ch.color);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('live_data_graph'),
              subtitle: context
                  .tr('graph_window')
                  .replaceAll('{n}', '${_kMaxPoints * 3 ~/ 60}'),
            ),
            _buildToggleRow(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.space20.w,
                  AppSizes.space12.h,
                  AppSizes.space20.w,
                  AppSizes.space20.h,
                ),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Expanded(child: _buildChart()),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: context.colors.border,
                      ),
                      _buildLegend(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Channel toggle chips ──────────────────────────────────────────────────

  Widget _buildToggleRow() {
    return SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space20.w,
          vertical: 4.h,
        ),
        itemCount: _channels.length,
        separatorBuilder: (_, _) => SizedBox(width: AppSizes.space8.w),
        itemBuilder: (_, i) {
          final ch = _channels[i];
          final on = _active.contains(ch.id);
          return AppFilterChip(
            label: _label(ch),
            selected: on,
            onTap: () => setState(() {
              if (on && _active.length > 1) {
                _active.remove(ch.id);
              } else {
                _active.add(ch.id);
              }
            }),
          );
        },
      ),
    );
  }

  /// Axis tick labels: 10 sp (just under the type scale's 11 sp caption) so
  /// the "100%" ticks fit the reserved axis width without crowding the chart.
  TextStyle get _axisStyle => AppTextStyles.numeric(
    AppTextStyles.caption,
  ).copyWith(fontSize: 10.sp, color: context.colors.muted);

  // ── Chart ─────────────────────────────────────────────────────────────────

  Widget _buildChart() {
    final p = context.colors;
    final activeChannels = _channels
        .where((c) => _active.contains(c.id))
        .toList();
    if (activeChannels.isEmpty) {
      return Center(
        child: Text(
          context.tr('select_channel'),
          style: AppTextStyles.body.copyWith(color: p.text2),
        ),
      );
    }

    // All series share one 0–100 % axis: each is normalised to its maxY.
    final lines = <LineChartBarData>[];
    final lineChannels = <_Channel>[];
    for (final ch in activeChannels) {
      final pts = _buffers[ch.id]!.toList();
      if (pts.isEmpty) continue;

      // X relative to now (0 = latest sample) so ticks land on round times.
      final normalised = pts
          .map((p) => FlSpot(p.x - _tick, (p.y / ch.maxY) * 100))
          .toList();

      lineChannels.add(ch);
      lines.add(
        LineChartBarData(
          spots: normalised,
          isCurved: true,
          curveSmoothness: 0.3,
          color: _color(ch),
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    // X range: the last _kMaxPoints samples, ending at "now" (0).
    const minX = -_kMaxPoints * 1.0;
    const maxX = 0.0;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(4.w, 16.h, 16.w, 8.h),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: 100,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: p.border, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 40.w,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  space: 4.w,
                  child: Text(
                    maxLines: 1,
                    softWrap: false,
                    '${v.toInt()}%',
                    textDirection: TextDirection.ltr,
                    style: _axisStyle,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _kMaxPoints / 4,
                reservedSize: 24.h,
                getTitlesWidget: (v, meta) {
                  final secsAgo = (-v * 3).round();
                  return SideTitleWidget(
                    meta: meta,
                    space: 6.h,
                    // Keeps the edge labels ("now" in Arabic is wider)
                    // inside the card.
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      secsAgo == 0 ? context.tr('graph_now') : '-${secsAgo}s',
                      textDirection: TextDirection.ltr,
                      style: _axisStyle,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: lines,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => p.surface,
              tooltipBorder: BorderSide(color: p.border),
              getTooltipItems: (spots) {
                return spots.map((s) {
                  final ch = lineChannels[s.barIndex];
                  final real = (s.y / 100) * ch.maxY;
                  return LineTooltipItem(
                    '${_label(ch)}: ${real.toStringAsFixed(1)} ${ch.unit}',
                    AppTextStyles.numeric(
                      AppTextStyles.caption,
                    ).copyWith(color: p.text, fontWeight: FontWeight.w600),
                  );
                }).toList();
              },
            ),
          ),
        ),
        duration: const Duration(milliseconds: 0), // no animation — real-time
      ),
    );
  }

  // ── Legend (current values) ────────────────────────────────────────────────

  Widget _buildLegend() {
    final p = context.colors;
    final active = _channels.where((c) => _active.contains(c.id)).toList();
    return Padding(
      padding: EdgeInsets.all(AppSizes.space16.r),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: AppSizes.space16.w,
          runSpacing: AppSizes.space8.h,
          children: active.map((ch) {
            final q = _buffers[ch.id]!;
            final val = q.isEmpty ? null : q.last.y;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12.r,
                  height: 4.r,
                  decoration: BoxDecoration(
                    color: _color(ch),
                    borderRadius: BorderRadius.circular(AppSizes.radiusXs.r),
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  '${_label(ch)} ',
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
                Text(
                  val != null ? '${val.toStringAsFixed(1)} ${ch.unit}' : '--',
                  // Number + Latin unit keep their order in RTL.
                  textDirection: TextDirection.ltr,
                  style: AppTextStyles.numeric(
                    AppTextStyles.label,
                  ).copyWith(fontWeight: FontWeight.w600, color: p.text),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
