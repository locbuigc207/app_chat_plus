// lib/widgets/conversation_summary_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:provider/provider.dart';

class ConversationSummarySheet extends StatefulWidget {
  final List<String> messages;

  const ConversationSummarySheet({super.key, required this.messages});

  @override
  State<ConversationSummarySheet> createState() =>
      _ConversationSummarySheetState();
}

class _ConversationSummarySheetState extends State<ConversationSummarySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String? _summary;
  Map<String, dynamic>? _sentiment;
  KeyMomentsResult? _moments;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AIBackendService().summarizeConversation(
          messages: widget.messages,
          maxSentences: 4,
          language: 'vi',
        ),
        AIBackendService().analyzeSentiment(widget.messages),
        AIBackendService().extractKeyMoments(messages: widget.messages),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as String?;
        _sentiment = results[1] as Map<String, dynamic>?;
        _moments = results[2] as KeyMomentsResult?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.70,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: p.shadowStrong,
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0EA5E9), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'AI Phân Tích Chat',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  GestureDetector(
                    onTap: _loadAll,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: p.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.refresh_rounded,
                          size: 16, color: p.textHint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: p.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: theme.primaryColor,
              unselectedLabelColor: p.textSecondary,
              indicator: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.all(3),
              tabs: const [
                Tab(text: '📝 Tóm tắt'),
                Tab(text: '😊 Cảm xúc'),
                Tab(text: '⭐ Điểm nhấn'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: theme.primaryColor,
                          strokeWidth: 2.5,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'AI đang phân tích cuộc trò chuyện...',
                          style: TextStyle(color: p.textHint, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 52, color: p.dangerColor),
                              const SizedBox(height: 14),
                              Text(
                                'Không thể phân tích lúc này',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _loadAll,
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Thử lại'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : TabBarView(
                        controller: _tab,
                        children: [
                          _SummaryTab(
                            summary: _summary,
                            palette: p,
                            primary: theme.primaryColor,
                          ),
                          _SentimentTab(
                            sentiment: _sentiment,
                            palette: p,
                            primary: theme.primaryColor,
                          ),
                          _MomentsTab(
                            moments: _moments?.moments ?? [],
                            highlights: _moments?.highlights ?? [],
                            palette: p,
                            primary: theme.primaryColor,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Summary ─────────────────────────────────────────────────────────
class _SummaryTab extends StatelessWidget {
  final String? summary;
  final ThemePalette palette;
  final Color primary;

  const _SummaryTab(
      {this.summary, required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withValues(alpha: 0.12)),
              ),
              child: Text(
                summary?.isNotEmpty == true
                    ? summary!
                    : 'Không có đủ nội dung để tóm tắt.',
                style: TextStyle(
                  fontSize: 15,
                  color: palette.textPrimary,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (summary != null && summary!.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: summary!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Đã sao chép tóm tắt'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Sao chép tóm tắt'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      );
}

// ── Tab 2: Sentiment ────────────────────────────────────────────────────────
class _SentimentTab extends StatelessWidget {
  final Map<String, dynamic>? sentiment;
  final ThemePalette palette;
  final Color primary;

  const _SentimentTab(
      {this.sentiment, required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    if (sentiment == null) {
      return Center(
        child:
            Text('Không có dữ liệu', style: TextStyle(color: palette.textHint)),
      );
    }

    final score = (sentiment!['score'] as num?)?.toDouble() ?? 0.5;
    final emoji = sentiment!['emoji'] as String? ?? '😐';
    final mood = sentiment!['mood'] as String? ?? 'Trung tính';
    final trend = sentiment!['trend'] as String? ?? 'stable';
    final sentiment_ = sentiment!['sentiment'] as String? ?? 'neutral';

    Color barColor;
    if (score > 0.65) {
      barColor = const Color(0xFF22C55E);
    } else if (score > 0.4) {
      barColor = primary;
    } else {
      barColor = Colors.red;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          // Big emoji
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border:
                  Border.all(color: barColor.withValues(alpha: 0.2), width: 2),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 52)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mood,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(score * 100).round()}% tích cực',
            style: TextStyle(fontSize: 14, color: palette.textSecondary),
          ),
          const SizedBox(height: 22),
          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiêu cực',
                      style: TextStyle(fontSize: 11, color: palette.textHint)),
                  Text('Tích cực',
                      style: TextStyle(fontSize: 11, color: palette.textHint)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: score.clamp(0.0, 1.0),
                  minHeight: 12,
                  backgroundColor: palette.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Trend badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  switch (trend) {
                    'improving' => '📈',
                    'declining' => '📉',
                    _ => '➡️',
                  },
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  switch (trend) {
                    'improving' => 'Xu hướng đang tốt hơn',
                    'declining' => 'Xu hướng đang giảm dần',
                    _ => 'Xu hướng ổn định',
                  },
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Overall badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: barColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              switch (sentiment_) {
                'positive' => '✨ Cuộc trò chuyện tích cực',
                'negative' => '💭 Cuộc trò chuyện căng thẳng',
                _ => '🤝 Cuộc trò chuyện trung tính',
              },
              style: TextStyle(
                fontSize: 13,
                color: barColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 3: Key Moments ──────────────────────────────────────────────────────
class _MomentsTab extends StatelessWidget {
  final List<KeyMoment> moments;
  final List<String> highlights;
  final ThemePalette palette;
  final Color primary;

  const _MomentsTab({
    required this.moments,
    required this.highlights,
    required this.palette,
    required this.primary,
  });

  static const _cfg = <String, (String, Color)>{
    'funny': ('😂', Color(0xFFF59E0B)),
    'touching': ('❤️', Color(0xFFEC4899)),
    'important': ('⭐', Color(0xFF6366F1)),
    'decision': ('✅', Color(0xFF10B981)),
  };

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty && highlights.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌟', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 14),
            Text(
              'Chưa có khoảnh khắc đặc biệt',
              style: TextStyle(fontSize: 14, color: palette.textHint),
            ),
            const SizedBox(height: 6),
            Text(
              'Cần thêm tin nhắn để phân tích',
              style: TextStyle(fontSize: 12, color: palette.textHint),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Highlights section
        if (highlights.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '✨ Điểm nổi bật',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
          ),
          ...highlights.map(
            (h) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: palette.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (moments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '💫 Khoảnh khắc đáng nhớ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ],
        // Moments
        ...moments.map((m) {
          final cfg = _cfg[m.type] ?? ('📌', primary);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cfg.$2.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cfg.$2.withValues(alpha: 0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cfg.$1, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    m.content,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: palette.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
