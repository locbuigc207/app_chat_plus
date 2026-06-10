import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/insights_models.dart';
import '../providers/theme_provider.dart';
import '../services/weekly_recap_service.dart';
import '../widgets/widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
// STYLE THEME MAP  (dùng chung cho cả WeeklyRecapCard & RecapStyleChip)
// ══════════════════════════════════════════════════════════════════════════════

const Map<RecapStyle, _CardTheme> _kCardThemes = {
  RecapStyle.humorous: _CardTheme(
    colorA: Color(0xFFBF360C),
    colorB: Color(0xFFFF8F00),
    accent: Color(0xFFFFCC80),
    icon: Icons.emoji_emotions_rounded,
    bgIcon: '🎭',
  ),
  RecapStyle.professional: _CardTheme(
    colorA: Color(0xFF0A1628),
    colorB: Color(0xFF1565C0),
    accent: Color(0xFF82B1FF),
    icon: Icons.analytics_rounded,
    bgIcon: '📊',
  ),
  RecapStyle.romantic: _CardTheme(
    colorA: Color(0xFF4A0E2B),
    colorB: Color(0xFFAD1457),
    accent: Color(0xFFF48FB1),
    icon: Icons.favorite_rounded,
    bgIcon: '💕',
  ),
  RecapStyle.tvHost: _CardTheme(
    colorA: Color(0xFF1A0A00),
    colorB: Color(0xFFE65100),
    accent: Color(0xFFFFCC80),
    icon: Icons.live_tv_rounded,
    bgIcon: '🎬',
  ),
  RecapStyle.minimal: _CardTheme(
    colorA: Color(0xFF102027),
    colorB: Color(0xFF455A64),
    accent: Color(0xFFB0BEC5),
    icon: Icons.format_list_bulleted_rounded,
    bgIcon: '📝',
  ),
};

class _CardTheme {
  final Color colorA;
  final Color colorB;
  final Color accent;
  final IconData icon;
  final String bgIcon;

