// lib/widgets/reminder_item_widget.dart
// Reusable reminder widgets dùng trong chat page và mọi nơi khác

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INLINE CARD – dùng trong chat bubble / message options
// ─────────────────────────────────────────────────────────────────────────────

class ReminderItemWidget extends StatefulWidget {
  final EnhancedReminder reminder;
  final ThemePalette palette;
  final Color primaryColor;
  final bool isCompact;
  final VoidCallback? onComplete;
  final VoidCallback? onSnooze;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const ReminderItemWidget({
    super.key,
    required this.reminder,
    required this.palette,
    required this.primaryColor,
    this.isCompact = false,
    this.onComplete,
    this.onSnooze,
    this.onDelete,
    this.onTap,
  });

  @override
  State<ReminderItemWidget> createState() => _ReminderItemWidgetState();
}

class _ReminderItemWidgetState extends State<ReminderItemWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    if (widget.reminder.isDueSoon) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isCompact ? _buildCompact() : _buildFull();
  }

  // ── COMPACT (tiny chip in chat) ───────────────────────────────────────────

  Widget _buildCompact() {
    final r = widget.reminder;
    final p = widget.palette;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: r.priority.color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: r.priority.color.withValues(alpha: .28), width: .8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm_rounded, color: r.priority.color, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                r.message,
                style: TextStyle(
                  color: r.priority.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _shortTime(r.reminderTime),
              style: TextStyle(
                  color: r.priority.color.withValues(alpha: .7),
                  fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── FULL CARD ─────────────────────────────────────────────────────────────

  Widget _buildFull() {
    final r = widget.reminder;
    final p = widget.palette;
    final accentColor = r.isDueSoon
        ? const Color(0xFFEF4444)
        : r.isOverdue
            ? const Color(0xFFDC2626)
            : r.priority.color;

    return ScaleTransition(
      scale: r.isDueSoon ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: r.isDueSoon ? .45 : .2),
              width: r.isDueSoon ? 1.4 : .8,
            ),
            boxShadow: [
              BoxShadow(
                  color: accentColor.withValues(alpha: .06),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ───────────────────────────────────────
                Row(
                  children: [
                    // Left accent bar
                    Container(
                      width: 3,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badges
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              _RBadge(
                                  text:
                                      '${r.priority.emoji} ${r.priority.label}',
                                  color: r.priority.color),
                              _RBadge(
                                  text:
                                      '${r.category.emoji} ${r.category.label}',
                                  color: widget.primaryColor),
                              if (r.isAutoGenerated)
                                _RBadge(
                                  text: '⚡ AI',
                                  color: const Color(0xFF6C63FF),
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFF2196F3),
                                  ]),
                                ),
                              if (r.isDueSoon && !r.isCompleted)
                                _RBadge(
                                    text: '🔥 Sắp đến',
                                    color: const Color(0xFFEF4444)),
                              if (r.isOverdue && !r.isCompleted)
                                _RBadge(
                                    text: '🚨 Quá hạn',
                                    color: const Color(0xFFDC2626)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Message
                          Text(
                            r.message,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          // Time row
                          _TimeRow(
                            reminder: r,
                            palette: p,
                            accentColor: accentColor,
                          ),
                          if (r.deadline != null) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.flag_rounded,
                                  size: 12, color: p.warningColor),
                              const SizedBox(width: 4),
                              Text('Deadline: ${r.deadline}',
                                  style: TextStyle(
                                      color: p.warningColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500)),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    // Delete button
                    if (widget.onDelete != null)
                      GestureDetector(
                        onTap: widget.onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: p.textHint),
                        ),
                      ),
                  ],
                ),

                // ── Action bar ───────────────────────────────────────
                if (!r.isCompleted &&
                    (widget.onSnooze != null || widget.onComplete != null)) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    if (widget.onSnooze != null)
                      Expanded(
                        child: _RActionBtn(
                          icon: Icons.snooze_rounded,
                          label: 'Hoãn',
                          color: const Color(0xFF6C63FF),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onSnooze?.call();
                          },
                        ),
                      ),
                    if (widget.onSnooze != null && widget.onComplete != null)
                      const SizedBox(width: 8),
                    if (widget.onComplete != null)
                      Expanded(
                        child: _RActionBtn(
                          icon: Icons.check_circle_rounded,
                          label: 'Hoàn thành',
                          color: const Color(0xFF22C55E),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onComplete?.call();
                          },
                        ),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortTime(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Quá hạn';
    if (diff.inMinutes < 60) return '${diff.inMinutes}ph';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return DateFormat('dd/MM').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PENDING REMINDERS BAR (used at top of chat page)
// ─────────────────────────────────────────────────────────────────────────────

class InlinePendingRemindersBar extends StatelessWidget {
  final List<EnhancedReminder> reminders;
  final ThemePalette palette;
  final Color primaryColor;
  final VoidCallback onViewAll;

  const InlinePendingRemindersBar({
    super.key,
    required this.reminders,
    required this.palette,
    required this.primaryColor,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) return const SizedBox.shrink();
    final p = palette;
    final dueSoon = reminders.where((r) => r.isDueSoon).length;
    final overdue = reminders.where((r) => r.isOverdue).length;
    final urgent = dueSoon + overdue;
    final accentColor = urgent > 0 ? const Color(0xFFEF4444) : primaryColor;

    return GestureDetector(
      onTap: onViewAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            accentColor.withValues(alpha: .07),
            primaryColor.withValues(alpha: .07),
          ]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: .28)),
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              urgent > 0 ? Icons.alarm_on_rounded : Icons.alarm_rounded,
              color: accentColor,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  urgent > 0
                      ? '⚡ $urgent nhắc nhở cần chú ý'
                      : '⏰ ${reminders.length} nhắc nhở đang chờ',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reminders.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reminders.first.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          // Chips
          _CountChip(
            count: reminders.length,
            color: primaryColor,
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 16, color: p.textHint),
        ]),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final int count;
  final Color color;
  const _CountChip({required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK SNOOZE DIALOG (mini – from anywhere)
// ─────────────────────────────────────────────────────────────────────────────

class QuickSnoozeDialog extends StatelessWidget {
  final EnhancedReminder reminder;
  final ThemePalette palette;
  final Color primaryColor;
  final ReminderProvider provider;
  final void Function(bool ok)? onDone;

  const QuickSnoozeDialog({
    super.key,
    required this.reminder,
    required this.palette,
    required this.primaryColor,
    required this.provider,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: p.shadowStrong,
                blurRadius: 30,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.snooze_rounded,
                    color: Color(0xFF6C63FF), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hoãn nhắc nhở',
                        style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(
                      reminder.message.length > 35
                          ? '${reminder.message.substring(0, 35)}…'
                          : reminder.message,
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Options grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: SnoozeOption.values
                  .map((opt) => _SnoozeBtn(
                        option: opt,
                        palette: p,
                        primaryColor: primaryColor,
                        onTap: () async {
                          Navigator.pop(context);
                          final ok = await provider.snoozeReminder(reminder.id,
                              option: opt);
                          onDone?.call(ok);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Huỷ',
                  style: TextStyle(color: p.textSecondary, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnoozeBtn extends StatelessWidget {
  final SnoozeOption option;
  final ThemePalette palette;
  final Color primaryColor;
  final VoidCallback onTap;

  const _SnoozeBtn({
    required this.option,
    required this.palette,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: primaryColor.withValues(alpha: .18), width: .8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(option.icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(option.label,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI REMINDER SUGGESTION PANEL (used after message send)
// ─────────────────────────────────────────────────────────────────────────────

class AiReminderSuggestionPanel extends StatefulWidget {
  final List<ExtractedReminder> extracted;
  final ThemePalette palette;
  final Color primaryColor;
  final void Function(ExtractedReminder) onAccept;
  final VoidCallback onDismissAll;

  const AiReminderSuggestionPanel({
    super.key,
    required this.extracted,
    required this.palette,
    required this.primaryColor,
    required this.onAccept,
    required this.onDismissAll,
  });

  @override
  State<AiReminderSuggestionPanel> createState() =>
      _AiReminderSuggestionPanelState();
}

class _AiReminderSuggestionPanelState extends State<AiReminderSuggestionPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  final Set<int> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.extracted
        .asMap()
        .entries
        .where((e) => !_dismissed.contains(e.key))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();
    final p = widget.palette;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, .3), end: Offset.zero)
          .animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: _slide,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFF6C63FF).withValues(alpha: .08),
              widget.primaryColor.withValues(alpha: .08),
            ]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFF6C63FF).withValues(alpha: .25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFF6C63FF),
                      widget.primaryColor,
                    ]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 11),
                      SizedBox(width: 4),
                      Text('AI phát hiện tác vụ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onDismissAll,
                  child: Icon(Icons.close_rounded, size: 18, color: p.textHint),
                ),
              ]),
              const SizedBox(height: 10),

              // Extracted items
              ...visible.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return _ExtractedItem(
                  item: item,
                  palette: p,
                  primaryColor: widget.primaryColor,
                  onAccept: () {
                    HapticFeedback.lightImpact();
                    widget.onAccept(item);
                    setState(() => _dismissed.add(idx));
                  },
                  onDismiss: () {
                    HapticFeedback.selectionClick();
                    setState(() => _dismissed.add(idx));
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtractedItem extends StatelessWidget {
  final ExtractedReminder item;
  final ThemePalette palette;
  final Color primaryColor;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _ExtractedItem({
    required this.item,
    required this.palette,
    required this.primaryColor,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.priority.color.withValues(alpha: .2)),
      ),
      child: Row(children: [
        // Priority indicator
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: item.priority.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child:
                Text(item.priority.emoji, style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 10),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.task,
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.reminderTimeHint != null) ...[
                const SizedBox(height: 2),
                Text(
                  '⏰ ${item.reminderTimeHint}',
                  style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        // Actions
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 15, color: p.textHint),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onAccept,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('+ Nhắc',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MICRO COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _RBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Gradient? gradient;
  const _RBadge({required this.text, required this.color, this.gradient});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: gradient == null ? color.withValues(alpha: .11) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(7),
          border: gradient == null
              ? Border.all(color: color.withValues(alpha: .28), width: .6)
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: gradient != null ? Colors.white : color,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _RActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .2), width: .8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _TimeRow extends StatelessWidget {
  final EnhancedReminder reminder;
  final ThemePalette palette;
  final Color accentColor;
  const _TimeRow({
    required this.reminder,
    required this.palette,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final p = palette;
    final now = DateTime.now();
    final diff = r.reminderTime.difference(now);

    String timeLabel;
    if (diff.isNegative) {
      final ago = now.difference(r.reminderTime);
      timeLabel = ago.inMinutes < 60
          ? 'Quá hạn ${ago.inMinutes} phút'
          : ago.inHours < 24
              ? 'Quá hạn ${ago.inHours} giờ'
              : 'Quá hạn ${DateFormat('dd/MM').format(r.reminderTime)}';
    } else if (diff.inMinutes < 60) {
      timeLabel = 'Còn ${diff.inMinutes} phút';
    } else if (diff.inHours < 24) {
      timeLabel = r.reminderTime.day == now.day
          ? 'Hôm nay ${DateFormat('HH:mm').format(r.reminderTime)}'
          : DateFormat('HH:mm, dd/MM').format(r.reminderTime);
    } else {
      timeLabel = DateFormat('HH:mm, dd/MM/yyyy').format(r.reminderTime);
    }

    return Row(children: [
      Icon(Icons.schedule_rounded,
          size: 12,
          color: r.isDueSoon || r.isOverdue ? accentColor : p.textHint),
      const SizedBox(width: 4),
      Text(timeLabel,
          style: TextStyle(
            color: r.isDueSoon || r.isOverdue ? accentColor : p.textHint,
            fontSize: 11.5,
            fontWeight:
                r.isDueSoon || r.isOverdue ? FontWeight.w700 : FontWeight.w400,
          )),
      if (r.repeat != ReminderRepeat.none) ...[
        const SizedBox(width: 8),
        Icon(Icons.repeat_rounded, size: 11, color: p.textHint),
        const SizedBox(width: 3),
        Text(r.repeat.shortLabel,
            style: TextStyle(color: p.textHint, fontSize: 10.5)),
      ],
      if (r.snoozeCount > 0) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withValues(alpha: .1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('${r.snoozeCount}× hoãn',
              style: const TextStyle(
                  color: Color(0xFF6C63FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}
