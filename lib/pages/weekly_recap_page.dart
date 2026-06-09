import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/models/ai_models.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/widgets/weekly_recap_card.dart';

class WeeklyRecapPage extends StatelessWidget {
  final String userId;

  const WeeklyRecapPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          title: Text(
              '📊 AI Recap Tuần',
              style: TextStyle(fontWeight: FontWeight.w700, color: p.textPrimary, fontSize: 17)
          ),
          backgroundColor: p.appBarBackground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
              onPressed: () => Navigator.pop(context)
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2)
              );
            }

            if (!snap.hasData || !snap.data!.exists) {
              return _buildEmpty(p, theme);
            }

            final data = snap.data!.data() as Map<String, dynamic>?;
            final recapRaw = data?['weeklyRecap'] as Map<String, dynamic>?;
            final insightsRaw = data?['aiInsights'] as Map<String, dynamic>?;

            if (recapRaw == null) return _buildEmpty(p, theme);

            try {
              final recap = WeeklyRecapResult.fromMap(recapRaw);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _InfoBanner(primary: theme.primaryColor, palette: p),
                  const SizedBox(height: 16),
                  WeeklyRecapCard(recap: recap),
                  if (insightsRaw != null) ...[
                    const SizedBox(height: 20),
                    _InsightsSection(
                        insights: insightsRaw,
                        palette: p,
                        primary: theme.primaryColor
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              );
            } catch (_) {
              return _buildEmpty(p, theme);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: p.surfaceVariant, shape: BoxShape.circle),
                child: Icon(
                    Icons.analytics_outlined,
                    size: 56,
                    color: p.textSecondary.withValues(alpha: 0.45)
                ),
              ),
              const SizedBox(height: 22),
              Text(
                  'Chưa có dữ liệu recap',
                  style: TextStyle(fontSize: 17, color: p.textPrimary, fontWeight: FontWeight.w600)
              ),
              const SizedBox(height: 8),
              Text(
                  'AI sẽ tự động tổng kết vào\ncuối mỗi tuần (Chủ nhật 20:00)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: p.textSecondary, height: 1.6)
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2))
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, color: theme.primaryColor, size: 15),
                      const SizedBox(width: 8),
                      Text(
                          'Cần ít nhất 10 tin nhắn trong tuần',
                          style: TextStyle(fontSize: 13, color: theme.primaryColor, fontWeight: FontWeight.w500)
                      ),
                    ]
                ),
              ),
            ]
        ),
      ),
    );
  }
}

// ── Info Banner ──────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final Color primary;
  final ThemePalette palette;

  const _InfoBanner({required this.primary, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.15))
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)
                ),
                child: Icon(Icons.auto_awesome_rounded, color: primary, size: 15)
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    'AI phân tích tự động mỗi tuần. Dữ liệu được ẩn danh và xử lý an toàn.',
                    style: TextStyle(fontSize: 12.5, color: primary, height: 1.5)
                )
            ),
          ]
      ),
    );
  }
}

// ── Insights Section ─────────────────────────────────────────────────────────

class _InsightsSection extends StatelessWidget {
  final Map<String, dynamic> insights;
  final ThemePalette palette;
  final Color primary;

  const _InsightsSection({
    required this.insights,
    required this.palette,
    required this.primary
  });

  String _formatTs(dynamic raw) {
    try {
      DateTime dt;
      if (raw != null && raw.runtimeType.toString().contains('Timestamp')) {
        dt = (raw as dynamic).toDate() as DateTime;
      } else {
        dt = DateTime.tryParse(raw.toString()) ?? DateTime.now();
      }
      return DateFormat('HH:mm, dd/MM/yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = insights['insightSummary'] as String? ?? '';
    final topics = (insights['topTopics'] as List? ?? []).cast<String>();
    final traits = (insights['personalityTraits'] as List? ?? []).cast<String>();
    final style = insights['communicationStyle'] as String? ?? 'mixed';
    final emoji = insights['emojiUsageLevel'] as String? ?? 'medium';
    final avgLen = insights['avgMessageLength'] as String? ?? 'medium';
    final updatedAt = insights['updatedAt'];

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
              children: [
                const Text('🧠', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Text(
                    'Phân tích giao tiếp',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: palette.textPrimary)
                ),
              ]
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.divider, width: 0.6),
                boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 10)]
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Badge(_styleLabel(style), primary),
                        _Badge(_emojiLabel(emoji), const Color(0xFFF59E0B)),
                        _Badge(_lenLabel(avgLen), const Color(0xFF10B981)),
                      ]
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: palette.surfaceVariant,
                            borderRadius: BorderRadius.circular(12)
                        ),
                        child: Text(
                            summary,
                            style: TextStyle(fontSize: 13.5, color: palette.textSecondary, height: 1.6)
                        )
                    ),
                  ],
                  if (topics.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                        '📌 Chủ đề thường nhắc',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textPrimary)
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topics.map((t) => _Badge(t, primary)).toList()
                    ),
                  ],
                  if (traits.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                        '✨ Đặc điểm nổi bật',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textPrimary)
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: traits.map((t) => _Badge(t, const Color(0xFF8B5CF6))).toList()
                    ),
                  ],
                  if (updatedAt != null) ...[
                    const SizedBox(height: 14),
                    Row(
                        children: [
                          Icon(Icons.update_rounded, size: 12, color: palette.textSecondary),
                          const SizedBox(width: 5),
                          Text(
                              'Cập nhật: ${_formatTs(updatedAt)}',
                              style: TextStyle(fontSize: 11, color: palette.textSecondary)
                          ),
                        ]
                    ),
                  ],
                ]
            ),
          ),
        ]
    );
  }

  String _styleLabel(String s) => switch (s) {
    'formal' => '📋 Trang trọng',
    'casual' => '😊 Thoải mái',
    _ => '🔄 Linh hoạt'
  };

  String _emojiLabel(String l) => switch (l) {
    'high' => '😄 Nhiều emoji',
    'low' => '📝 Ít emoji',
    _ => '👍 Vừa phải'
  };

  String _lenLabel(String l) => switch (l) {
    'short' => '⚡ Tin ngắn',
    'long' => '📖 Tin dài',
    _ => '📋 Độ dài vừa'
  };
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25))
      ),
      child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)
      ),
    );
  }
}