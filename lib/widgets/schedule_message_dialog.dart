import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:intl/intl.dart';

enum RepeatOption { none, daily, weekly, monthly }

class ScheduleMessageResult {
  final String message;
  final DateTime scheduledTime;
  final RepeatOption repeat;
  final bool notifyBeforeSend;
  final int? remindBeforeMinutes;

  const ScheduleMessageResult({
    required this.message,
    required this.scheduledTime,
    this.repeat = RepeatOption.none,
    this.notifyBeforeSend = false,
    this.remindBeforeMinutes,
  });
}

class ScheduleMessageDialog extends StatelessWidget {
  final String? initialMessage;
  final DateTime? minDate;

  const ScheduleMessageDialog({
    super.key,
    this.initialMessage,
    this.minDate,
  });

  static Future<ScheduleMessageResult?> show(
    BuildContext context, {
    String? initialMessage,
  }) {
    return showDialog<ScheduleMessageResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => ScheduleMessageDialog(initialMessage: initialMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ScheduleMessageContent(
      initialMessage: initialMessage,
      minDate: minDate,
    );
  }
}

class _ScheduleMessageContent extends StatefulWidget {
  final String? initialMessage;
  final DateTime? minDate;

  const _ScheduleMessageContent({this.initialMessage, this.minDate});

  @override
  State<_ScheduleMessageContent> createState() =>
      _ScheduleMessageContentState();
}

class _ScheduleMessageContentState extends State<_ScheduleMessageContent>
    with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _messageFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  DateTime? _scheduledTime;
  RepeatOption _repeat = RepeatOption.none;
  bool _notifyBefore = false;
  int _remindMinutes = 5;
  bool _isConfirming = false;

  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  late final AnimationController _confirmController;
  late final Animation<double> _confirmScale;

  static const _quickPresets = [
    (label: '30 min', duration: Duration(minutes: 30)),
    (label: '1 hour', duration: Duration(hours: 1)),
    (label: '3 hours', duration: Duration(hours: 3)),
    (label: 'Tomorrow', duration: Duration(days: 1)),
  ];

