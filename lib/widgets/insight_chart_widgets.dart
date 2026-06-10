// lib/widgets/insight_chart_widgets.dart
// TÍNH NĂNG 2: USER INSIGHTS — Chart widgets hoàn chỉnh
// Gồm: SentimentBar, MoodTrendChart, ActivityHeatmapChart, TopicsBarChart
// Tất cả dùng CustomPainter, không cần package chart ngoài

import 'package:flutter/material.dart';

import '../models/insights_models.dart';
import '../providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SentimentBar — animated 3-section bar (positive / neutral / negative)
// ─────────────────────────────────────────────────────────────────────────────

class SentimentBar extends StatefulWidget {
  final SentimentBreakdown breakdown;
  final ThemePalette palette;

  const SentimentBar({
    super.key,
    required this.breakdown,
    required this.palette,
  });

  @override
  State<SentimentBar> createState() => _SentimentBarState();
}

class _SentimentBarState extends State<SentimentBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.breakdown;
    final p = widget.palette;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final t = _anim.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: [
                  _BarSegment(
                      flex: (b.positive * t * 100).round(),
                      color: const Color(0xFF22C55E)),
                  _BarSegment(
                      flex: (b.neutral * t * 100).round(),
                      color: const Color(0xFF94A3B8)),
                  _BarSegment(
                      flex: (b.negative * t * 100).round(),
                      color: const Color(0xFFEF4444)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Legend
            Row(
              children: [
                _LegendDot(
                    color: const Color(0xFF22C55E),
                    label: 'Tích cực ${(b.positive * 100).round()}%',
                    palette: p),
                const SizedBox(width: 16),
                _LegendDot(
                    color: const Color(0xFF94A3B8),
                    label: 'Trung lập ${(b.neutral * 100).round()}%',
                    palette: p),
                const SizedBox(width: 16),
                _LegendDot(
                    color: const Color(0xFFEF4444),
                    label: 'Tiêu cực ${(b.negative * 100).round()}%',
                    palette: p),
              ],
            ),
            const SizedBox(height: 8),
            // Trend badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _trendColor(b.trend).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: _trendColor(b.trend).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_trendIcon(b.trend),
                      size: 13, color: _trendColor(b.trend)),
                  const SizedBox(width: 5),
                  Text(_trendLabel(b.trend),
                      style: TextStyle(
                          color: _trendColor(b.trend),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Color _trendColor(String trend) => switch (trend) {
        'improving' => const Color(0xFF22C55E),
        'declining' => const Color(0xFFEF4444),
        _ => const Color(0xFF94A3B8),
      };

  IconData _trendIcon(String trend) => switch (trend) {
        'improving' => Icons.trending_up_rounded,
        'declining' => Icons.trending_down_rounded,
        _ => Icons.trending_flat_rounded,
      };

  String _trendLabel(String trend) => switch (trend) {
        'improving' => 'Đang tích cực hơn',
        'declining' => 'Đang ít tích cực hơn',
        _ => 'Tâm trạng ổn định',
      };
}

class _BarSegment extends StatelessWidget {
  final int flex;
  final Color color;
  const _BarSegment({required this.flex, required this.color});

  @override
  Widget build(BuildContext context) => Flexible(
        flex: flex.clamp(1, 100),
        child: Container(height: 14, color: color),
      );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final ThemePalette palette;
  const _LegendDot(
      {required this.color, required this.label, required this.palette});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MoodTrendChart — bezier smooth line chart với gradient fill
// ─────────────────────────────────────────────────────────────────────────────

class MoodTrendChart extends StatefulWidget {
  final List<MoodPoint> points;
  final ThemePalette palette;
  final Color lineColor;

  const MoodTrendChart({
    super.key,
    required this.points,
    required this.palette,
    required this.lineColor,
  });

  @override
  State<MoodTrendChart> createState() => _MoodTrendChartState();
}

class _MoodTrendChartState extends State<MoodTrendChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return Center(
        child: Text('Chưa đủ dữ liệu',
            style: TextStyle(color: widget.palette.textHint, fontSize: 13)),
      );
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => GestureDetector(
        onTapDown: (d) => _onTap(d.localPosition, context),
        onTapUp: (_) => setState(() => _hoveredIndex = null),
        child: CustomPaint(
          painter: _MoodLinePainter(
            points: widget.points,
            progress: _anim.value,
            lineColor: widget.lineColor,
            palette: widget.palette,
            hoveredIndex: _hoveredIndex,
          ),
          child: const SizedBox(width: double.infinity, height: 160),
        ),
      ),
    );
  }

  void _onTap(Offset pos, BuildContext ctx) {
    final w = ctx.size?.width ?? 0;
    if (w == 0 || widget.points.isEmpty) return;
    final spacing = w / (widget.points.length - 1).clamp(1, 999);
    final idx =
        ((pos.dx - 16) / spacing).round().clamp(0, widget.points.length - 1);
    setState(() => _hoveredIndex = idx);
  }
}

