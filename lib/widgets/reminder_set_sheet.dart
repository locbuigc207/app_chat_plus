// lib/widgets/reminder_set_sheet.dart
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

// ─────────────────────────────────────────────────────────────────────────
// Bottom sheet để đặt nhắc nhở từ 1 tin nhắn cụ thể (chat 1-1 & group)
// Trả về Map<String,dynamic>{ 'time': DateTime, 'priority': ReminderPriority,
//                              'category': ReminderCategory, 'repeat': ReminderRepeat }
// ─────────────────────────────────────────────────────────────────────────
class ReminderSetSheet extends StatefulWidget {
  final String message;
  final ThemePalette palette;
  final ThemeProvider theme;

  const ReminderSetSheet({
    super.key,
    required this.message,
    required this.palette,
    required this.theme,
  });

  @override
  State<ReminderSetSheet> createState() => _ReminderSetSheetState();
}

class _ReminderSetSheetState extends State<ReminderSetSheet> {
  DateTime? _selectedTime;
  ReminderPriority _priority = ReminderPriority.medium;
  ReminderCategory _category = ReminderCategory.other;
  ReminderRepeat _repeat = ReminderRepeat.none;
  int _quickIndex = -1;

  static final _quickOptions = <_QuickTime>[
    _QuickTime('15 phút', const Duration(minutes: 15), Icons.bolt_rounded),
    _QuickTime('1 giờ', const Duration(hours: 1), Icons.schedule_rounded),
    _QuickTime('3 giờ', const Duration(hours: 3), Icons.access_time_rounded),
    _QuickTime('Tối nay', null, Icons.nightlight_round),
    _QuickTime('Ngày mai', null, Icons.wb_sunny_rounded),
    _QuickTime('Tuần sau', const Duration(days: 7), Icons.date_range_rounded),
  ];

  DateTime _resolveQuick(int i) {
    final now = DateTime.now();
    switch (i) {
      case 3: // Tối nay 20:00
        final t = DateTime(now.year, now.month, now.day, 20);
        return t.isAfter(now) ? t : t.add(const Duration(days: 1));
      case 4: // Ngày mai 9:00
        final tmr = now.add(const Duration(days: 1));
        return DateTime(tmr.year, tmr.month, tmr.day, 9);
      default:
        return now.add(_quickOptions[i].duration!);
    }
  }

  Future<void> _pickCustom() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: widget.theme.primaryColor,
              ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;

    // ignore: use_build_context_synchronously
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now().replacing(
        minute: ((TimeOfDay.now().minute + 5) ~/ 5) * 5 % 60,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: widget.theme.primaryColor,
              ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _quickIndex = -1;
      _selectedTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final theme = widget.theme;
    final dt =
        _selectedTime ?? (_quickIndex >= 0 ? _resolveQuick(_quickIndex) : null);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: p.textSecondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      theme.primaryColor,
                      theme.primaryColor.withValues(alpha: 0.6),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.alarm_add_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Đặt nhắc nhở',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary)),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: p.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: p.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.divider.withValues(alpha: 0.3)),
              ),
              child: Text(
                widget.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: p.textSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.4),
              ),
            ),
            const SizedBox(height: 20),

            // Quick time chips
            Text('Thời gian',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_quickOptions.length, (i) {
                final opt = _quickOptions[i];
                final selected = _quickIndex == i;
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _quickIndex = i;
                      _selectedTime = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? theme.primaryColor : p.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? theme.primaryColor
                            : p.divider.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(opt.icon,
                          size: 15,
                          color: selected ? Colors.white : p.textSecondary),
                      const SizedBox(width: 6),
                      Text(opt.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : p.textPrimary)),
                    ]),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickCustom,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedTime != null
                        ? theme.primaryColor
                        : p.divider.withValues(alpha: 0.4),
                    width: _selectedTime != null ? 1.5 : 1,
                  ),
                  color: _selectedTime != null
                      ? theme.primaryColor.withValues(alpha: 0.08)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_calendar_rounded,
                        size: 17,
                        color: _selectedTime != null
                            ? theme.primaryColor
                            : p.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      _selectedTime != null
                          ? _fmtDateTime(_selectedTime!)
                          : 'Chọn thời gian khác',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _selectedTime != null
                            ? theme.primaryColor
                            : p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),
            Text('Mức độ ưu tiên',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary)),
            const SizedBox(height: 10),
            Row(
              children: ReminderPriority.values.asMap().entries.map((e) {
                final pr = e.value;
                final selected = _priority == pr;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: e.key == ReminderPriority.values.length - 1
                            ? 0
                            : 8),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _priority = pr);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? pr.color.withValues(alpha: 0.15)
                              : p.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? pr.color
                                : p.divider.withValues(alpha: 0.3),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(children: [
                          Text(pr.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(pr.label,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      selected ? pr.color : p.textSecondary)),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 22),
            Text('Danh mục',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReminderCategory.values.map((cat) {
                final selected = _category == cat;
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _category = cat);
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.primaryColor.withValues(alpha: 0.12)
                          : p.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? theme.primaryColor
                            : p.divider.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(cat.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? theme.primaryColor
                                  : p.textPrimary)),
                    ]),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 22),
            Text('Lặp lại',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReminderRepeat.values.map((rep) {
                final selected = _repeat == rep;
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _repeat = rep);
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.primaryColor.withValues(alpha: 0.12)
                          : p.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? theme.primaryColor
                            : p.divider.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(rep.label,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color:
                                selected ? theme.primaryColor : p.textPrimary)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: dt == null
                    ? null
                    : () => Navigator.pop(context, {
                          'time': dt,
                          'priority': _priority,
                          'category': _category,
                          'repeat': _repeat,
                        }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  disabledBackgroundColor: p.divider.withValues(alpha: 0.3),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  dt != null
                      ? 'Đặt nhắc nhở • ${_fmtDateTime(dt)}'
                      : 'Chọn thời gian',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTime {
  final String label;
  final Duration? duration;
  final IconData icon;
  const _QuickTime(this.label, this.duration, this.icon);
}

String _fmtDateTime(DateTime dt) {
  final now = DateTime.now();
  final isToday =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow = dt.year == tomorrow.year &&
      dt.month == tomorrow.month &&
      dt.day == tomorrow.day;
  final hm =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (isToday) return 'Hôm nay, $hm';
  if (isTomorrow) return 'Ngày mai, $hm';
  return '${dt.day}/${dt.month}/${dt.year}, $hm';
}