  @override
  void initState() {
    super.initState();

    if (widget.initialMessage != null) {
      _messageController.text = widget.initialMessage!;
    }

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _entryFade =
        CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));

    _confirmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _confirmScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _confirmController, curve: Curves.easeInOut),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocus.dispose();
    _entryController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final minDate = widget.minDate ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledTime ?? now.add(const Duration(hours: 1)),
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => _themedPicker(ctx, child),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledTime != null
          ? TimeOfDay.fromDateTime(_scheduledTime!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      builder: (ctx, child) => _themedPicker(ctx, child),
    );
    if (time == null || !mounted) return;

    final selected =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (selected.isBefore(now)) {
      _showError('Please choose a future time.');
      return;
    }

    setState(() => _scheduledTime = selected);
    HapticFeedback.lightImpact();
  }

  void _applyQuickPreset(Duration offset) {
    setState(() {
      _scheduledTime = DateTime.now().add(offset);
      final extra = _scheduledTime!.minute % 5;
      if (extra != 0) {
        _scheduledTime = _scheduledTime!
            .add(Duration(minutes: 5 - extra))
            .copyWith(second: 0, millisecond: 0);
      }
    });
    HapticFeedback.selectionClick();
  }

  Widget _themedPicker(BuildContext ctx, Widget? child) {
    return Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: ColorScheme.light(
          primary: ColorConstants.primaryColor,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF1A1A2E),
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
      ),
      child: child!,
    );
  }

  // FIX LỖI 3: Bọc try/finally để _isConfirming luôn được reset dù có lỗi hay không
  Future<void> _handleSchedule() async {
    if (_isConfirming) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      _showError('Message cannot be empty.');
      _messageFocus.requestFocus();
      return;
    }
    if (_scheduledTime == null) {
      _showError('Please select a scheduled time.');
      return;
    }
    if (_scheduledTime!.isBefore(DateTime.now())) {
      _showError('Scheduled time must be in the future.');
      return;
    }

    setState(() => _isConfirming = true);
    try {
      await _confirmController.forward();
      await Future.delayed(const Duration(milliseconds: 80));
      await _confirmController.reverse();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pop(ScheduleMessageResult(
        message: text,
        scheduledTime: _scheduledTime!,
        repeat: _repeat,
        notifyBeforeSend: _notifyBefore,
        remindBeforeMinutes: _notifyBefore ? _remindMinutes : null,
      ));
    } catch (e) {
      debugPrint('❌ _handleSchedule error: $e');
      if (mounted) _showError('Đã xảy ra lỗi, vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(seconds: 3),
      ));
  }

  String get _timeUntilText {
    if (_scheduledTime == null) return '';
    final diff = _scheduledTime!.difference(DateTime.now());
    if (diff.inDays > 0) {
      return 'Sends in ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    }
    if (diff.inHours > 0) {
      return 'Sends in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return 'Sends in ${diff.inMinutes}m';
  }

  Color get _primaryColor => ColorConstants.primaryColor;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            _buildMessageField(),
                            const SizedBox(height: 20),
                            _buildQuickPresets(),
                            const SizedBox(height: 16),
                            _buildDateTimeSelector(),
                            if (_scheduledTime != null) ...[
                              const SizedBox(height: 12),
                              _buildTimeBadge(),
                            ],
                            const SizedBox(height: 20),
                            _buildRepeatSelector(),
                            const SizedBox(height: 16),
                            _buildNotifyToggle(),
                            if (_notifyBefore) ...[
                              const SizedBox(height: 12),
                              _buildRemindSlider(),
                            ],
                            const SizedBox(height: 24),
                            _buildActions(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primaryColor,
            _primaryColor.withValues(alpha: 0.80),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule_send_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schedule Message',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Send automatically at the right time',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Message', Icons.chat_bubble_outline_rounded),
        const SizedBox(height: 8),
        TextFormField(
          controller: _messageController,
          focusNode: _messageFocus,
          maxLines: 3,
          minLines: 2,
          maxLength: 1000,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF1A1A2E), height: 1.5),
          decoration: InputDecoration(
            hintText: 'Type your message here…',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF8F9FF),
            counterStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFFE8ECF4), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _primaryColor, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Quick Schedule', Icons.flash_on_rounded),
        const SizedBox(height: 10),
        Row(
          children: _quickPresets.map((preset) {
            final isSelected = _scheduledTime != null &&
                _scheduledTime!
                        .difference(DateTime.now())
                        .abs()
                        .inMinutes
                        .compareTo(preset.duration.inMinutes) <
                    10;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _QuickChip(
                  label: preset.label,
                  isSelected: isSelected,
                  primaryColor: _primaryColor,
                  onTap: () => _applyQuickPreset(preset.duration),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Custom Date & Time', Icons.calendar_month_rounded),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: _scheduledTime != null
                    ? _primaryColor.withValues(alpha: 0.06)
                    : const Color(0xFFF8F9FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _scheduledTime != null
                      ? _primaryColor.withValues(alpha: 0.40)
                      : const Color(0xFFE8ECF4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _scheduledTime != null
                          ? _primaryColor.withValues(alpha: 0.12)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.calendar_today_rounded,
                      color: _scheduledTime != null
                          ? _primaryColor
                          : Colors.grey.shade500,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _scheduledTime != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEEE, MMM d, yyyy')
                                    .format(_scheduledTime!),
                                style: TextStyle(
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('hh:mm a').format(_scheduledTime!),
                                style: TextStyle(
                                  color: _primaryColor.withValues(alpha: 0.70),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Select date & time',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 14),
                          ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _scheduledTime != null
                        ? _primaryColor
                        : Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // FIX LỖI 1: Thêm .clamp(0.0, 1.0) cho opacity và scale để tránh crash
  // khi Curves.easeOutBack overshoot ra ngoài [0.0, 1.0]
  Widget _buildTimeBadge() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: v.clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _primaryColor.withValues(alpha: 0.10),
              _primaryColor.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _primaryColor.withValues(alpha: 0.20), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: 15, color: _primaryColor),
            const SizedBox(width: 6),
            Text(
              _timeUntilText,
              style: TextStyle(
                color: _primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Repeat', Icons.repeat_rounded),
        const SizedBox(height: 10),
        Row(
          children: RepeatOption.values.map((opt) {
            const labels = {
              RepeatOption.none: 'None',
              RepeatOption.daily: 'Daily',
              RepeatOption.weekly: 'Weekly',
              RepeatOption.monthly: 'Monthly',
            };
            final isSelected = _repeat == opt;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 7),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _repeat = opt);
                    HapticFeedback.selectionClick();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? _primaryColor : const Color(0xFFF8F9FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? _primaryColor
                            : const Color(0xFFE8ECF4),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      labels[opt]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNotifyToggle() {
    return GestureDetector(
      onTap: () {
        setState(() => _notifyBefore = !_notifyBefore);
        HapticFeedback.lightImpact();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _notifyBefore
              ? _primaryColor.withValues(alpha: 0.06)
              : const Color(0xFFF8F9FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _notifyBefore
                ? _primaryColor.withValues(alpha: 0.35)
                : const Color(0xFFE8ECF4),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: _notifyBefore ? _primaryColor : Colors.grey.shade500,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remind me before sending',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _notifyBefore
                          ? _primaryColor
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (_notifyBefore) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Get a heads-up $_remindMinutes min before',
                      style: TextStyle(
                          fontSize: 11,
                          color: _primaryColor.withValues(alpha: 0.70)),
                    ),
                  ],
                ],
              ),
            ),
            _AnimatedSwitch(
              value: _notifyBefore,
              primaryColor: _primaryColor,
              onChanged: (v) => setState(() => _notifyBefore = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemindSlider() {
    final options = [2, 5, 10, 15, 30, 60];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, v, child) =>
          Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Wrap(
          spacing: 8,
          children: options.map((min) {
            final selected = _remindMinutes == min;
            return GestureDetector(
              onTap: () {
                setState(() => _remindMinutes = min);
                HapticFeedback.selectionClick();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? _primaryColor : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  min < 60 ? '${min}m' : '1h',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200, width: 1.5),
              ),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ScaleTransition(
            scale: _confirmScale,
            child: Material(
              borderRadius: BorderRadius.circular(14),
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primaryColor,
                      _primaryColor
                          .withBlue((_primaryColor.blue + 30).clamp(0, 255)),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isConfirming ? null : _handleSchedule,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    child: _isConfirming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule_send_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Schedule',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _primaryColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  State<_QuickChip> createState() => _QuickChipState();
}

class _QuickChipState extends State<_QuickChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _c.forward(),
      onTapUp: (_) {
        _c.reverse();
        widget.onTap();
      },
      onTapCancel: () => _c.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.primaryColor
                : const Color(0xFFF8F9FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected
                  ? widget.primaryColor
                  : const Color(0xFFE8ECF4),
              width: 1.5,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.isSelected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedSwitch extends StatelessWidget {
  final bool value;
  final Color primaryColor;
  final ValueChanged<bool> onChanged;

  const _AnimatedSwitch({
    required this.value,
    required this.primaryColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? primaryColor : Colors.grey.shade300,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