  const _CardTheme({
    required this.colorA,
    required this.colorB,
    required this.accent,
    required this.icon,
    required this.bgIcon,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// WEEKLY RECAP CARD  (dựa trên WeeklyRecapData từ weekly_recap_service.dart)
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyRecapCard extends StatefulWidget {
  final WeeklyRecapData recap;
  final String conversationName;
  final bool showShareButton;
  final VoidCallback? onRefresh;
  final bool initiallyExpanded;

  const WeeklyRecapCard({
    super.key,
    required this.recap,
    required this.conversationName,
    this.showShareButton = true,
    this.onRefresh,
    this.initiallyExpanded = false,
  });

  @override
  State<WeeklyRecapCard> createState() => _WeeklyRecapCardState();
}

class _WeeklyRecapCardState extends State<WeeklyRecapCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  late final Animation<double> _rotateAnim;
  final GlobalKey _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnim =
        CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _rotateAnim = Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    _expanded ? _expandCtrl.forward() : _expandCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final ct = _kCardThemes[widget.recap.style] ??
        _kCardThemes[RecapStyle.professional]!;

    return RepaintBoundary(
      key: _shareKey,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(22),
          border:
              Border.all(color: ct.colorB.withValues(alpha: 0.22), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: ct.colorB.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8)),
            BoxShadow(
                color: p.shadow, blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(p, ct),
              _buildSummary(p, ct),
              _buildExpandableContent(p, ct),
              _buildFooter(p, ct),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(ThemePalette p, _CardTheme ct) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [ct.colorA, ct.colorB],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          // Style icon circle
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(ct.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recap.recapTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.conversationName,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Sentiment pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Text(
              '${widget.recap.sentimentEmoji} ${widget.recap.sentimentLabel}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh
          if (widget.onRefresh != null)
            GestureDetector(
              onTap: widget.onRefresh,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  Widget _buildSummary(ThemePalette p, _CardTheme ct) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big emoji decoration + title
          Row(
            children: [
              Text(ct.bgIcon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.recap.summary.isNotEmpty
                      ? widget.recap.summary
                      : widget.recap.recapTitle,
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Full text (truncated / expanded)
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: Text(
              widget.recap.fullText,
              style: TextStyle(
                  color: p.textSecondary, fontSize: 13.5, height: 1.68),
              maxLines: _expanded ? 100 : 4,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          // Expand / Collapse toggle
          GestureDetector(
            onTap: _toggleExpanded,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _rotateAnim,
                  child: Icon(Icons.expand_more_rounded,
                      size: 18, color: ct.colorB),
                ),
                const SizedBox(width: 4),
                Text(
                  _expanded ? 'Thu gọn' : 'Đọc thêm',
                  style: TextStyle(
                      color: ct.colorB,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Expandable: Highlights + Keywords ─────────────────────────────────────
  Widget _buildExpandableContent(ThemePalette p, _CardTheme ct) {
    if (!widget.recap.hasHighlights && !widget.recap.hasKeywords) {
      return const SizedBox.shrink();
    }

    return SizeTransition(
      sizeFactor: _expandAnim,
      child: FadeTransition(
        opacity: _expandAnim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Highlights
              if (widget.recap.hasHighlights) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ct.colorB.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: ct.colorB.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 14, color: ct.colorB),
                          const SizedBox(width: 6),
                          Text(
                            'Điểm nổi bật',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ct.colorB),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...widget.recap.highlights
                          .asMap()
                          .entries
                          .map((e) => Padding(
                                padding: EdgeInsets.only(
                                    bottom: e.key <
                                            widget.recap.highlights.length - 1
                                        ? 8
                                        : 0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(
                                          top: 6, right: 8),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            colors: [ct.colorA, ct.colorB]),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        e.value,
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            color: p.textSecondary,
                                            height: 1.45),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Keywords
              if (widget.recap.hasKeywords) ...[
                Text(
                  'Từ khoá nổi bật',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: widget.recap.topKeywords
                      .map((kw) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ct.colorB.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: ct.colorB.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('#',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: ct.colorB,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                  kw,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: p.textSecondary,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer: stats + share ──────────────────────────────────────────────────
  Widget _buildFooter(ThemePalette p, _CardTheme ct) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 16),
      child: Row(
        children: [
          _StatChip(
              icon: Icons.chat_bubble_outline_rounded,
              label: '${widget.recap.messageCount}',
              color: p.textHint,
              palette: p),
          const SizedBox(width: 8),
          _StatChip(
              icon: Icons.calendar_today_rounded,
              label: '${widget.recap.lookbackDays}d',
              color: p.textHint,
              palette: p),
          const SizedBox(width: 8),
          _StatChip(
              icon: Icons.access_time_rounded,
              label: DateFormat('HH:mm').format(widget.recap.generatedAt),
              color: p.textHint,
              palette: p),
          const Spacer(),
          // Share button
          if (widget.showShareButton)
            GestureDetector(
              onTap: () => _openShare(context, ct),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [ct.colorA, ct.colorB],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: ct.colorB.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.share_rounded, size: 15, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Chia sẻ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openShare(BuildContext context, _CardTheme ct) async {
    HapticFeedback.mediumImpact();
    try {
      final boundary =
          _shareKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      _showShareBottomSheet(context, bytes.buffer.asUint8List(), ct);
    } catch (_) {
      // Fallback: open recap share sheet nếu screenshot thất bại
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useSafeArea: true,
          builder: (_) => RecapShareSheet(
            recap: widget.recap,
            conversationName: widget.conversationName,
          ),
        );
      }
    }
  }

  void _showShareBottomSheet(
      BuildContext context, Uint8List bytes, _CardTheme ct) {
    final p = context.read<ThemeProvider>().palette;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: p.surface, borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.share_rounded, color: ct.colorB, size: 22),
                const SizedBox(width: 10),
                Text('Chia sẻ Recap',
                    style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes,
                  width: double.infinity, fit: BoxFit.fitWidth),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final content =
                      '${widget.recap.recapTitle} — ${widget.conversationName}\n'
                      '${widget.recap.summary}';
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('✅ Đã sao chép nội dung Recap!'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(12),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Sao chép nội dung'),
                style: FilledButton.styleFrom(
                  backgroundColor: ct.colorB,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INSIGHTS RECAP CARD  (dựa trên InsightsSnapshot từ insights_models.dart)
// ══════════════════════════════════════════════════════════════════════════════

class InsightsRecapCard extends StatefulWidget {
  final InsightsSnapshot snapshot;
  final ThemePalette palette;
  final Color primaryColor;
  final String peerName;

  const InsightsRecapCard({
    super.key,
    required this.snapshot,
    required this.palette,
    required this.primaryColor,
    required this.peerName,
  });

  @override
  State<InsightsRecapCard> createState() => _InsightsRecapCardState();
}

class _InsightsRecapCardState extends State<InsightsRecapCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  final GlobalKey _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _expandAnim =
        CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    _expanded ? _expandCtrl.forward() : _expandCtrl.reverse();
  }

  // Gradient color theo sentiment
  List<Color> get _gradientColors {
    final s = widget.snapshot.sentimentBreakdown;
    if (s.positive > 0.6) {
      return [const Color(0xFF22C55E), const Color(0xFF16A34A)];
    } else if (s.negative > 0.4) {
      return [const Color(0xFF6366F1), const Color(0xFF4F46E5)];
    }
    return [
      widget.primaryColor,
      widget.primaryColor.withValues(alpha: 0.7),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final p = widget.palette;

    return RepaintBoundary(
      key: _shareKey,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ─────────────────────────────────────────────────
              GestureDetector(
                onTap: _toggleExpand,
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recap ${s.period.label}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3),
                            ),
                            Text(
                              '${s.totalMessages} tin · ${s.activeDays} ngày hoạt động',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          // Share button
                          GestureDetector(
                            onTap: _onShare,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.ios_share_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Expand chevron
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 300),
                            child: const Icon(Icons.keyboard_arrow_down_rounded,
                                color: Colors.white, size: 22),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Summary text (always visible) ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Text(
                  s.insightSummary.isNotEmpty
                      ? s.insightSummary
                      : 'Chưa có đủ dữ liệu để tổng hợp.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 13.5,
                      height: 1.55),
                  maxLines: _expanded ? null : 2,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
              ),

              // ─── Expandable details ──────────────────────────────────────
              SizeTransition(
                sizeFactor: _expandAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 0.7,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    // Highlights grid
                    if (_buildHighlights(s).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _buildHighlights(s)
                              .map((h) => _HighlightChip(text: h))
                              .toList(),
                        ),
                      ),

                    // Stats row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      child: Row(
                        children: [
                          _StatItem(
                            icon: Icons.message_outlined,
                            value:
                                '${s.avgMessagesPerDay.toStringAsFixed(1)}/ngày',
                            label: 'Trung bình',
                          ),
                          const SizedBox(width: 12),
                          _StatItem(
                            icon: Icons.straighten_rounded,
                            value: '${s.avgMessageLength} ký tự',
                            label: 'Độ dài TB',
                          ),
                          const SizedBox(width: 12),
                          _StatItem(
                            icon: Icons.mood_rounded,
                            value: s.emojiUsageLevel == 'heavy'
                                ? '😊 Nhiều'
                                : s.emojiUsageLevel == 'moderate'
                                    ? '😊 Vừa'
                                    : '😊 Ít',
                            label: 'Emoji',
                          ),
                        ],
                      ),
                    ),

                    // AI summary nếu có
                    if (s.aiGeneratedSummary != null &&
                        s.aiGeneratedSummary!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white70, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.aiGeneratedSummary!,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12.5,
                                    height: 1.5,
                                    fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _buildHighlights(InsightsSnapshot s) {
    final list = <String>[];
    if (s.totalMessages > 0) list.add('📨 ${s.totalMessages} tin nhắn');
    if (s.activeDays > 0) list.add('📅 ${s.activeDays} ngày nhắn');
    if (s.topTopics.isNotEmpty) {
      list.add('${s.topTopics.first.emoji} Chủ đề: ${s.topTopics.first.topic}');
    }
    if (s.activityPattern == 'night_owl') {
      list.add('🌙 Cú đêm');
    } else if (s.activityPattern == 'morning_person') {
      list.add('☀️ Người sáng sớm');
    }
    for (final t in s.personalityTraits.take(2)) {
      list.add(_traitLabel(t));
    }
    return list;
  }

  String _traitLabel(String t) => switch (t) {
        'expressive' => '💬 Cởi mở',
        'communicative' => '🗣️ Hay trò chuyện',
        'direct' => '⚡ Thẳng thắn',
        'optimistic' => '😊 Lạc quan',
        'reflective' => '🤔 Suy tư',
        _ => '✨ Cân bằng',
      };

  Future<void> _onShare() async {
    HapticFeedback.mediumImpact();
    try {
      final boundary =
          _shareKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      _showShareDialog(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('[InsightsRecapCard] share error: $e');
    }
  }

  void _showShareDialog(Uint8List bytes) {
    final s = widget.snapshot;
    final p = widget.palette;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: p.surface, borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.share_rounded, color: widget.primaryColor, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Chia sẻ Recap',
                  style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes,
                  width: double.infinity, fit: BoxFit.fitWidth),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final content =
                      'APP_CHAT_PLUS Recap ${s.period.label} với ${widget.peerName}:\n'
                      '📊 ${s.totalMessages} tin · ${s.activeDays} ngày\n'
                      '${s.insightSummary}';
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('✅ Đã sao chép nội dung Recap!'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.all(12),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Sao chép nội dung'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECAP STYLE SELECTOR CHIP
// ══════════════════════════════════════════════════════════════════════════════

class RecapStyleChip extends StatelessWidget {
  final RecapStyle style;
  final bool selected;
  final VoidCallback onTap;
  final bool isCached;

  const RecapStyleChip({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
    this.isCached = false,
  });

  @override
  Widget build(BuildContext context) {
    final ct = _kCardThemes[style]!;
    final p = context.watch<ThemeProvider>().palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [ct.colorA, ct.colorB],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)
              : null,
          color: selected ? null : p.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.transparent : p.divider,
            width: selected ? 0 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: ct.colorB.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(ct.icon,
                    size: 22, color: selected ? Colors.white : p.textSecondary),
                if (isCached)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : ct.colorB,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              style.label
                  .replaceFirst(RegExp(r'^[^\s]+\s'), ''), // Remove emoji
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED HELPER WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

/// Stat chip nhỏ dùng trong footer của WeeklyRecapCard.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final ThemePalette palette;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

/// Highlight pill dùng trong InsightsRecapCard.
class _HighlightChip extends StatelessWidget {
  final String text;
  const _HighlightChip({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );
}

/// Stat item dùng trong InsightsRecapCard expanded row.
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white70, size: 14),
              const SizedBox(height: 5),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 10.5)),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// EMPTY / ERROR STATES
// ══════════════════════════════════════════════════════════════════════════════

class RecapEmptyState extends StatelessWidget {
  final String conversationType;
  final VoidCallback onGenerate;

  const RecapEmptyState({
    super.key,
    required this.conversationType,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.primaryColor.withValues(alpha: 0.15),
                    theme.primaryColor.withValues(alpha: 0.05)
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 40, color: theme.primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              conversationType == 'personal'
                  ? 'Kỷ niệm tuần đang chờ bạn! 🌟'
                  : 'Nhóm chưa có tổng kết tuần 📊',
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'AI sẽ đọc các tin nhắn an toàn trong tuần và tạo một bản tóm tắt độc đáo cho bạn.',
              style:
                  TextStyle(color: p.textSecondary, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onGenerate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.primaryColor,
                      theme.primaryLightColor ?? theme.primaryColor
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Tạo Tổng Kết Ngay',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecapErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const RecapErrorState(
      {super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>().palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: p.dangerColor),
            const SizedBox(height: 16),
            Text('Không thể tạo tóm tắt',
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                    color: p.textSecondary, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
