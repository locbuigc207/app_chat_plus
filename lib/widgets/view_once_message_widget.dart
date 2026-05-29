import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

enum ViewOnceState {
  locked,
  revealing,
  expiring,
  viewed,
}

class CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color foreColor;
  final Color trackColor;
  final double strokeWidth;

  const CountdownRingPainter({
    required this.progress,
    required this.foreColor,
    required this.trackColor,
    this.strokeWidth = 2.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint..color = trackColor);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        paint..color = foreColor,
      );
    }
  }

  @override
  bool shouldRepaint(CountdownRingPainter old) =>
      old.progress != progress || old.foreColor != foreColor || old.trackColor != trackColor;
}

class ViewOnceMessageWidget extends StatefulWidget {
  final String groupChatId;
  final String messageId;
  final String content;
  final int type;
  final String currentUserId;
  final bool isViewed;
  final ViewOnceProvider provider;

  final int viewDurationSeconds;

  const ViewOnceMessageWidget({
    super.key,
    required this.groupChatId,
    required this.messageId,
    required this.content,
    required this.type,
    required this.currentUserId,
    required this.isViewed,
    required this.provider,
    this.viewDurationSeconds = 10,
  });

  @override
  State<ViewOnceMessageWidget> createState() => _ViewOnceMessageWidgetState();
}

