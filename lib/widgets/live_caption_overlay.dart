import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/realtime_ai_service.dart';

// ══════════════════════════════════════════════════════
// LIVE CAPTION OVERLAY
// Real-time speech-to-text captions during calls,
// shown as a frosted glass panel with AI security alerts.
// ══════════════════════════════════════════════════════
class LiveCaptionOverlay extends StatefulWidget {
  final String speakerName;
  final bool showSpeakerLabel;
  final int maxLines;
  final double bottomOffset;

  const LiveCaptionOverlay({
    super.key,
    this.speakerName = '',
    this.showSpeakerLabel = true,
    this.maxLines = 3,
    this.bottomOffset = 110,
  });

  @override
  State<LiveCaptionOverlay> createState() => _LiveCaptionOverlayState();
}

class _LiveCaptionOverlayState extends State<LiveCaptionOverlay>
    with TickerProviderStateMixin {
  // Completed lines (finalized captions)
  final List<_CaptionLine> _lines = [];
  // Current partial caption being typed
  String _partial = '';

  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  late final AnimationController _securityBorderCtrl;
  late final Animation<double> _securityBorderAnim;

  StreamSubscription<String>? _capSub;
  StreamSubscription<SecurityEvent>? _secSub;

  Timer? _silenceTimer;
  bool _visible = false;
  SecurityStatus _securityStatus = SecurityStatus.safe;

  static const Duration _silenceTimeout = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _securityBorderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _securityBorderAnim = Tween<double>(begin: 0.3, end: 0.9).animate(
        CurvedAnimation(parent: _securityBorderCtrl, curve: Curves.easeInOut));

    _capSub = RealtimeAIService().captionStream.listen(_onCaption);
    _secSub = RealtimeAIService().securityStream.listen(_onSecurityEvent);
  }

  @override
  void dispose() {
    _capSub?.cancel();
    _secSub?.cancel();
    _silenceTimer?.cancel();
    _entryCtrl.dispose();
    _securityBorderCtrl.dispose();
    super.dispose();
  }

  void _onCaption(String text) {
    if (text.isEmpty) {
      // Empty = end of speech segment
      if (_partial.isNotEmpty) {
        _finalizeLine(_partial);
        _partial = '';
      }
      _startSilenceTimer();
      return;
    }

    _silenceTimer?.cancel();
    setState(() => _partial = text);

    if (!_visible) {
      _visible = true;
      _entryCtrl.forward();
    }
  }

  void _onSecurityEvent(SecurityEvent event) {
    if (!mounted) return;
    setState(() => _securityStatus = event.status);
  }

  void _finalizeLine(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _lines.add(_CaptionLine(
        text: text.trim(),
        timestamp: DateTime.now(),
        isSpeaker: false, // Detected from remote
      ));
      if (_lines.length > widget.maxLines) _lines.removeAt(0);
      _partial = '';
    });
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () {
      if (mounted) {
        _entryCtrl.reverse().then((_) {
          if (mounted) {
            setState(() {
              _visible = false;
              _partial = '';
            });
          }
        });
      }
    });
  }

  Color _accentColor() {
    switch (_securityStatus) {
      case SecurityStatus.warning:
        return const Color(0xFFFBBF24);
      case SecurityStatus.danger:
        return const Color(0xFFF87171);
      case SecurityStatus.scanning:
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFF34C759);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible && _partial.isEmpty && _lines.isEmpty) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: _CaptionPanel(
          lines: _lines,
          partial: _partial,
          speakerName: widget.speakerName,
          showSpeakerLabel: widget.showSpeakerLabel,
          securityStatus: _securityStatus,
          accentColor: _accentColor(),
          securityBorderAnim: _securityBorderAnim,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// CAPTION PANEL
// ══════════════════════════════════════════════════════
class _CaptionPanel extends StatelessWidget {
  final List<_CaptionLine> lines;
  final String partial;
  final String speakerName;
  final bool showSpeakerLabel;
  final SecurityStatus securityStatus;
  final Color accentColor;
  final Animation<double> securityBorderAnim;

  const _CaptionPanel({
    required this.lines,
    required this.partial,
    required this.speakerName,
    required this.showSpeakerLabel,
    required this.securityStatus,
    required this.accentColor,
    required this.securityBorderAnim,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedBuilder(
          animation: securityBorderAnim,
          builder: (context, child) {
            final borderColor = securityStatus == SecurityStatus.safe
                ? accentColor.withValues(alpha: 0.18)
                : accentColor.withValues(
                    alpha: securityBorderAnim.value * 0.55);

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                  if (securityStatus != SecurityStatus.safe)
                    BoxShadow(
                      color: accentColor.withValues(
                          alpha: securityBorderAnim.value * 0.2),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: child,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row
              Row(children: [
                _CaptionDot(color: accentColor),
                const SizedBox(width: 7),
                Text(
                  showSpeakerLabel && speakerName.isNotEmpty
                      ? speakerName
                      : 'Phụ đề AI',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                _StatusBadge(status: securityStatus, accentColor: accentColor),
              ]),

              const SizedBox(height: 8),

              // Completed lines (faded)
              ...lines.map((line) => _CompletedLine(line: line)),

              // Partial line (current, bright)
              if (partial.isNotEmpty) _PartialLine(text: partial),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SecurityStatus status;
  final Color accentColor;

  const _StatusBadge({required this.status, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final Widget inner;

    switch (status) {
      case SecurityStatus.warning:
        inner = Icon(Icons.warning_amber_rounded, size: 11, color: accentColor);
        break;
      case SecurityStatus.danger:
        inner = Icon(Icons.gpp_bad_rounded, size: 11, color: accentColor);
        break;
      case SecurityStatus.scanning:
        inner = SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        );
        break;
      default:
        inner = Icon(Icons.subtitles_rounded,
            color: Colors.white.withValues(alpha: 0.4), size: 13);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
          horizontal: status == SecurityStatus.safe ? 0 : 5,
          vertical: status == SecurityStatus.safe ? 0 : 3),
      decoration: BoxDecoration(
        color: status == SecurityStatus.safe
            ? Colors.transparent
            : accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: status == SecurityStatus.safe
                ? Colors.transparent
                : accentColor.withValues(alpha: 0.25),
            width: 0.8),
      ),
      child: inner,
    );
  }
}

// ── Animated caption dot ──────────────────────────────
class _CaptionDot extends StatefulWidget {
  final Color color;
  const _CaptionDot({required this.color});

  @override
  State<_CaptionDot> createState() => _CaptionDotState();
}

class _CaptionDotState extends State<_CaptionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.6 + _ctrl.value * 0.4),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _ctrl.value * 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
}

// ── Completed caption line ────────────────────────────
class _CompletedLine extends StatefulWidget {
  final _CaptionLine line;
  const _CompletedLine({required this.line});

  @override
  State<_CompletedLine> createState() => _CompletedLineState();
}

class _CompletedLineState extends State<_CompletedLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300))
      ..forward();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            widget.line.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

// ── Partial (current) line ────────────────────────────
class _PartialLine extends StatefulWidget {
  final String text;
  const _PartialLine({required this.text});

  @override
  State<_PartialLine> createState() => _PartialLineState();
}

class _PartialLineState extends State<_PartialLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorCtrl;
  late final Animation<double> _cursor;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _cursor = CurvedAnimation(parent: _cursorCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
                letterSpacing: 0.15,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Blinking cursor
          AnimatedBuilder(
            animation: _cursor,
            builder: (_, __) => Opacity(
              opacity: _cursor.value,
              child: Container(
                width: 2,
                height: 16,
                margin: const EdgeInsets.only(left: 2, top: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════
// EXPANDED CAPTION VIEW  (scrollable, for long calls)
// ══════════════════════════════════════════════════════
class FullCaptionView extends StatefulWidget {
  const FullCaptionView({super.key});

  @override
  State<FullCaptionView> createState() => _FullCaptionViewState();
}

class _FullCaptionViewState extends State<FullCaptionView> {
  final List<String> _allLines = [];
  String _partial = '';
  final _scrollCtrl = ScrollController();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = RealtimeAIService().captionStream.listen((text) {
      if (text.isEmpty) {
        if (_partial.isNotEmpty) {
          setState(() {
            _allLines.add(_partial);
            _partial = '';
          });
          _scrollToBottom();
        }
      } else {
        setState(() => _partial = text);
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                const Icon(Icons.subtitles_rounded,
                    color: Color(0xFF34C759), size: 16),
                const SizedBox(width: 8),
                const Text('Phụ đề AI (Toàn bộ)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_allLines.length} dòng',
                    style:
                        const TextStyle(color: Colors.white30, fontSize: 11)),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),

            // Caption list
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: _allLines.length + (_partial.isNotEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i < _allLines.length) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_allLines[i],
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              height: 1.4)),
                    );
                  }
                  // Partial line
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(_partial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w500)),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// MODEL
// ══════════════════════════════════════════════════════
class _CaptionLine {
  final String text;
  final DateTime timestamp;
  final bool isSpeaker;

  const _CaptionLine({
    required this.text,
    required this.timestamp,
    required this.isSpeaker,
  });
}