class _MoodLinePainter extends CustomPainter {
  final List<MoodPoint> points;
  final double progress;
  final Color lineColor;
  final ThemePalette palette;
  final int? hoveredIndex;

  _MoodLinePainter({
    required this.points,
    required this.progress,
    required this.lineColor,
    required this.palette,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const padL = 16.0, padR = 16.0, padT = 16.0, padB = 32.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final n = points.length;
    final dx = n > 1 ? w / (n - 1) : w;

    Offset pt(int i) {
      final x = padL + i * dx;
      final y = padT + h * (1 - points[i].score);
      return Offset(x, y);
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = palette.divider.withValues(alpha: 0.5)
      ..strokeWidth = 0.6;
    for (int i = 0; i <= 4; i++) {
      final y = padT + h * i / 4;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
    }

    // Build path (bezier)
    final visibleN = (n * progress).round().clamp(2, n);
    final path = Path();
    path.moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < visibleN; i++) {
      final p0 = pt(i - 1);
      final p1 = pt(i);
      final cpX = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
    }

    // Gradient fill
    final fillPath = Path.from(path);
    final lastPt = pt(visibleN - 1);
    fillPath.lineTo(lastPt.dx, padT + h);
    fillPath.lineTo(padL, padT + h);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, padT, size.width, h)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dots
    for (int i = 0; i < visibleN; i++) {
      final p = pt(i);
      final isHov = hoveredIndex == i;
      canvas.drawCircle(
          p,
          isHov ? 7.0 : 4.0,
          Paint()
            ..color = isHov ? lineColor : lineColor.withValues(alpha: 0.7));
      canvas.drawCircle(p, isHov ? 4.0 : 2.0, Paint()..color = Colors.white);
    }

    // Hovered tooltip
    if (hoveredIndex != null && hoveredIndex! < visibleN) {
      final p = pt(hoveredIndex!);
      final mp = points[hoveredIndex!];
      final label =
          '${mp.emoji} ${(mp.score * 100).round()}%  ${mp.messageCount} tin';

      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: palette.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);

      const pad = 6.0;
      final rx = (p.dx - tp.width / 2 - pad)
          .clamp(4.0, size.width - tp.width - 2 * pad - 4);
      final ry = p.dy - tp.height - pad * 2 - 10;

      final rRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(rx, ry.clamp(2.0, size.height - 30), tp.width + pad * 2,
              tp.height + pad * 2),
          const Radius.circular(8));

      canvas.drawRRect(
          rRect,
          Paint()
            ..color = palette.surface
            ..style = PaintingStyle.fill);
      canvas.drawRRect(
          rRect,
          Paint()
            ..color = lineColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      tp.paint(canvas, Offset(rx + pad, ry.clamp(2.0, size.height - 30) + pad));
    }

