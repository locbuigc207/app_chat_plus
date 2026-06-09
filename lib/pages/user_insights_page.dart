import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class UserInsightsPage extends StatefulWidget {
  final String conversationId;
  final String peerName;

  const UserInsightsPage(
      {super.key, required this.conversationId, required this.peerName});

  @override
  State<UserInsightsPage> createState() => _UserInsightsPageState();
}

class _UserInsightsPageState extends State<UserInsightsPage>
    with SingleTickerProviderStateMixin {
  UserInsightsResult? _result;
  bool _loading = true;
  String? _error;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _animCtrl.reset();

    try {
      final result = await AIBackendService()
          .getUserInsights(conversationId: widget.conversationId);
      if (!mounted) return;

      setState(() {
        _result = result;
        _loading = false;
      });
      _animCtrl.forward();
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

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          title: Text('AI Phân Tích Giao Tiếp',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                  fontSize: 16)),
          backgroundColor: p.appBarBackground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: theme.primaryColor, size: 20),
              onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
                icon: Icon(Icons.refresh_rounded, color: theme.primaryColor),
                onPressed: _load,
                tooltip: 'Làm mới')
          ],
        ),
        body: _loading
            ? _buildLoading(p, theme)
            : _error != null
                ? _buildError(p, theme)
                : _result == null
                    ? _buildNoData(p, theme)
                    : FadeTransition(
                        opacity: _fadeAnim,
                        child: _buildContent(_result!, p, theme)),
      ),
    );
  }

  Widget _buildLoading(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle),
            child: CircularProgressIndicator(
                color: theme.primaryColor, strokeWidth: 2.5)),
        const SizedBox(height: 20),
        Text('AI đang phân tích...',
            style: TextStyle(
                fontSize: 15,
                color: p.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('Đang xử lý lịch sử trò chuyện của bạn',
            style: TextStyle(fontSize: 13, color: p.textSecondary)),
      ]),
    );
  }

  Widget _buildError(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: p.dangerColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: Icon(Icons.error_outline_rounded,
                  size: 48, color: p.dangerColor)),
          const SizedBox(height: 18),
          Text('Không thể tải dữ liệu',
              style: TextStyle(
                  fontSize: 17,
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Vui lòng kiểm tra kết nối mạng và thử lại',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: p.textSecondary, height: 1.5)),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
              style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)))),
        ]),
      ),
    );
  }

  Widget _buildNoData(ThemePalette p, ThemeProvider theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: p.surfaceVariant, shape: BoxShape.circle),
              child: Icon(Icons.psychology_outlined,
                  size: 56, color: p.textSecondary.withValues(alpha: 0.5))),
          const SizedBox(height: 20),
          Text('Chưa đủ dữ liệu để phân tích',
              style: TextStyle(
                  fontSize: 16,
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
              'Cần ít nhất 5 tin nhắn trong 7 ngày gần đây\nđể AI có thể phân tích phong cách của bạn',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: p.textSecondary, height: 1.6)),
        ]),
      ),
    );
  }

  Widget _buildContent(
      UserInsightsResult r, ThemePalette p, ThemeProvider theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroCard(
            insightSummary: r.insightSummary,
            palette: p,
            primary: theme.primaryColor),
        const SizedBox(height: 14),
        _InsightCard(
            icon: '💬',
            title: 'Phong cách giao tiếp',
            content: switch (r.communicationStyle) {
              'formal' =>
                'Trang trọng & lịch sự — bạn thường dùng ngôn ngữ chuẩn mực và súc tích',
              'casual' =>
                'Thoải mái & thân thiện — bạn nói chuyện tự nhiên, vui vẻ và gần gũi',
              _ =>
                'Linh hoạt theo tình huống — bạn dễ thay đổi phong cách phù hợp ngữ cảnh',
            },
            color: const Color(0xFF8B5CF6),
            palette: p),
        if (r.topTopics.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TopicsCard(
              topics: r.topTopics, palette: p, primary: theme.primaryColor),
        ],
        if (r.personalityTraits.isNotEmpty) ...[
          const SizedBox(height: 14),
          _InsightCard(
              icon: '✨',
              title: 'Đặc điểm nổi bật',
              content: r.personalityTraits.join(' • '),
              color: const Color(0xFFF59E0B),
              palette: p),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _StatCard(
                  emoji: '😊',
                  label: 'Dùng emoji',
                  value: switch (r.emojiUsageLevel) {
                    'high' => '🔥 Nhiều',
                    'low' => '💤 Ít',
                    _ => '👍 Vừa'
                  },
                  valueColor: switch (r.emojiUsageLevel) {
                    'high' => const Color(0xFFFF6B6B),
                    'low' => const Color(0xFF94A3B8),
                    _ => const Color(0xFF22C55E)
                  },
                  palette: p)),
          const SizedBox(width: 12),
          Expanded(
              child: _StatCard(
                  emoji: '📝',
                  label: 'Độ dài tin',
                  value: switch (r.avgMessageLength) {
                    'short' => '⚡ Ngắn',
                    'long' => '📖 Dài',
                    _ => '📋 Vừa'
                  },
                  valueColor: switch (r.avgMessageLength) {
                    'short' => const Color(0xFFF59E0B),
                    'long' => const Color(0xFF6366F1),
                    _ => const Color(0xFF22C55E)
                  },
                  palette: p)),
        ]),
        if (r.activityPattern.isNotEmpty && r.activityPattern != 'unknown') ...[
          const SizedBox(height: 14),
          _InsightCard(
              icon: '⏰',
              title: 'Thói quen nhắn tin',
              content: r.activityPattern,
              color: const Color(0xFF0EA5E9),
              palette: p),
        ],
        const SizedBox(height: 14),
        _WeeklyRecapSection(
            userId: widget.conversationId,
            palette: p,
            primary: theme.primaryColor),
        const SizedBox(height: 24),
      ],
    );
  }

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
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String insightSummary;
  final ThemePalette palette;
  final Color primary;

  const _HeroCard(
      {required this.insightSummary,
      required this.palette,
      required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [primary, primary.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧠', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Text('Tổng quan AI',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const Spacer(),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999)),
              child: const Text('Gemini AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 12),
        Text(
            insightSummary.isNotEmpty
                ? insightSummary
                : 'Không có đủ dữ liệu để tổng quan.',
            style: const TextStyle(
                fontSize: 14, color: Colors.white, height: 1.6)),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String icon, title, content;
  final Color color;
  final ThemePalette palette;

  const _InsightCard(
      {required this.icon,
      required this.title,
      required this.content,
      required this.color,
      required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8)],
          border: Border(left: BorderSide(color: color, width: 3.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: palette.textPrimary))
        ]),
        const SizedBox(height: 8),
        Text(content,
            style: TextStyle(
                fontSize: 13.5, color: palette.textSecondary, height: 1.55)),
      ]),
    );
  }
}

