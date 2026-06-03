import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ══════════════════════════════════════════════════════
// CALL CONTROL BAR
// A glassmorphism floating control panel for active calls
// ══════════════════════════════════════════════════════
class CallControlBar extends StatelessWidget {
  final bool isVideoCall;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final VoidCallback onMuteTap;
  final VoidCallback? onCameraTap;
  final VoidCallback onSpeakerTap;
  final VoidCallback? onSwitchCameraTap;
  final VoidCallback onEndCall;
  final VoidCallback? onKeypadTap;

  const CallControlBar({
    super.key,
    required this.isVideoCall,
    required this.isMuted,
    required this.isCameraOff,
    required this.isSpeakerOn,
    required this.isFrontCamera,
    required this.onMuteTap,
    this.onCameraTap,
    required this.onSpeakerTap,
    this.onSwitchCameraTap,
    required this.onEndCall,
    this.onKeypadTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: isVideoCall ? _buildVideoControls() : _buildVoiceControls(),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CtrlBtn(
          icon: isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
          label: isMuted ? 'Bật mic' : 'Tắt mic',
          isActive: isMuted,
          activeColor: Colors.redAccent,
          onTap: () {
            HapticFeedback.lightImpact();
            onMuteTap();
          },
        ),
        _CtrlBtn(
          icon: isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: isSpeakerOn ? 'Loa ngoài' : 'Tai nghe',
          isActive: isSpeakerOn,
          activeColor: const Color(0xFF5C6BC0),
          onTap: () {
            HapticFeedback.lightImpact();
            onSpeakerTap();
          },
        ),
        _CtrlBtn(
          icon: Icons.dialpad_rounded,
          label: 'Bàn phím',
          isActive: false,
          activeColor: Colors.white,
          onTap: () {
            HapticFeedback.lightImpact();
            onKeypadTap?.call();
          },
        ),
        _EndCallBtn(onTap: onEndCall),
      ],
    );
  }

  Widget _buildVideoControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CtrlBtn(
          icon: isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
          label: isMuted ? 'Bật mic' : 'Tắt mic',
          isActive: isMuted,
          activeColor: Colors.redAccent,
          onTap: () {
            HapticFeedback.lightImpact();
            onMuteTap();
          },
        ),
        _CtrlBtn(
          icon:
              isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: isCameraOff ? 'Bật cam' : 'Tắt cam',
          isActive: isCameraOff,
          activeColor: Colors.orangeAccent,
          onTap: () {
            HapticFeedback.lightImpact();
            onCameraTap?.call();
          },
        ),
        _CtrlBtn(
          icon: Icons.flip_camera_ios_rounded,
          label: isFrontCamera ? 'Cam sau' : 'Cam trước',
          isActive: false,
          activeColor: Colors.white,
          onTap: () {
            HapticFeedback.selectionClick();
            onSwitchCameraTap?.call();
          },
        ),
        _CtrlBtn(
          icon: isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: isSpeakerOn ? 'Loa ngoài' : 'Tai nghe',
          isActive: isSpeakerOn,
          activeColor: const Color(0xFF5C6BC0),
          onTap: () {
            HapticFeedback.lightImpact();
            onSpeakerTap();
          },
        ),
        _EndCallBtn(onTap: onEndCall),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════
// CONTROL BUTTON
// ══════════════════════════════════════════════════════
class _CtrlBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_CtrlBtn> createState() => _CtrlBtnState();
}

class _CtrlBtnState extends State<_CtrlBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 80),
        reverseDuration: const Duration(milliseconds: 180));
    _scale = Tween<double>(begin: 1.0, end: 0.85)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.activeColor.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isActive
                    ? widget.activeColor.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.14),
                width: 1.2,
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: widget.activeColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: widget.isActive ? widget.activeColor : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.isActive
                  ? widget.activeColor.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.65),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// END CALL BUTTON
// ══════════════════════════════════════════════════════
class _EndCallBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _EndCallBtn({required this.onTap});

  @override
  State<_EndCallBtn> createState() => _EndCallBtnState();
}

class _EndCallBtnState extends State<_EndCallBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 90),
        reverseDuration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 1.0, end: 0.82)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _glow = Tween<double>(begin: 0.5, end: 0.1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.heavyImpact();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 72,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color:
                        const Color(0xFFFF3B30).withValues(alpha: _glow.value),
                    blurRadius: 22,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text('Kết thúc',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════
// KEYPAD DIALOG
// ══════════════════════════════════════════════════════
class CallKeypadDialog extends StatefulWidget {
  final void Function(String digit) onDigit;
  const CallKeypadDialog({super.key, required this.onDigit});

  @override
  State<CallKeypadDialog> createState() => _CallKeypadDialogState();
}

class _CallKeypadDialogState extends State<CallKeypadDialog> {
  String _input = '';

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          decoration: BoxDecoration(
            color: const Color(0xF0101728),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),

            // Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _input.isEmpty ? 'Nhập số' : _input,
                style: TextStyle(
                  color: _input.isEmpty ? Colors.white24 : Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Keys grid
            ..._keys.map((row) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                      children: row
                          .map((k) => Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: _KeyBtn(
                                    digit: k,
                                    onTap: () {
                                      setState(() => _input += k);
                                      widget.onDigit(k);
                                      HapticFeedback.selectionClick();
                                    },
                                  ),
                                ),
                              ))
                          .toList()),
                )),

            // Delete button
            if (_input.isNotEmpty)
              GestureDetector(
                onTap: () => setState(
                    () => _input = _input.substring(0, _input.length - 1)),
                child: Container(
                  width: 56,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.backspace_outlined,
                      color: Colors.white60, size: 20),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _KeyBtn extends StatefulWidget {
  final String digit;
  final VoidCallback onTap;
  const _KeyBtn({required this.digit, required this.onTap});

  @override
  State<_KeyBtn> createState() => _KeyBtnState();
}

class _KeyBtnState extends State<_KeyBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 60),
        reverseDuration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Center(
                child: Text(widget.digit,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600))),
          ),
        ),
      );
}