    // X-axis labels (first, middle, last)
    if (n >= 2) {
      void drawLabel(int i, String text) {
        final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(color: palette.textHint, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = padL + i * dx - tp.width / 2;
        tp.paint(
            canvas,
            Offset(
                x.clamp(0.0, size.width - tp.width), size.height - padB + 4));
      }

      String _fmtDate(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      drawLabel(0, _fmtDate(points.first.date));
      if (n > 2) drawLabel(n ~/ 2, _fmtDate(points[n ~/ 2].date));
      drawLabel(n - 1, _fmtDate(points.last.date));
    }
  }

  @override
  bool shouldRepaint(_MoodLinePainter old) =>
      old.progress != progress ||
      old.hoveredIndex != hoveredIndex ||
      old.points.length != points.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// ActivityHeatmapChart — 7×24 grid
// ─────────────────────────────────────────────────────────────────────────────

class ActivityHeatmapChart extends StatefulWidget {
  final List<ActivitySlot> slots;
  final ThemePalette palette;
  final Color baseColor;

  const ActivityHeatmapChart({
    super.key,
    required this.slots,
    required this.palette,
    required this.baseColor,
  });

  @override
  State<ActivityHeatmapChart> createState() => _ActivityHeatmapChartState();
}

class _ActivityHeatmapChartState extends State<ActivityHeatmapChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  int? _tappedIdx;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final p = widget.palette;

    if (widget.slots.isEmpty) {
      return Center(
          child: Text('Chưa đủ dữ liệu',
              style: TextStyle(color: p.textHint, fontSize: 13)));
    }

    // Build lookup
    final lookup = <String, ActivitySlot>{};
    for (final s in widget.slots) {
      lookup['${s.dayOfWeek}_${s.hour}'] = s;
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hour labels top
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [0, 6, 12, 18, 23].map((h) {
                return Text(
                  '${h.toString().padLeft(2, '0')}h',
                  style: TextStyle(color: p.textHint, fontSize: 9.5),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          ...List.generate(7, (d) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(days[d],
                        style: TextStyle(
                            color: p.textHint,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Row(
                      children: List.generate(24, (h) {
                        final slot = lookup['${d}_$h'];
                        final intensity =
                            (slot?.intensity ?? 0.0) * _anim.value;
                        final isTapped = _tappedIdx == d * 24 + h;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() =>
                                _tappedIdx = isTapped ? null : d * 24 + h),
                            child: Padding(
                              padding: const EdgeInsets.all(1),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color: isTapped
                                        ? widget.baseColor
                                        : intensity < 0.05
                                            ? p.divider.withValues(alpha: 0.3)
                                            : widget.baseColor.withValues(
                                                alpha: 0.15 + intensity * 0.75),
                                    borderRadius: BorderRadius.circular(3),
                                    border: isTapped
                                        ? Border.all(
                                            color: widget.baseColor, width: 1)
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // Tooltip
          if (_tappedIdx != null) ...[
            Builder(builder: (_) {
              final d = _tappedIdx! ~/ 24;
              final h = _tappedIdx! % 24;
              final slot = lookup['${d}_$h'];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: widget.baseColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: widget.baseColor.withValues(alpha: 0.3))),
                child: Text(
                  '${days[d]} ${h.toString().padLeft(2, '0')}:00 — ${slot?.count ?? 0} tin nhắn',
                  style: TextStyle(
                      color: widget.baseColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
          // Legend
          Row(
            children: [
              Text('Ít', style: TextStyle(color: p.textHint, fontSize: 11)),
              const SizedBox(width: 6),
              Row(
                children: [0.1, 0.3, 0.5, 0.7, 0.9].map((v) {
                  return Container(
                    width: 16,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color:
                          widget.baseColor.withValues(alpha: 0.15 + v * 0.75),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 6),
              Text('Nhiều', style: TextStyle(color: p.textHint, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TopicsBarChart — horizontal animated bars
// ─────────────────────────────────────────────────────────────────────────────

class TopicsBarChart extends StatefulWidget {
  final List<TopicTag> topics;
  final ThemePalette palette;

  const TopicsBarChart({
    super.key,
    required this.topics,
    required this.palette,
  });

  @override
  State<TopicsBarChart> createState() => _TopicsBarChartState();
}

class _TopicsBarChartState extends State<TopicsBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  static const _colors = [
    Color(0xFF6366F1),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final topics = widget.topics.take(8).toList();

    if (topics.isEmpty) {
      return Center(
          child: Text('Chưa đủ dữ liệu',
              style: TextStyle(color: p.textHint, fontSize: 13)));
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        children: topics.asMap().entries.map((entry) {
          final i = entry.key;
          final topic = entry.value;
          final color = _colors[i % _colors.length];
          final pct = topic.percentage * _anim.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                // Emoji + label
                Text(topic.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  child: Text(
                    topic.topic,
                    style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Bar
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                          height: 10,
                          decoration: BoxDecoration(
                              color: p.divider.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(999))),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0.02, 1.0),
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color, color.withValues(alpha: 0.6)],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                  color: color.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1))
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Percentage
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(topic.percentage * 100).round()}%',
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
