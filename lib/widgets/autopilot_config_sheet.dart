// lib/widgets/autopilot_config_sheet.dart
// TÍNH NĂNG 1: AUTOPILOT — BottomSheet cấu hình hoàn chỉnh
// UI: Toggle master, 5 tone cards, schedule grid, away message, persona learning, preview

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/autopilot_provider.dart';
import '../providers/theme_provider.dart';

class AutoPilotConfigSheet extends StatefulWidget {
  final String conversationId;
  final String currentUserId;
  final bool isGroup;

  const AutoPilotConfigSheet({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.isGroup = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
    required String currentUserId,
    bool isGroup = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: true,
      builder: (_) => AutoPilotConfigSheet(
        conversationId: conversationId,
        currentUserId: currentUserId,
        isGroup: isGroup,
      ),
    );
  }

  @override
  State<AutoPilotConfigSheet> createState() => _AutoPilotConfigSheetState();
}

class _AutoPilotConfigSheetState extends State<AutoPilotConfigSheet>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final TextEditingController _awayMsgCtrl;

  bool _isLearning = false;
  bool _isGeneratingPreview = false;
  String? _previewReply;
  Timer? _awayMsgDebounce;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    final pilot = context.read<AutoPilotProvider>();
    final config = pilot.getConfig(widget.conversationId);
    _awayMsgCtrl = TextEditingController(text: config.awayMessage);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _awayMsgCtrl.dispose();
    _awayMsgDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final pilot = context.watch<AutoPilotProvider>();
    final config = pilot.getConfig(widget.conversationId);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: p.shadowStrong,
                blurRadius: 40,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(p),
              _buildHeader(p, theme, config, pilot),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!config.isEnabled) _buildDisabledBanner(p),
                      const SizedBox(height: 16),
                      _buildPersonalitySection(p, theme, config, pilot),
                      const SizedBox(height: 16),
                      _buildScheduleSection(p, theme, config, pilot),
                      const SizedBox(height: 16),
                      _buildAwayMessageSection(p, theme, pilot),
                      const SizedBox(height: 16),
                      _buildLearnStyleSection(p, theme, config, pilot),
                      if (_previewReply != null) ...[
                        const SizedBox(height: 16),
                        _buildPreviewSection(p, theme),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Handle ───────────────────────────────────────────────────────────────

  Widget _buildHandle(ThemePalette p) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotConfig config,
    AutoPilotProvider pilot,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.divider, width: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor.withValues(alpha: 0.18),
                  theme.primaryColor.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.primaryColor.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: theme.primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AutoPilot',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (config.isEnabled && config.isActiveNow)
                      _ActiveBadge(color: theme.primaryColor),
                  ],
                ),
                Text(
                  config.isEnabled
                      ? '${config.tone.emoji} ${config.tone.label} · ${_schedLabel(config)}'
                      : 'Trả lời tự động khi bạn vắng mặt',
                  style: TextStyle(
                    color: config.isEnabled
                        ? theme.primaryColor.withValues(alpha: 0.8)
                        : p.textHint,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          _MasterToggle(
            value: config.isEnabled,
            color: theme.primaryColor,
            onChanged: (val) {
              HapticFeedback.mediumImpact();
              pilot.toggleAutoPlayForConversation(
                widget.conversationId,
                enabled: val,
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Disabled banner ──────────────────────────────────────────────────────

  Widget _buildDisabledBanner(ThemePalette p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: p.textHint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bật AutoPilot để AI tự động trả lời thay bạn khi vắng mặt.',
                style: TextStyle(
                  color: p.textHint,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  // ─── Personality / Tone ───────────────────────────────────────────────────

  Widget _buildPersonalitySection(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotConfig config,
    AutoPilotProvider pilot,
  ) {
    return _SectionCard(
      icon: Icons.palette_outlined,
      title: 'Phong cách trả lời',
      palette: p,
      primary: theme.primaryColor,
      child: Column(
        children: AutoPilotTone.values.map((tone) {
          final isSelected = config.tone == tone;
          return _ToneCard(
            tone: tone,
            isSelected: isSelected,
            palette: p,
            primary: theme.primaryColor,
            onTap: () {
              HapticFeedback.selectionClick();
              pilot.updateTone(widget.conversationId, tone);
              if (!_isGeneratingPreview) {
                _generatePreview(tone, pilot);
              }
            },
          );
        }).toList(),
      ),
    );
  }

  // ─── Schedule ─────────────────────────────────────────────────────────────

  Widget _buildScheduleSection(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotConfig config,
    AutoPilotProvider pilot,
  ) {
    final schedOptions = [
      _ScheduleData(
        mode: ScheduleMode.always,
        label: 'Luôn bật',
        sub: 'Trả lời mọi lúc, không giới hạn giờ',
        icon: Icons.all_inclusive_rounded,
        color: Colors.green,
      ),
      _ScheduleData(
        mode: ScheduleMode.sleepHours,
        label: 'Giờ ngủ',
        sub: '22:00 – 07:00 hàng ngày',
        icon: Icons.bedtime_rounded,
        color: const Color(0xFF6366F1),
      ),
      _ScheduleData(
        mode: ScheduleMode.workHours,
        label: 'Giờ làm việc',
        sub: '08:00 – 18:00 hàng ngày',
        icon: Icons.work_outline_rounded,
        color: const Color(0xFFF59E0B),
      ),
      _ScheduleData(
        mode: ScheduleMode.custom,
        label: 'Tùy chỉnh',
        sub: config.scheduleMode == ScheduleMode.custom
            ? '${_fmtH(config.startHour)} – ${_fmtH(config.endHour)}'
            : 'Thiết lập khung giờ riêng',
        icon: Icons.tune_rounded,
        color: const Color(0xFFEC4899),
      ),
    ];

    return _SectionCard(
      icon: Icons.schedule_rounded,
      title: 'Lịch hoạt động',
      palette: p,
      primary: theme.primaryColor,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: schedOptions.map((s) {
          final isSel = config.scheduleMode == s.mode;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (s.mode == ScheduleMode.custom) {
                _showCustomSchedulePicker(p, theme, config, pilot);
              } else {
                pilot.updateScheduleMode(widget.conversationId, s.mode);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: (MediaQuery.of(context).size.width - 80) / 2,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isSel ? s.color.withValues(alpha: 0.1) : p.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSel ? s.color.withValues(alpha: 0.4) : p.divider,
                  width: isSel ? 1.5 : 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSel
                              ? s.color.withValues(alpha: 0.15)
                              : p.divider.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(s.icon,
                            size: 15, color: isSel ? s.color : p.textHint),
                      ),
                      const Spacer(),
                      if (isSel)
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: s.color),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.label,
                    style: TextStyle(
                      color: isSel ? s.color : p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.sub,
                    style: TextStyle(
                      color: p.textHint,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Away message ─────────────────────────────────────────────────────────

  Widget _buildAwayMessageSection(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotProvider pilot,
  ) {
    return _SectionCard(
      icon: Icons.message_outlined,
      title: 'Tin nhắn dự phòng',
      palette: p,
      primary: theme.primaryColor,
      trailing: Text(
        '${_awayMsgCtrl.text.length}/200',
        style: TextStyle(color: p.textHint, fontSize: 11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dùng khi AI không đủ ngữ cảnh để trả lời hoặc câu hỏi quá phức tạp.',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: p.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.inputBorder),
            ),
            child: TextField(
              controller: _awayMsgCtrl,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'VD: Mình đang bận, sẽ nhắn lại sau nhé! 😊',
                hintStyle: TextStyle(color: p.textHint, fontSize: 13.5),
                contentPadding: const EdgeInsets.all(14),
                border: InputBorder.none,
                counterStyle: TextStyle(color: p.textHint, fontSize: 11),
              ),
              onChanged: (val) {
                setState(() {});
                _awayMsgDebounce?.cancel();
                _awayMsgDebounce = Timer(
                  const Duration(milliseconds: 600),
                  () => pilot.updateAwayMessage(widget.conversationId, val),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Quick templates
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _kAwayTemplates.map((tpl) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _awayMsgCtrl.text = tpl;
                  pilot.updateAwayMessage(widget.conversationId, tpl);
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    tpl.length > 28 ? '${tpl.substring(0, 28)}…' : tpl,
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Learn style ──────────────────────────────────────────────────────────

  Widget _buildLearnStyleSection(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotConfig config,
    AutoPilotProvider pilot,
  ) {
    final hasPersona = config.learnedPersona != null;
    final learnedAt = config.personaLearnedAt;

    return _SectionCard(
      icon: Icons.psychology_rounded,
      title: 'Học phong cách của bạn',
      palette: p,
      primary: theme.primaryColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPersona && learnedAt != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI đã học phong cách nhắn tin của bạn!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Cập nhật: ${_formatDate(learnedAt)}',
                          style: TextStyle(
                            color: Colors.green.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text(
            'AI phân tích lịch sử chat để học cách bạn dùng emoji, độ dài câu và từ ngữ đặc trưng — giúp trả lời tự nhiên và giống bạn hơn.',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: FilledButton.icon(
                onPressed: _isLearning
                    ? null
                    : () => _learnUserStyle(pilot, theme.primaryColor, p),
                icon: _isLearning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        hasPersona
                            ? Icons.refresh_rounded
                            : Icons.auto_fix_high_rounded,
                        size: 18,
                      ),
                label: Text(
                  _isLearning
                      ? 'AI đang học...'
                      : hasPersona
                          ? 'Học lại từ chat mới nhất'
                          : 'Học từ lịch sử chat',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  disabledBackgroundColor:
                      theme.primaryColor.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Preview ──────────────────────────────────────────────────────────────

  Widget _buildPreviewSection(ThemePalette p, ThemeProvider theme) {
    return _SectionCard(
      icon: Icons.visibility_outlined,
      title: 'Xem trước câu trả lời mẫu',
      palette: p,
      primary: theme.primaryColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thử với: "Ê, mày có rảnh tối nay không?"',
            style: TextStyle(color: p.textHint, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Incoming bubble
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.incomingBubble,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                    ),
                    border: Border.all(color: p.divider, width: 0.5),
                  ),
                  child: Text(
                    'Ê, mày có rảnh tối nay không?',
                    style: TextStyle(
                      color: p.incomingText,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _isGeneratingPreview
                      ? const SizedBox(
                          height: 18,
                          width: 60,
                          child: _TypingDots(),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.smart_toy_rounded,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 13),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _previewReply!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Custom schedule picker ───────────────────────────────────────────────

  void _showCustomSchedulePicker(
    ThemePalette p,
    ThemeProvider theme,
    AutoPilotConfig config,
    AutoPilotProvider pilot,
  ) {
    int startH = config.startHour;
    int endH = config.endHour;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => Dialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.tune_rounded,
                          color: theme.primaryColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Giờ hoạt động',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HourWheelPicker(
                        label: 'Từ giờ',
                        value: startH,
                        primary: theme.primaryColor,
                        palette: p,
                        onChanged: (h) => ss(() => startH = h),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            '→',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _HourWheelPicker(
                        label: 'Đến giờ',
                        value: endH,
                        primary: theme.primaryColor,
                        palette: p,
                        onChanged: (h) => ss(() => endH = h),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'AutoPilot sẽ hoạt động từ ${_fmtH(startH)} đến ${_fmtH(endH)}',
                  style: TextStyle(color: p.textHint, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          foregroundColor: p.textSecondary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Huỷ'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          pilot.updateCustomSchedule(
                            widget.conversationId,
                            startHour: startH,
                            endHour: endH,
                          );
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _generatePreview(
    AutoPilotTone tone,
    AutoPilotProvider pilot,
  ) async {
    setState(() {
      _isGeneratingPreview = true;
      _previewReply = '...';
    });
    final preview = await pilot.generatePreviewReply(
      tone: tone,
      sampleMessage: 'Ê, mày có rảnh tối nay không?',
    );
    if (mounted) {
      setState(() {
        _previewReply = preview ?? 'Mình đang bận xíu, lát nhắn lại nha! 😊';
        _isGeneratingPreview = false;
      });
    }
  }

  Future<void> _learnUserStyle(
    AutoPilotProvider pilot,
    Color primary,
    ThemePalette p,
  ) async {
    setState(() => _isLearning = true);
    HapticFeedback.lightImpact();

    final success = await pilot.learnStyleFromHistory(
      conversationId: widget.conversationId,
      currentUserId: widget.currentUserId,
    );

    if (mounted) {
      setState(() => _isLearning = false);
      final snack = SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                success
                    ? '✅ AI đã học phong cách nhắn tin của bạn!'
                    : 'Cần ít nhất 10 tin nhắn để AI có thể học.',
              ),
            ),
          ],
        ),
        backgroundColor: success ? p.successColor : p.warningColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      );
      ScaffoldMessenger.of(context).showSnackBar(snack);
    }
  }

  String _fmtH(int h) => '${h.toString().padLeft(2, '0')}:00';

  String _schedLabel(AutoPilotConfig c) {
    switch (c.scheduleMode) {
      case ScheduleMode.always:
        return 'Luôn bật';
      case ScheduleMode.sleepHours:
        return 'Giờ ngủ';
      case ScheduleMode.workHours:
        return 'Giờ làm';
      case ScheduleMode.custom:
        return '${_fmtH(c.startHour)}–${_fmtH(c.endHour)}';
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _kAwayTemplates = [
  'Mình đang bận, sẽ nhắn lại sau! 😊',
  'Đang không tiện rep, chờ mình nhé 🙏',
  'Mình đang lái xe, lát nhắn lại nhé!',
  'Đang ngủ 😴 sáng mai rep nha',
  'Mình đang họp, để sau nhé!',
];

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets / Components
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleData {
  final ScheduleMode mode;
  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  const _ScheduleData({
    required this.mode,
    required this.label,
    required this.sub,
    required this.icon,
    required this.color,
  });
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final ThemePalette palette;
  final Color primary;
  final Widget? trailing;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    required this.palette,
    required this.primary,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider, width: 0.7),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: primary, size: 15),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          Divider(height: 1, color: palette.divider),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ToneCard extends StatelessWidget {
  final AutoPilotTone tone;
  final bool isSelected;
  final ThemePalette palette;
  final Color primary;
  final VoidCallback onTap;

  const _ToneCard({
    required this.tone,
    required this.isSelected,
    required this.palette,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.07)
              : palette.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected ? primary.withValues(alpha: 0.4) : palette.divider,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? primary.withValues(alpha: 0.1)
                    : palette.divider.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  tone.emoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tone.label,
                    style: TextStyle(
                      color: isSelected ? primary : palette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tone.description,
                    style: TextStyle(
                      color: palette.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? primary : palette.divider,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 13)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MasterToggle extends StatelessWidget {
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  const _MasterToggle({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: 52,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: value ? color : Colors.grey.withValues(alpha: 0.25),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              left: value ? 24 : 2,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  value ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
                  size: 14,
                  color: value ? color : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final Color color;
  const _ActiveBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourWheelPicker extends StatelessWidget {
  final String label;
  final int value;
  final Color primary;
  final ThemePalette palette;
  final ValueChanged<int> onChanged;

  const _HourWheelPicker({
    required this.label,
    required this.value,
    required this.primary,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 130,
          decoration: BoxDecoration(
            color: palette.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: ListWheelScrollView.useDelegate(
            itemExtent: 42,
            physics: const FixedExtentScrollPhysics(),
            controller: FixedExtentScrollController(initialItem: value),
            onSelectedItemChanged: onChanged,
            perspective: 0.004,
            diameterRatio: 1.5,
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (ctx, i) => Center(
                child: Text(
                  '${i.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                    color: i == value ? primary : palette.textSecondary,
                    fontWeight: i == value ? FontWeight.w800 : FontWeight.w400,
                    fontSize: i == value ? 18 : 14,
                  ),
                ),
              ),
              childCount: 24,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${value.toString().padLeft(2, '0')}:00',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// Typing dots animation
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i / 3.0;
            final progress = (((_ctrl.value - delay) % 1.0 + 1.0) % 1.0);
            final scale = 0.6 +
                0.4 * (progress < 0.5 ? progress * 2 : (1 - progress) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white70,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
