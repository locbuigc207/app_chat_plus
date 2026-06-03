// lib/widgets/weekly_recap_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/models/ai_models.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class WeeklyRecapCard extends StatefulWidget {
  final WeeklyRecapResult recap;
  final bool expanded;

  const WeeklyRecapCard({
    super.key,
    required this.recap,
    this.expanded = true,
  });

  @override
  State<WeeklyRecapCard> createState() => _WeeklyRecapCardState();
}

class _WeeklyRecapCardState extends State<WeeklyRecapCard>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.expanded;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.expanded ? 1.0 : 0.0,
    );
    _expandAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  Color _sentimentColor(ThemePalette p) => switch (widget.recap.sentiment) {
        'positive' => p.successColor,
        'negative' => p.dangerColor,
        _ => p.infoColor,
      };

  String _sentimentLabel() => switch (widget.recap.sentiment) {
        'positive' => '😊 Tích cực',
        'negative' => '😔 Tiêu cực',
        _ => '😐 Trung tính',
      };

  String _sentimentEmoji() => switch (widget.recap.sentiment) {
        'positive' => '🌟',
        'negative' => '⛅',
        _ => '🌤',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final p = theme.palette;
    final sc = _sentimentColor(p);
    final primary = theme.primaryColor;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header gradient
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primary.withValues(alpha: 0.06),
                    sc.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primary, sc],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('📊', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tóm tắt tuần',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM/yyyy')
                              .format(widget.recap.generatedAt),
                          style: TextStyle(fontSize: 11.5, color: p.textHint),
                        ),
                      ],
                    ),
                  ),
                  // Sentiment badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: sc.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      _sentimentLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sc,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggle,
                    child: AnimatedRotation(
                      turns: _isExpanded ? 0 : -0.5,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: p.textHint,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            SizeTransition(
              sizeFactor: _expandAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary text
                      if (widget.recap.summary.isNotEmpty) ...[
                        Text(
                          widget.recap.summary,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: p.textSecondary,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Highlights
                      if (widget.recap.highlights.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text('✨', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              'Điểm nổi bật',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: p.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...widget.recap.highlights.map(
                          (h) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    h,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: p.textSecondary,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Footer timestamp
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded,
                                size: 12, color: p.textHint),
                            const SizedBox(width: 5),
                            Text(
                              'Tạo lúc ${DateFormat('HH:mm, dd/MM/yyyy').format(widget.recap.generatedAt)}',
                              style: TextStyle(fontSize: 11, color: p.textHint),
                            ),
                          ],
                        ),
                      ),
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
}