class _TopicsCard extends StatelessWidget {
  final List<String> topics;
  final ThemePalette palette;
  final Color primary;

  const _TopicsCard(
      {required this.topics, required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📌', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text('Chủ đề thường nhắc tới',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                  fontSize: 14))
        ]),
        const SizedBox(height: 12),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: topics
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: primary.withValues(alpha: 0.2))),
                      child: Text(t,
                          style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ))
                .toList()),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji, label, value;
  final Color valueColor;
  final ThemePalette palette;

  const _StatCard(
      {required this.emoji,
      required this.label,
      required this.value,
      required this.valueColor,
      required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8)]),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13.5, color: valueColor),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      ]),
    );
  }
}

class _WeeklyRecapSection extends StatelessWidget {
  final String userId;
  final ThemePalette palette;
  final Color primary;

  const _WeeklyRecapSection(
      {required this.userId, required this.palette, required this.primary});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (ctx, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();

        final data = snap.data!.data() as Map<String, dynamic>?;
        final raw = data?['weeklyRecap'] as Map<String, dynamic>?;

        if (raw == null || raw.isEmpty) return const SizedBox.shrink();

        try {
          final recap = WeeklyRecapResult.fromMap(raw);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('📊', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Text('Tóm tắt tuần gần nhất',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary))
                ]),
                const SizedBox(height: 10),
                WeeklyRecapCard(recap: recap),
              ]);
        } catch (_) {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
