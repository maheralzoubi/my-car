import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/obd_service.dart';

// ── Sensor channel definition ─────────────────────────────────────────────────

class _Channel {
  final String id;
  final String label;
  final String unit;
  final Color color;
  final double maxY;
  final double? Function(OBDLiveData) extract;

  const _Channel({
    required this.id,
    required this.label,
    required this.unit,
    required this.color,
    required this.maxY,
    required this.extract,
  });
}

const _kMaxPoints = 60; // 60 samples × 3 s poll = last 3 minutes

// ── Screen ────────────────────────────────────────────────────────────────────

class LiveGraphScreen extends StatefulWidget {
  const LiveGraphScreen({super.key});

  @override
  State<LiveGraphScreen> createState() => _LiveGraphScreenState();
}

class _LiveGraphScreenState extends State<LiveGraphScreen> {
  static final List<_Channel> _channels = [
    _Channel(id: 'rpm',    label: 'RPM',      unit: 'rpm',  color: const Color(0xFF00D9FF), maxY: 8000, extract: (d) => d.rpm),
    _Channel(id: 'speed',  label: 'Speed',    unit: 'km/h', color: const Color(0xFF00E676), maxY: 200,  extract: (d) => d.speedKmh),
    _Channel(id: 'coolant',label: 'Coolant',  unit: '°C',   color: const Color(0xFFFFD600), maxY: 130,  extract: (d) => d.coolantTempC),
    _Channel(id: 'load',   label: 'Eng Load', unit: '%',    color: const Color(0xFF9C27B0), maxY: 100,  extract: (d) => d.engineLoad),
    _Channel(id: 'stft',   label: 'STFT B1',  unit: '%',    color: const Color(0xFFFF6B35), maxY: 30,   extract: (d) => d.fuelTrimShortPct),
    _Channel(id: 'ltft',   label: 'LTFT B1',  unit: '%',    color: const Color(0xFFFF1744), maxY: 30,   extract: (d) => d.fuelTrimLongPct),
    _Channel(id: 'map',    label: 'MAP',      unit: 'kPa',  color: const Color(0xFF00BCD4), maxY: 150,  extract: (d) => d.mapKpa),
    _Channel(id: 'timing', label: 'Timing',   unit: '°',    color: const Color(0xFFCDDC39), maxY: 40,   extract: (d) => d.timingAdvanceDeg),
    _Channel(id: 'o2b1s1', label: 'O2 B1S1',  unit: 'V',    color: const Color(0xFFE91E63), maxY: 1.3,  extract: (d) => d.o2B1S1Voltage),
    _Channel(id: 'o2b1s2', label: 'O2 B1S2',  unit: 'V',    color: const Color(0xFFF48FB1), maxY: 1.3,  extract: (d) => d.o2B1S2Voltage),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildToggleRow(),
              Expanded(child: _buildChart()),
              _buildLegend(),
              SizedBox(height: 12.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 12.h, 20.w, 4.h),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('live_data_graph'),
            style: TextStyle(
              fontSize: 20.sp, fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          Text(
            '${_kMaxPoints * 3 ~/ 60} min window',
            style: TextStyle(fontSize: 11.sp,
                color: AppColors.textLight.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  // ── Channel toggle chips ──────────────────────────────────────────────────

  Widget _buildToggleRow() {
    return SizedBox(
      height: 38.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        children: _channels.map((ch) {
          final on = _active.contains(ch.id);
          return GestureDetector(
            onTap: () => setState(() {
              if (on && _active.length > 1) {
                _active.remove(ch.id);
              } else {
                _active.add(ch.id);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: 8.w),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: on ? ch.color.withValues(alpha: 0.2) : Colors.transparent,
                border: Border.all(
                  color: on ? ch.color : ch.color.withValues(alpha: 0.3),
                  width: on ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                ch.label,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: on ? ch.color : ch.color.withValues(alpha: 0.5),
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Chart ─────────────────────────────────────────────────────────────────

  Widget _buildChart() {
    final activeChannels = _channels.where((c) => _active.contains(c.id)).toList();
    if (activeChannels.isEmpty) {
      return Center(
        child: Text(context.tr('select_channel'),
            style: TextStyle(color: AppColors.textLight.withValues(alpha: 0.5))),
      );
    }

    // Determine Y range from the first active channel (normalise all to 0–1 for multi-axis)
    final lines = <LineChartBarData>[];
    for (final ch in activeChannels) {
      final pts = _buffers[ch.id]!.toList();
      if (pts.isEmpty) continue;

      // Normalise to 0–100 scale for unified Y axis
      final normalised = pts.map((p) => FlSpot(p.x, (p.y / ch.maxY) * 100)).toList();

      lines.add(LineChartBarData(
        spots: normalised,
        isCurved: true,
        curveSmoothness: 0.3,
        color: ch.color,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: ch.color.withValues(alpha: 0.05),
        ),
      ));
    }

    // X range: last _kMaxPoints ticks
    final minX = (_tick - _kMaxPoints).toDouble();
    final maxX = _tick.toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 12.h, 16.w, 8.h),
      child: LineChart(
        LineChartData(
          minX: minX, maxX: maxX,
          minY: 0,    maxY: 100,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 30.w,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}%',
                  style: TextStyle(
                      fontSize: 9.sp,
                      color: AppColors.textLight.withValues(alpha: 0.4)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _kMaxPoints / 4,
                getTitlesWidget: (v, _) {
                  final secsAgo = ((_tick - v) * 3).toInt();
                  return Text(
                    secsAgo == 0 ? 'now' : '-${secsAgo}s',
                    style: TextStyle(
                        fontSize: 9.sp,
                        color: AppColors.textLight.withValues(alpha: 0.4)),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          lineBarsData: lines,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceDark,
              getTooltipItems: (spots) {
                return spots.map((s) {
                  final ch = activeChannels[spots.indexOf(s)];
                  final real = (s.y / 100) * ch.maxY;
                  return LineTooltipItem(
                    '${ch.label}: ${real.toStringAsFixed(1)} ${ch.unit}',
                    TextStyle(color: ch.color, fontSize: 11.sp,
                        fontWeight: FontWeight.w600),
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
    final active = _channels.where((c) => _active.contains(c.id)).toList();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Wrap(
        spacing: 12.w, runSpacing: 6.h,
        children: active.map((ch) {
          final q = _buffers[ch.id]!;
          final val = q.isEmpty ? null : q.last.y;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10.w, height: 3.h,
                decoration: BoxDecoration(
                  color: ch.color,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                '${ch.label}: ${val != null ? '${val.toStringAsFixed(1)} ${ch.unit}' : '--'}',
                style: TextStyle(fontSize: 11.sp, color: ch.color),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
