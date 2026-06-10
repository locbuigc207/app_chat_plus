import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Đảm bảo import đúng với cấu trúc dự án của bạn.
// Nếu dùng relative path bị lỗi, hãy thay thế bằng package:flutter_chat_demo/...
import '../models/insights_models.dart';
import '../providers/insights_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/insight_chart_widgets.dart';
import '../widgets/weekly_recap_card.dart';

class UserInsightsPage extends StatefulWidget {
  final String conversationId;
  final String userId;
  final String peerName;

  const UserInsightsPage({
    super.key,
    required this.conversationId,
    required this.userId,
    required this.peerName,
  });

  @override
  State<UserInsightsPage> createState() => _UserInsightsPageState();
}

class _UserInsightsPageState extends State<UserInsightsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InsightsProvider>().loadDashboard(
            conversationId: widget.conversationId,
            userId: widget.userId,
          );
      _fadeCtrl.forward();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final provider = context.watch<InsightsProvider>();

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: RefreshIndicator(
            onRefresh: () => provider.refresh(),
            color: theme.primaryColor,
            backgroundColor: p.surface,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                // ─── SliverAppBar ───────────────────────────────────────────
                _buildAppBar(theme, p, provider),

                // ─── Period Selector (pinned) ───────────────────────────────
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PeriodSelectorDelegate(
                    selectedPeriod: provider.selectedPeriod,
                    primaryColor: theme.primaryColor,
                    palette: p,
                    onChanged: (period) {
                      HapticFeedback.selectionClick();
                      provider.selectPeriod(period);
                    },
                  ),
                ),

                // ─── Body ───────────────────────────────────────────────────
                if (provider.loadState == InsightsLoadState.error)
                  SliverFillRemaining(
                      child: _ErrorView(
                    message: provider.errorMessage ?? 'Có lỗi xảy ra.',
                    palette: p,
                    onRetry: () => provider.loadDashboard(
                        conversationId: widget.conversationId,
                        userId: widget.userId),
                  ))
                else if (provider.loadState == InsightsLoadState.loading)
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _SkeletonLoader(palette: p),
                      ]),
                    ),
                  )
                else if (!provider.hasData ||
                    provider.currentSnapshot == null ||
                    provider.currentSnapshot!.totalMessages == 0)
                  SliverFillRemaining(
                      child: _EmptyState(
                    palette: p,
                    peerName: widget.peerName,
                  ))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(
                        _buildCards(
                            context, theme, p, provider.currentSnapshot!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar(
      ThemeProvider theme, ThemePalette p, InsightsProvider provider) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: p.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (provider.loadState == InsightsLoadState.refreshing)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.primaryColor),
              ),
            ),
          )
        else
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: p.textSecondary, size: 22),
            onPressed: () => provider.refresh(),
            tooltip: 'Làm mới dữ liệu',
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.primaryColor.withValues(alpha: 0.15),
                theme.primaryColor.withValues(alpha: 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Insights',
                      style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    Text(
                      'Phân tích cuộc trò chuyện với ${widget.peerName}',
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.primaryColor,
                      theme.primaryColor.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Icon(Icons.insights_rounded,
                    color: Colors.white, size: 28),
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
      ),
    );
  }

  // ─── Cards builder ────────────────────────────────────────────────────────

  List<Widget> _buildCards(BuildContext ctx, ThemeProvider theme,
      ThemePalette p, InsightsSnapshot snap) {
    return [
      // Stale warning
      if (snap.isStale) ...[
        _StaleWarning(palette: p, primaryColor: theme.primaryColor),
        const SizedBox(height: 12),
      ],

      // Weekly Recap card
      InsightsRecapCard(
        snapshot: snap,
        palette: p,
        primaryColor: theme.primaryColor,
        peerName: widget.peerName,
      ),
      const SizedBox(height: 14),

      // Stats Row
      _StatsRow(snapshot: snap, palette: p, primaryColor: theme.primaryColor),
      const SizedBox(height: 14),

      // Sentiment breakdown
      _InsightCard(
        icon: Icons.sentiment_satisfied_alt_rounded,
        title: 'Phân tích tâm trạng',
        primary: theme.primaryColor,
        palette: p,
        child: SentimentBar(breakdown: snap.sentimentBreakdown, palette: p),
      ),
      const SizedBox(height: 14),

      // Mood Trend
      if (snap.moodTrend.isNotEmpty) ...[
        _InsightCard(
          icon: Icons.show_chart_rounded,
          title: 'Xu hướng tâm trạng',
          subtitle: '${snap.moodTrend.length} ngày',
          primary: theme.primaryColor,
          palette: p,
          child: MoodTrendChart(
            points: snap.moodTrend,
            palette: p,
            lineColor: theme.primaryColor,
          ),
        ),
        const SizedBox(height: 14),
      ],

      // Activity Heatmap
      if (snap.activityHeatmap.isNotEmpty) ...[
        _InsightCard(
          icon: Icons.grid_view_rounded,
          title: 'Giờ nhắn tin',
          subtitle: 'Heatmap 7 ngày × 24 giờ',
          primary: theme.primaryColor,
          palette: p,
          child: ActivityHeatmapChart(
            slots: snap.activityHeatmap,
            palette: p,
            baseColor: theme.primaryColor,
          ),
        ),
        const SizedBox(height: 14),
      ],

      // Topics
      if (snap.topTopics.isNotEmpty) ...[
        _InsightCard(
          icon: Icons.topic_outlined,
          title: 'Chủ đề thường nhắc',
          subtitle: 'Top ${snap.topTopics.length} từ khoá',
          primary: theme.primaryColor,
          palette: p,
          child: TopicsBarChart(topics: snap.topTopics, palette: p),
        ),
        const SizedBox(height: 14),
      ],

      // Personality card
      _PersonalityCard(
        snapshot: snap,
        palette: p,
        primaryColor: theme.primaryColor,
      ),
      const SizedBox(height: 8),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Period Selector (SliverPersistentHeaderDelegate)
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodSelectorDelegate extends SliverPersistentHeaderDelegate {
  final InsightsPeriod selectedPeriod;
  final Color primaryColor;
  final ThemePalette palette;
  final ValueChanged<InsightsPeriod> onChanged;

  _PeriodSelectorDelegate({
    required this.selectedPeriod,
    required this.primaryColor,
    required this.palette,
    required this.onChanged,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: palette.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: InsightsPeriod.values.map((period) {
            final isSel = selectedPeriod == period;
            return GestureDetector(
              onTap: () => onChanged(period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel ? primaryColor : palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: isSel ? primaryColor : palette.divider,
                      width: isSel ? 0 : 0.8),
                  boxShadow: isSel
                      ? [
                          BoxShadow(
                              color: primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Text(
                  period.label,
                  style: TextStyle(
                      color: isSel ? Colors.white : palette.textSecondary,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PeriodSelectorDelegate old) =>
      old.selectedPeriod != selectedPeriod;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Row — 3 metric chips
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final ThemePalette palette;
  final Color primaryColor;

  const _StatsRow(
      {required this.snapshot,
      required this.palette,
      required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    return Row(
      children: [
        _MetricChip(
          icon: Icons.message_outlined,
          value: s.totalMessages.toString(),
          label: 'Tin nhắn',
          color: primaryColor,
          palette: palette,
        ),
        const SizedBox(width: 10),
        _MetricChip(
          icon: Icons.calendar_today_rounded,
          value: s.activeDays.toString(),
          label: 'Ngày hoạt động',
          color: const Color(0xFF22C55E),
          palette: palette,
        ),
        const SizedBox(width: 10),
        _MetricChip(
          icon: Icons.bar_chart_rounded,
          value: s.avgMessagesPerDay.toStringAsFixed(1),
          label: 'Tin/ngày',
          color: const Color(0xFFF59E0B),
          palette: palette,
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final ThemePalette palette;

  const _MetricChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: -0.5)),
              Text(label,
                  style: TextStyle(
                      color: palette.textHint, fontSize: 11, height: 1.2),
                  maxLines: 2),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic InsightCard container
// ─────────────────────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final ThemePalette palette;
  final Color primary;

  const _InsightCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    required this.palette,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.divider, width: 0.7),
          boxShadow: [
            BoxShadow(
                color: palette.shadow,
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, color: primary, size: 15),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        if (subtitle != null)
                          Text(subtitle!,
                              style: TextStyle(
                                  color: palette.textHint, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.divider),
            Padding(padding: const EdgeInsets.all(16), child: child),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PersonalityCard
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalityCard extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final ThemePalette palette;
  final Color primaryColor;

  const _PersonalityCard(
      {required this.snapshot,
      required this.palette,
      required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final traitMeta = {
      'expressive': ('💬', 'Cởi mở', 'Chia sẻ nhiều, diễn đạt rõ ràng'),
      'communicative': (
        '🗣️',
        'Hay trò chuyện',
        'Thích giao tiếp, nhiều chủ đề'
      ),
      'direct': ('⚡', 'Thẳng thắn', 'Ngắn gọn, đi thẳng vào vấn đề'),
      'optimistic': ('😊', 'Lạc quan', 'Tâm trạng tích cực, vui vẻ'),
      'reflective': ('🤔', 'Suy tư', 'Hay suy nghĩ, cân nhắc kỹ'),
      'balanced': ('⚖️', 'Cân bằng', 'Phong cách linh hoạt, dễ thích nghi'),
    };

    return _InsightCard(
      icon: Icons.person_outline_rounded,
      title: 'Tính cách giao tiếp',
      palette: palette,
      primary: primaryColor,
      child: s.personalityTraits.isEmpty
          ? Center(
              child: Text('Chưa đủ dữ liệu',
                  style: TextStyle(color: palette.textHint, fontSize: 13)))
          : Column(
              children: s.personalityTraits.map((trait) {
                final meta =
                    traitMeta[trait] ?? ('✨', trait, 'Phong cách đặc trưng');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                            child: Text(meta.$1,
                                style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meta.$2,
                                style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            Text(meta.$3,
                                style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 12.5)),
                          ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton Loader
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonLoader extends StatefulWidget {
  final ThemePalette palette;
  const _SkeletonLoader({required this.palette});

  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = widget.palette.divider.withValues(alpha: _anim.value);
        return Column(
          children: [
            _SkeletonBox(color: color, height: 110, radius: 20),
            const SizedBox(height: 14),
            Row(
              children: [
                _SkeletonBox(color: color, height: 80, radius: 16, flex: 1),
                const SizedBox(width: 10),
                _SkeletonBox(color: color, height: 80, radius: 16, flex: 1),
                const SizedBox(width: 10),
                _SkeletonBox(color: color, height: 80, radius: 16, flex: 1),
              ],
            ),
            const SizedBox(height: 14),
            _SkeletonBox(color: color, height: 130, radius: 20),
            const SizedBox(height: 14),
            _SkeletonBox(color: color, height: 200, radius: 20),
          ],
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final Color color;
  final double height;
  final double radius;
  final int flex;

  const _SkeletonBox({
    required this.color,
    required this.height,
    this.radius = 12,
    this.flex = 0,
  });

  Widget _box() => Container(
        height: height,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(radius)),
      );

  @override
  Widget build(BuildContext context) =>
      flex > 0 ? Expanded(flex: flex, child: _box()) : _box();
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ThemePalette palette;
  final String peerName;

  const _EmptyState({required this.palette, required this.peerName});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 64, color: palette.textHint),
              const SizedBox(height: 20),
              Text(
                'Chưa đủ dữ liệu',
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Hãy nhắn tin thêm với $peerName để AI phân tích được phong cách giao tiếp của bạn.',
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Error View
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final ThemePalette palette;
  final VoidCallback onRetry;

  const _ErrorView(
      {required this.message, required this.palette, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 56, color: const Color(0xFFEF4444)),
              const SizedBox(height: 16),
              Text(
                'Không thể tải dữ liệu',
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(message,
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Thử lại'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stale Warning Banner
// ─────────────────────────────────────────────────────────────────────────────

class _StaleWarning extends StatelessWidget {
  final ThemePalette palette;
  final Color primaryColor;

  const _StaleWarning({required this.palette, required this.primaryColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3))),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Dữ liệu có thể chưa được cập nhật mới nhất. Vuốt xuống để làm mới.',
                style: TextStyle(
                    color: palette.textSecondary, fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
