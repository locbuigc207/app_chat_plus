// lib/pages/weekly_recap_page.dart

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/providers.dart';
import '../services/services.dart';
import '../widgets/widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PAGE
// ══════════════════════════════════════════════════════════════════════════════

class WeeklyRecapPage extends StatefulWidget {
  final String userId;
  final String? conversationId;
  final String? peerName;
  final RecapConversationType conversationType;

  const WeeklyRecapPage({
    super.key,
    required this.userId,
    this.conversationId,
    this.peerName,
    this.conversationType = RecapConversationType.group,
  });

  @override
  State<WeeklyRecapPage> createState() => _WeeklyRecapPageState();
}

class _WeeklyRecapPageState extends State<WeeklyRecapPage>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final _service = WeeklyRecapService();

  // ── State ─────────────────────────────────────────────────────────────────
  RecapStyle _selectedStyle = RecapStyle.humorous;
  RecapLookback _lookback = RecapLookback.oneWeek;
  _PageState _pageState = _PageState.idle;
  WeeklyRecapData? _recapData;
  String _errorMsg = '';

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _heroAnim;
  late final AnimationController _contentAnim;
  late final AnimationController _genAnim; // generation pulse
  late final AnimationController _particleAnim;

  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;
  late final Animation<double> _pulseSc;

  // ── Scroll ────────────────────────────────────────────────────────────────
  late final ScrollController _scroll;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();

    // Hero animations
    _heroAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _heroFade = CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _heroAnim, curve: Curves.easeOutCubic));

    // Content animations
    _contentAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _contentFade = CurvedAnimation(parent: _contentAnim, curve: Curves.easeOut);
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
            CurvedAnimation(parent: _contentAnim, curve: Curves.easeOutCubic));

    // Generating pulse
    _genAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseSc = Tween<double>(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _genAnim, curve: Curves.easeInOut));

    // Particle animation
    _particleAnim =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();

    _scroll = ScrollController()
      ..addListener(() {
        if (mounted) setState(() => _scrollOffset = _scroll.offset);
      });

    // Start hero animation
    _heroAnim.forward();

    // Auto-generate if conversationId is given and style cached
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.conversationId != null) {
        final cached = _service.getCached(
          widget.conversationId!,
          _selectedStyle,
          _lookback.days,
        );
        if (cached != null) {
          setState(() {
            _recapData = cached;
            _pageState = _PageState.success;
          });
          _contentAnim.forward();
        }
      } else {
        // If it's global fetch, trigger content animation
        _contentAnim.forward();
      }
    });
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    _contentAnim.dispose();
    _genAnim.dispose();
    _particleAnim.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Generate (for Conversation Mode) ──────────────────────────────────────
  Future<void> _generate({bool forceRefresh = false}) async {
    if (_pageState == _PageState.loading) return;
    if (widget.conversationId == null) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _pageState = _PageState.loading;
      _errorMsg = '';
    });
    _contentAnim.reset();

    final result = await _service.generateRecap(
      conversationId: widget.conversationId!,
      style: _selectedStyle,
      conversationType: widget.conversationType,
      lookbackDays: _lookback.days,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;

    if (result.success) {
      HapticFeedback.heavyImpact();
      setState(() {
        _recapData = result;
        _pageState = _PageState.success;
      });
      _contentAnim.forward();
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _pageState = _PageState.error;
        _errorMsg = result.failReason ?? 'Không thể tạo tóm tắt.';
      });
    }
  }

  void _onStyleChanged(RecapStyle style) {
    if (_selectedStyle == style) return;
    HapticFeedback.selectionClick();

    final isCached = widget.conversationId != null &&
        _service.isCached(widget.conversationId!, style, _lookback.days);

    setState(() {
      _selectedStyle = style;
      if (isCached) {
        _recapData =
            _service.getCached(widget.conversationId!, style, _lookback.days);
        _pageState = _PageState.success;
        _contentAnim
          ..reset()
          ..forward();
      } else if (_pageState == _PageState.success) {
        _pageState = _PageState.idle;
        _recapData = null;
      }
    });
  }

  void _onLookbackChanged(RecapLookback lb) {
    if (_lookback == lb) return;
    HapticFeedback.selectionClick();
    setState(() {
      _lookback = lb;
      _pageState = _PageState.idle;
      _recapData = null;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final primary = theme.primaryColor;
    final isGlobal = widget.conversationId == null;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // ── Collapsible Hero AppBar ──────────────────────────────────────
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              elevation: 0,
              backgroundColor: p.appBarBackground,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: primary),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (!isGlobal && _pageState == _PageState.success)
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 22, color: primary),
                    tooltip: 'Tạo lại',
                    onPressed: () => _generate(forceRefresh: true),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: SlideTransition(
                  position: _heroSlide,
                  child: FadeTransition(
                    opacity: _heroFade,
                    child: _HeroHeader(
                      peerName: widget.peerName ??
                          (isGlobal ? 'Tổng kết cá nhân' : 'Chat'),
                      conversationType: isGlobal
                          ? RecapConversationType.personal
                          : widget.conversationType,
                      style: _selectedStyle,
                      particleAnim: _particleAnim,
                    ),
                  ),
                ),
                title: Text(
                  isGlobal ? 'AI Recap Tuần' : 'Tổng Kết Tuần',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                titlePadding:
                    const EdgeInsetsDirectional.only(start: 56, bottom: 16),
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: isGlobal
                  // GLOBAL MODE: Fetch from Firestore
                  ? _buildGlobalRecap(p, primary, theme)
                  // CONVERSATION MODE: AI Generation Builder
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Conversation info card
                        _buildConversationCard(p, primary),

                        // Style selector
                        _buildStyleSelector(p),

                        // Period selector
                        _buildPeriodSelector(p, primary),

                        // Content area
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                      begin: const Offset(0, 0.05),
                                      end: Offset.zero)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey(
                                '${_pageState.name}_${_selectedStyle.key}_${_lookback.days}'),
                            child: _buildContent(p, primary, theme),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Global Profile Recap (From Firestore) ─────────────────────────────────
  Widget _buildGlobalRecap(ThemePalette p, Color primary, ThemeProvider theme) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
                child:
                    CircularProgressIndicator(color: primary, strokeWidth: 2)),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          return _buildGlobalEmptyState(p, theme);
        }

        final data = snap.data!.data() as Map<String, dynamic>?;
        final recapRaw = data?['weeklyRecap'] as Map<String, dynamic>?;
        final insightsRaw = data?['aiInsights'] as Map<String, dynamic>?;

        if (recapRaw == null) return _buildGlobalEmptyState(p, theme);

        try {
          final recap = WeeklyRecapData.fromMap(recapRaw, _selectedStyle);
          return SlideTransition(
            position: _contentSlide,
            child: FadeTransition(
              opacity: _contentFade,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoBanner(primary: primary, palette: p),
                    const SizedBox(height: 16),
                    WeeklyRecapCard(
                      recap: recap,
                      conversationName: 'Tài khoản của bạn',
                      showShareButton: false,
                      initiallyExpanded: true,
                    ),
                    if (insightsRaw != null) ...[
                      const SizedBox(height: 20),
                      _InsightsSection(
                          insights: insightsRaw, palette: p, primary: primary),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        } catch (_) {
          return _buildGlobalEmptyState(p, theme);
        }
      },
    );
  }

  Widget _buildGlobalEmptyState(ThemePalette p, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration:
              BoxDecoration(color: p.surfaceVariant, shape: BoxShape.circle),
          child: Icon(Icons.analytics_outlined,
              size: 56, color: p.textSecondary.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 22),
        Text('Chưa có dữ liệu recap',
            style: TextStyle(
                fontSize: 17,
                color: p.textPrimary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('AI sẽ tự động tổng kết vào\ncuối mỗi tuần (Chủ nhật 20:00)',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13.5, color: p.textSecondary, height: 1.6)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: theme.primaryColor.withValues(alpha: 0.2))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline_rounded,
                color: theme.primaryColor, size: 15),
            const SizedBox(width: 8),
            Text('Cần ít nhất 10 tin nhắn trong tuần',
                style: TextStyle(
                    fontSize: 13,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }

  // ── Conversation Info Card ────────────────────────────────────────────────
  Widget _buildConversationCard(ThemePalette p, Color primary) {
    final icon = widget.conversationType == RecapConversationType.group
        ? Icons.group_rounded
        : Icons.person_rounded;
    final typeLabel = widget.conversationType == RecapConversationType.group
        ? 'Nhóm'
        : 'Cá nhân';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.divider),
          boxShadow: [
            BoxShadow(
                color: p.shadow, blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.peerName ?? 'Hội thoại',
                    style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text(typeLabel,
                    style: TextStyle(color: p.textHint, fontSize: 12)),
              ])),
          if (_pageState == _PageState.success)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded, size: 12, color: Colors.green),
                SizedBox(width: 4),
                Text('Đã tạo',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      ),
    );
  }

  // ── Style Selector ────────────────────────────────────────────────────────
  Widget _buildStyleSelector(ThemePalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(children: [
          Icon(Icons.palette_rounded, size: 16, color: p.textSecondary),
          const SizedBox(width: 6),
          Text('Phong cách',
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(RecapStyle.values.length.toString() + ' kiểu',
              style: TextStyle(color: p.textHint, fontSize: 12)),
        ]),
      ),
      SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: RecapStyle.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final style = RecapStyle.values[i];
            final isCached = widget.conversationId != null &&
                _service.isCached(
                    widget.conversationId!, style, _lookback.days);
            return RecapStyleChip(
              style: style,
              selected: _selectedStyle == style,
              isCached: isCached,
              onTap: () => _onStyleChanged(style),
            );
          },
        ),
      ),
      // Style description tooltip
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            key: ValueKey(_selectedStyle.key),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: p.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_selectedStyle.label.split(' ').first,
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(_selectedStyle.description,
                  style: TextStyle(color: p.textHint, fontSize: 12.5)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Period Selector ───────────────────────────────────────────────────────
  Widget _buildPeriodSelector(ThemePalette p, Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.calendar_month_rounded, size: 16, color: p.textSecondary),
          const SizedBox(width: 6),
          Text('Khoảng thời gian',
              style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(
            children: RecapLookback.values.map((lb) {
          final selected = _lookback == lb;
          return Expanded(
              child: Padding(
            padding:
                EdgeInsets.only(right: lb != RecapLookback.values.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => _onLookbackChanged(lb),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: selected ? primary : p.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.transparent : p.divider,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ]
                      : [],
                ),
                child: Text(
                  lb.label,
                  style: TextStyle(
                    color: selected ? Colors.white : p.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ));
        }).toList()),
      ]),
    );
  }

  // ── Content Area ──────────────────────────────────────────────────────────
  Widget _buildContent(ThemePalette p, Color primary, ThemeProvider theme) {
    switch (_pageState) {
      case _PageState.idle:
        return _buildIdleState(p, primary);

      case _PageState.loading:
        return _buildLoadingState(p, primary, theme);

      case _PageState.success:
        return _buildSuccessState(p, primary);

      case _PageState.error:
        return _buildErrorState(p);
    }
  }

  Widget _buildIdleState(ThemePalette p, Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: RecapEmptyState(
        conversationType: widget.conversationType.name,
        onGenerate: _generate,
      ),
    );
  }

  Widget _buildLoadingState(
      ThemePalette p, Color primary, ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(children: [
        ScaleTransition(
          scale: _pulseSc,
          child: const RecapLoadingPlaceholder(),
        ),
        const SizedBox(height: 24),
        _GeneratingProgressWidget(
          style: _selectedStyle,
          lookback: _lookback,
          animController: _genAnim,
        ),
      ]),
    );
  }

  Widget _buildSuccessState(ThemePalette p, Color primary) {
    if (_recapData == null) return const SizedBox.shrink();

    return SlideTransition(
      position: _contentSlide,
      child: FadeTransition(
        opacity: _contentFade,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(children: [
            WeeklyRecapCard(
              recap: _recapData!,
              conversationName: widget.peerName ?? 'Chat',
              showShareButton: true,
              onRefresh: () => _generate(forceRefresh: true),
              initiallyExpanded: true,
            ),
            const SizedBox(height: 16),

            // Regenerate row
            Row(children: [
              Expanded(
                  child: _OutlineAction(
                icon: Icons.style_rounded,
                label: 'Đổi phong cách',
                onTap: () => _scroll.animateTo(0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _OutlineAction(
                icon: Icons.share_rounded,
                label: 'Chia sẻ Story',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => RecapShareSheet(
                    recap: _recapData!,
                    conversationName: widget.peerName ?? 'Chat',
                  ),
                ),
              )),
            ]),

            const SizedBox(height: 10),
            _OutlineAction(
              icon: Icons.refresh_rounded,
              label: 'Tạo lại bản mới',
              onTap: () => _generate(forceRefresh: true),
              fullWidth: true,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemePalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: RecapErrorState(
        message: _errorMsg,
        onRetry: _generate,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXTRA COMPONENTS (GLOBAL INSIGHTS, BANNERS, HERO, ETC)
// ══════════════════════════════════════════════════════════════════════════════

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
          border: Border.all(color: primary.withValues(alpha: 0.15))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.auto_awesome_rounded, color: primary, size: 15)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                'AI phân tích tự động mỗi tuần. Dữ liệu được ẩn danh và xử lý an toàn.',
                style: TextStyle(fontSize: 12.5, color: primary, height: 1.5))),
      ]),
    );
  }
}

