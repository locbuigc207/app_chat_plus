// lib/widgets/weekly_recap_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/weekly_recap_service.dart';
import 'recap_bubble_widget.dart';

// ══════════════════════════════════════════════════════════════════════════════
// STYLE THEME MAP  (dùng chung với recap_bubble_widget)
// ══════════════════════════════════════════════════════════════════════════════

const Map<RecapStyle, _CardTheme> _kCardThemes = {
  RecapStyle.humorous: _CardTheme(
    colorA: Color(0xFFBF360C), colorB: Color(0xFFFF8F00),
    accent: Color(0xFFFFCC80), icon: Icons.emoji_emotions_rounded, bgIcon: '🎭',
  ),
  RecapStyle.professional: _CardTheme(
    colorA: Color(0xFF0A1628), colorB: Color(0xFF1565C0),
    accent: Color(0xFF82B1FF), icon: Icons.analytics_rounded, bgIcon: '📊',
  ),
  RecapStyle.romantic: _CardTheme(
    colorA: Color(0xFF4A0E2B), colorB: Color(0xFFAD1457),
    accent: Color(0xFFF48FB1), icon: Icons.favorite_rounded, bgIcon: '💕',
  ),
  RecapStyle.tvHost: _CardTheme(
    colorA: Color(0xFF1A0A00), colorB: Color(0xFFE65100),
    accent: Color(0xFFFFCC80), icon: Icons.live_tv_rounded, bgIcon: '🎬',
  ),
  RecapStyle.minimal: _CardTheme(
    colorA: Color(0xFF102027), colorB: Color(0xFF455A64),
    accent: Color(0xFFB0BEC5), icon: Icons.format_list_bulleted_rounded, bgIcon: '📝',
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
// WEEKLY RECAP CARD
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

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _rotateAnim = Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final ct = _kCardThemes[widget.recap.style] ?? _kCardThemes[RecapStyle.professional]!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ct.colorB.withValues(alpha: 0.22), width: 1.5),
        boxShadow: [
          BoxShadow(color: ct.colorB.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: p.shadow, blurRadius: 8, offset: const Offset(0, 2)),
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
            ]),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                widget.recap.recapTitle,
                style: const TextStyle(
                  color: Colors.white, fontSize: 15.5,
                  fontWeight: FontWeight.w700, letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.conversationName,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
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
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh
          if (widget.onRefresh != null)
            GestureDetector(
              onTap: widget.onRefresh,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  Widget _buildSummary(ThemePalette p, _CardTheme ct) {
    final previewLines = _expanded ? 100 : 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Big emoji decoration
        Row(children: [
          Text(ct.bgIcon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.recap.summary.isNotEmpty ? widget.recap.summary : widget.recap.recapTitle,
              style: TextStyle(color: p.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Full text (truncated)
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: Text(
            widget.recap.fullText,
            style: TextStyle(color: p.textSecondary, fontSize: 13.5, height: 1.68),
            maxLines: previewLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        // Expand/Collapse
        GestureDetector(
          onTap: _toggleExpanded,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            RotationTransition(
              turns: _rotateAnim,
              child: Icon(Icons.expand_more_rounded, size: 18, color: ct.colorB),
            ),
            const SizedBox(width: 4),
            Text(
              _expanded ? 'Thu gọn' : 'Đọc thêm',
              style: TextStyle(color: ct.colorB, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Expandable: Highlights + Keywords ─────────────────────────────────────
  Widget _buildExpandableContent(ThemePalette p, _CardTheme ct) {
    if (!widget.recap.hasHighlights && !widget.recap.hasKeywords) return const SizedBox.shrink();

    return SizeTransition(
      sizeFactor: _expandAnim,
      child: FadeTransition(
        opacity: _expandAnim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Highlights
            if (widget.recap.hasHighlights) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ct.colorB.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ct.colorB.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: ct.colorB),
                      const SizedBox(width: 6),
                      Text('Điểm nổi bật',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ct.colorB)),
                    ]),
                    const SizedBox(height: 10),
                    ...widget.recap.highlights.asMap().entries.map((e) => Padding(
                      padding: EdgeInsets.only(bottom: e.key < widget.recap.highlights.length - 1 ? 8 : 0),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [ct.colorA, ct.colorB]),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(e.value,
                              style: TextStyle(fontSize: 13.5, color: p.textSecondary, height: 1.45)),
                        ),
                      ]),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Keywords
            if (widget.recap.hasKeywords) ...[
              Text('Từ khoá nổi bật',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.textSecondary)),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                ...widget.recap.topKeywords.map((kw) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ct.colorB.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: ct.colorB.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('#', style: TextStyle(fontSize: 11, color: ct.colorB, fontWeight: FontWeight.w700)),
                    Text(kw, style: TextStyle(fontSize: 12, color: p.textSecondary, fontWeight: FontWeight.w500)),
                  ]),
                )),
              ]),
            ],
          ]),
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
          // Stats chips
          _StatChip(icon: Icons.chat_bubble_outline_rounded,
              label: '${widget.recap.messageCount}', color: p.textHint, palette: p),
          const SizedBox(width: 8),
          _StatChip(icon: Icons.calendar_today_rounded,
              label: '${widget.recap.lookbackDays}d', color: p.textHint, palette: p),
          const SizedBox(width: 8),
          _StatChip(icon: Icons.access_time_rounded,
              label: DateFormat('HH:mm').format(widget.recap.generatedAt),
              color: p.textHint, palette: p),
          const Spacer(),
          // Share button
          if (widget.showShareButton)
            GestureDetector(
              onTap: () => _openShare(context, ct),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [ct.colorA, ct.colorB],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: ct.colorB.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.share_rounded, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Chia sẻ', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  void _openShare(BuildContext context, _CardTheme ct) {
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

// ── Stat Chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final ThemePalette palette;

  const _StatChip({required this.icon, required this.label, required this.color, required this.palette});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: palette.surfaceVariant,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w500)),
    ]),
  );
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
              ? LinearGradient(colors: [ct.colorA, ct.colorB],
              begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: selected ? null : p.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.transparent : p.divider,
            width: selected ? 0 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: ct.colorB.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(ct.icon, size: 22, color: selected ? Colors.white : p.textSecondary),
              if (isCached)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    width: 8, height: 8,
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
            style.label.replaceFirst(RegExp(r'^[^\s]+\s'), ''), // Remove emoji
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : p.textSecondary,
            ),
          ),
        ]),
      ),
    );
  }
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor.withValues(alpha: 0.15), theme.primaryColor.withValues(alpha: 0.05)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 40, color: theme.primaryColor),
          ),
          const SizedBox(height: 20),
          Text(
            conversationType == 'personal' ? 'Kỷ niệm tuần đang chờ bạn! 🌟' : 'Nhóm chưa có tổng kết tuần 📊',
            style: TextStyle(color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'AI sẽ đọc các tin nhắn an toàn trong tuần và tạo một bản tóm tắt độc đáo cho bạn.',
            style: TextStyle(color: p.textSecondary, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onGenerate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.primaryColor, theme.primaryLightColor ?? theme.primaryColor],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: theme.primaryColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Tạo Tổng Kết Ngay', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class RecapErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const RecapErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>().palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 56, color: p.dangerColor),
          const SizedBox(height: 16),
          Text('Không thể tạo tóm tắt',
              style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: p.textSecondary, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }
}