class _ViewOnceMessageWidgetState extends State<ViewOnceMessageWidget>
    with TickerProviderStateMixin {
  ViewOnceState _state = ViewOnceState.locked;

  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  double _countdownProgress = 1.0;

  late AnimationController _lockPulseCtrl;
  late AnimationController _revealCtrl;
  late AnimationController _expiringCtrl;
  late AnimationController _viewedCtrl;
  late AnimationController _shakeCtrl;

  late Animation<double> _lockPulse;
  late Animation<double> _revealScale;
  late Animation<double> _revealOpacity;
  late Animation<double> _expiringBorderPulse;
  late Animation<double> _viewedOpacity;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    if (widget.isViewed) _state = ViewOnceState.viewed;
    _remainingSeconds = widget.viewDurationSeconds;

    _lockPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _lockPulse = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _lockPulseCtrl, curve: Curves.easeInOut),
    );

    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _revealScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOutBack),
    );
    _revealOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut),
    );

    _expiringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _expiringBorderPulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expiringCtrl, curve: Curves.easeInOut),
    );

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: -1.0, end: 1.0)
        .chain(CurveTween(curve: _ShakeCurve()))
        .animate(_shakeCtrl);

    _viewedCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _viewedOpacity = CurvedAnimation(parent: _viewedCtrl, curve: Curves.easeOut);

    if (_state == ViewOnceState.viewed) _viewedCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _lockPulseCtrl.dispose();
    _revealCtrl.dispose();
    _expiringCtrl.dispose();
    _shakeCtrl.dispose();
    _viewedCtrl.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_state != ViewOnceState.locked) return;
    HapticFeedback.heavyImpact();

    setState(() {
      _state = ViewOnceState.revealing;
      _remainingSeconds = widget.viewDurationSeconds;
      _countdownProgress = 1.0;
    });

    _revealCtrl.forward();
    _startCountdown();

    await widget.provider.openViewOnceMessage(
      groupChatId: widget.groupChatId,
      messageId: widget.messageId,
      userId: widget.currentUserId,
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
        _countdownProgress = (_remainingSeconds / widget.viewDurationSeconds).clamp(0.0, 1.0);
      });

      if (_remainingSeconds == 3 && _state == ViewOnceState.revealing) {
        setState(() => _state = ViewOnceState.expiring);
        HapticFeedback.mediumImpact();
        _shakeCtrl.forward(from: 0);
      }

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _expire();
      }
    });
  }

  Future<void> _expire() async {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    await _revealCtrl.reverse();
    if (mounted) {
      setState(() => _state = ViewOnceState.viewed);
      _viewedCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      ViewOnceState.locked => _buildLocked(),
      ViewOnceState.revealing => _buildRevealing(isExpiring: false),
      ViewOnceState.expiring => _buildRevealing(isExpiring: true),
      ViewOnceState.viewed => _buildViewed(),
    };
  }

  Widget _buildLocked() {
    return AnimatedBuilder(
      animation: _lockPulse,
      builder: (_, child) => Transform.scale(scale: _lockPulse.value, child: child),
      child: GestureDetector(
        onTap: _reveal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
              stops: [0.0, 0.55, 1.0],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE94057).withValues(alpha: 0.38),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tin nhắn bí mật',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhấn để mở · chỉ xem 1 lần',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevealing({required bool isExpiring}) {
    const activeColor = Color(0xFF34C759);
    const expiringColor = Color(0xFFFF6B35);
    final borderColor = isExpiring ? expiringColor : activeColor;

    return AnimatedBuilder(
      animation: Listenable.merge([_revealCtrl, _expiringBorderPulse, _shakeAnim]),
      builder: (_, __) {
        return FadeTransition(
          opacity: _revealOpacity,
          child: ScaleTransition(
            scale: _revealScale,
            child: Transform.translate(
              offset: isExpiring ? Offset(_shakeAnim.value * 3, 0) : Offset.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isExpiring
                        ? Color.lerp(
                                expiringColor, const Color(0xFFE94057), _expiringBorderPulse.value)!
                            .withValues(alpha: 0.85)
                        : activeColor.withValues(alpha: 0.45),
                    width: isExpiring ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withValues(
                        alpha: isExpiring ? 0.18 + _expiringBorderPulse.value * 0.12 : 0.10,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: isExpiring
                            ? expiringColor.withValues(
                                alpha: 0.07 + _expiringBorderPulse.value * 0.05)
                            : const Color(0xFFF8F8FA),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(19),
                          topRight: Radius.circular(19),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            height: 30,
                            child: CustomPaint(
                              painter: CountdownRingPainter(
                                progress: _countdownProgress,
                                foreColor: isExpiring
                                    ? Color.lerp(
                                        expiringColor,
                                        const Color(0xFFE94057),
                                        _expiringBorderPulse.value,
                                      )!
                                    : activeColor,
                                trackColor: borderColor.withValues(alpha: 0.15),
                              ),
                              child: Center(
                                child: Text(
                                  '$_remainingSeconds',
                                  style: TextStyle(
                                    color: isExpiring
                                        ? Color.lerp(
                                            expiringColor,
                                            const Color(0xFFE94057),
                                            _expiringBorderPulse.value,
                                          )
                                        : activeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Text(
                                isExpiring ? '⚠ Sắp biến mất!' : 'Đang hiển thị · tự xoá sau',
                                key: ValueKey(isExpiring),
                                style: TextStyle(
                                  color: isExpiring ? expiringColor : const Color(0xFF8E8E93),
                                  fontSize: 11.5,
                                  fontWeight: isExpiring ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                          Icon(
                            Icons.visibility_rounded,
                            size: 14,
                            color: borderColor.withValues(alpha: 0.65),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: _buildContent(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (widget.type == TypeMessage.text) {
      return Text(
        widget.content,
        style: const TextStyle(
          color: Color(0xFF111418),
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.55,
        ),
      );
    }

    if (widget.type == TypeMessage.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          widget.content,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 220,
              height: 220,
              color: const Color(0xFFF2F2F7),
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2.5,
                  color: const Color(0xFFE94057),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 220,
            height: 220,
            color: const Color(0xFFF2F2F7),
            child: const Center(
              child: Icon(Icons.broken_image_rounded, color: Color(0xFFAAAAAA), size: 36),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildViewed() {
    return FadeTransition(
      opacity: _viewedOpacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility_off_rounded,
                color: Color(0xFF8E8E93),
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Đã xem',
                  style: TextStyle(
                    color: Color(0xFF3C3C43),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tin nhắn này không thể xem lại',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontStyle: FontStyle.italic,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShakeCurve extends Curve {
  @override
  double transformInternal(double t) => math.sin(t * math.pi * 4) * (1 - t);
}

class SendViewOnceDialog extends StatefulWidget {
  final Function(String content, int type, int durationSeconds) onSend;

  const SendViewOnceDialog({
    super.key,
    required this.onSend,
  });

  @override
  State<SendViewOnceDialog> createState() => _SendViewOnceDialogState();
}

class _SendViewOnceDialogState extends State<SendViewOnceDialog>
    with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  bool _isText = true;
  int _selectedDuration = 10;

  late AnimationController _entryCtrl;
  late Animation<double> _entrySlide;
  late Animation<double> _entryOpacity;

  static const List<int> _durations = [5, 10, 30, 60];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
    _urlCtrl.addListener(() => setState(() {}));

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
    _entryOpacity = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<double>(begin: 0.08, end: 0.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _urlCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  bool get _canSend {
    if (_isText) return _textCtrl.text.trim().isNotEmpty;
    return _urlCtrl.text.trim().isNotEmpty;
  }

  void _send() {
    if (!_canSend) return;
    widget.onSend(
      _isText ? _textCtrl.text.trim() : _urlCtrl.text.trim(),
      _isText ? TypeMessage.text : TypeMessage.image,
      _selectedDuration,
    );
    Navigator.pop(context);
  }

  String _durationLabel(int s) {
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (_, child) => FadeTransition(
        opacity: _entryOpacity,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, _entrySlide.value),
            end: Offset.zero,
          ).animate(_entryCtrl),
          child: child,
        ),
      ),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        backgroundColor: Colors.white,
        elevation: 24,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildTypeTabs(),
              const SizedBox(height: 16),
              _buildInputField(),
              const SizedBox(height: 16),
              _buildDurationSelector(),
              const SizedBox(height: 20),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8A2387), Color(0xFFE94057)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE94057).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.lock_clock_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tin nhắn bí mật',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
                color: Color(0xFF111418),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tự xoá sau khi người nhận xem xong',
              style: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeTabs() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _TabBtn(
            label: 'Văn bản',
            icon: Icons.text_fields_rounded,
            isSelected: _isText,
            onTap: () => setState(() => _isText = true),
          ),
          _TabBtn(
            label: 'Hình ảnh',
            icon: Icons.image_rounded,
            isSelected: !_isText,
            onTap: () => setState(() => _isText = false),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: _isText
          ? _styledField(
              key: const ValueKey('text'),
              controller: _textCtrl,
              hint: 'Nhập nội dung bí mật...',
              maxLines: 4,
              maxLength: 500,
              prefixIcon: null,
            )
          : _styledField(
              key: const ValueKey('url'),
              controller: _urlCtrl,
              hint: 'Dán URL hình ảnh vào đây...',
              maxLines: 1,
              prefixIcon: Icons.link_rounded,
            ),
    );
  }

  Widget _styledField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    int? maxLength,
    IconData? prefixIcon,
  }) {
    const borderRadius = 14.0;
    const borderColor = Color(0xFFE5E5EA);
    const focusColor = Color(0xFFE94057);

    return TextField(
      key: key,
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF9F9FB),
        prefixIcon:
            prefixIcon != null ? Icon(prefixIcon, color: const Color(0xFFAAAAAA), size: 20) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: focusColor, width: 1.5),
        ),
        counterStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 11),
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF8E8E93)),
            const SizedBox(width: 5),
            const Text(
              'Thời gian xem',
              style: TextStyle(
                color: Color(0xFF3C3C43),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: _durations.map((d) {
            final selected = d == _selectedDuration;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedDuration = d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: [Color(0xFF8A2387), Color(0xFFE94057)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: selected ? null : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE94057).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _durationLabel(d),
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF3C3C43),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE5E5EA)),
              ),
            ),
            child: const Text(
              'Hủy',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: AnimatedOpacity(
            opacity: _canSend ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton(
              onPressed: _canSend ? _send : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFFE94057),
                disabledBackgroundColor: const Color(0xFFE94057).withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 15, color: Colors.white),
                  SizedBox(width: 7),
                  Text(
                    'Gửi bí mật',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabBtn({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: double.infinity,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFFE94057) : const Color(0xFF8E8E93),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF111418) : const Color(0xFF8E8E93),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