// ── Insights Section ─────────────────────────────────────────────────────────
class _InsightsSection extends StatelessWidget {
  final Map<String, dynamic> insights;
  final ThemePalette palette;
  final Color primary;

  const _InsightsSection(
      {required this.insights, required this.palette, required this.primary});

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
    final traits =
        (insights['personalityTraits'] as List? ?? []).cast<String>();
    final style = insights['communicationStyle'] as String? ?? 'mixed';
    final emoji = insights['emojiUsageLevel'] as String? ?? 'medium';
    final avgLen = insights['avgMessageLength'] as String? ?? 'medium';
    final updatedAt = insights['updatedAt'];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('🧠', style: TextStyle(fontSize: 15)),
        const SizedBox(width: 8),
        Text('Phân tích giao tiếp',
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary)),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.divider, width: 0.6),
            boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 10)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Badge(_styleLabel(style), primary),
            _Badge(_emojiLabel(emoji), const Color(0xFFF59E0B)),
            _Badge(_lenLabel(avgLen), const Color(0xFF10B981)),
          ]),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(summary,
                    style: TextStyle(
                        fontSize: 13.5,
                        color: palette.textSecondary,
                        height: 1.6))),
          ],
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('📌 Chủ đề thường nhắc',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topics.map((t) => _Badge(t, primary)).toList()),
          ],
          if (traits.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('✨ Đặc điểm nổi bật',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: traits
                    .map((t) => _Badge(t, const Color(0xFF8B5CF6)))
                    .toList()),
          ],
          if (updatedAt != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.update_rounded,
                  size: 12, color: palette.textSecondary),
              const SizedBox(width: 5),
              Text('Cập nhật: ${_formatTs(updatedAt)}',
                  style: TextStyle(fontSize: 11, color: palette.textSecondary)),
            ]),
          ],
        ]),
      ),
    ]);
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
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Text(label,
          style: TextStyle(
              fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Hero Header ──────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String peerName;
  final RecapConversationType conversationType;
  final RecapStyle style;
  final AnimationController particleAnim;

  const _HeroHeader({
    required this.peerName,
    required this.conversationType,
    required this.style,
    required this.particleAnim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final primary = theme.primaryColor;

    const particles = ['✨', '📊', '🎭', '💬', '🌟', '🎬', '💕', '📝', '🔥'];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.9),
            primary.withValues(alpha: 0.5),
            Colors.transparent
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // Floating particles
          ...List.generate(6, (i) {
            final rand = math.Random(i * 7 + 3);
            final xFrac = rand.nextDouble();
            final delay = rand.nextDouble();
            final emoji = particles[i % particles.length];
            return AnimatedBuilder(
              animation: particleAnim,
              builder: (_, __) {
                final t = ((particleAnim.value + delay) % 1.0);
                final y = 1.0 - t;
                final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0);
                return Positioned(
                  left: MediaQuery.sizeOf(context).width * xFrac,
                  top: 200 * y * 0.9,
                  child: Opacity(
                    opacity: opacity * 0.6,
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                );
              },
            );
          }),

          // Main content
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 72, 20, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      conversationType == RecapConversationType.group
                          ? Icons.group_rounded
                          : Icons.person_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      conversationType == RecapConversationType.group
                          ? 'Nhóm'
                          : 'Cá nhân',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    style.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Generating Progress Widget ───────────────────────────────────────────────
class _GeneratingProgressWidget extends StatefulWidget {
  final RecapStyle style;
  final RecapLookback lookback;
  final AnimationController animController;

  const _GeneratingProgressWidget({
    required this.style,
    required this.lookback,
    required this.animController,
  });

  @override
  State<_GeneratingProgressWidget> createState() =>
      _GeneratingProgressWidgetState();
}

class _GeneratingProgressWidgetState extends State<_GeneratingProgressWidget> {
  int _stepIndex = 0;
  late final List<String> _steps;

  @override
  void initState() {
    super.initState();
    _steps = [
      '🔍 Đọc lịch sử chat an toàn...',
      '🤖 AI đang phân tích nội dung...',
      '✍️ Viết tóm tắt ${widget.style.label}...',
      '🎨 Hoàn thiện bản tóm tắt...',
    ];
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
      setState(() => _stepIndex = (_stepIndex + 1) % _steps.length);
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>().palette;
    final primary = context.watch<ThemeProvider>().primaryColor;

    return AnimatedBuilder(
      animation: widget.animController,
      builder: (_, __) {
        final glow = (widget.animController.value * 0.4 + 0.6);
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primary.withValues(alpha: 0.2 * glow)),
            boxShadow: [
              BoxShadow(
                  color: primary.withValues(alpha: 0.08 * glow),
                  blurRadius: 20),
            ],
          ),
          child: Column(children: [
            // Animated dots
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ...List.generate(3, (i) {
                final phase =
                    (widget.animController.value * math.pi * 2) - (i * 0.8);
                final scale = (math.sin(phase) * 0.3 + 0.7).clamp(0.5, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: scale),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.3), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                _steps[_stepIndex],
                key: ValueKey(_stepIndex),
                style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: null,
                backgroundColor: p.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(primary),
                minHeight: 3,
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Outline Action Button ────────────────────────────────────────────────────
class _OutlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _OutlineAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>().palette;
    final primary = context.watch<ThemeProvider>().primaryColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: p.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.divider),
        ),
        child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: primary),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE STATE ENUM
// ══════════════════════════════════════════════════════════════════════════════

enum _PageState { idle, loading, success, error }
