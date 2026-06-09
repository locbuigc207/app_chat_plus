// lib/widgets/bubble_typing_indicator.dart
import 'dart:async';

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TYPING INDICATOR  —  three-dot bounce animation
// ═══════════════════════════════════════════════════════════════════════════

/// Standalone widget that renders three animated dots.
///
/// Variants
/// ─────────
/// • [BubbleTypingIndicator.chat]   – inside a chat bubble (peer side)
/// • [BubbleTypingIndicator.header] – inside the mini-chat header bar
/// • [BubbleTypingIndicator.list]   – in the conversation list as a subtitle
/// • [BubbleTypingIndicator.pip]    – tiny version on the PiP bubble
class BubbleTypingIndicator extends StatefulWidget {
  final TypingStyle style;
  final Color? color;
  final double dotSize;
  final double spacing;
  final String? peerName; // optional "Alice is typing…" label
  final bool showLabel;

  const BubbleTypingIndicator({
    super.key,
    this.style = TypingStyle.chat,
    this.color,
    this.dotSize = 7,
    this.spacing = 5,
    this.peerName,
    this.showLabel = false,
  });

  // ── Named constructors ────────────────────────────────────────────────

  const BubbleTypingIndicator.chat({super.key, this.peerName})
      : style = TypingStyle.chat,
        color = null,
        dotSize = 7,
        spacing = 5,
        showLabel = false;

  const BubbleTypingIndicator.header({super.key, Color? accent})
      : style = TypingStyle.header,
        color = accent,
        dotSize = 5,
        spacing = 4,
        peerName = null,
        showLabel = false;

  const BubbleTypingIndicator.list({super.key, String? name})
      : style = TypingStyle.list,
        color = null,
        dotSize = 5,
        spacing = 3,
        peerName = name,
        showLabel = true;

  const BubbleTypingIndicator.pip({super.key})
      : style = TypingStyle.pip,
        color = null,
        dotSize = 4,
        spacing = 3,
        peerName = null,
        showLabel = false;

  @override
  State<BubbleTypingIndicator> createState() => _BubbleTypingIndicatorState();
}

enum TypingStyle { chat, header, list, pip }

class _BubbleTypingIndicatorState extends State<BubbleTypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _anims;

  static const _period = Duration(milliseconds: 480);
  static const _stagger = Duration(milliseconds: 140);
  static const _peak = 1.0; // max translateY factor

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        3, (i) => AnimationController(vsync: this, duration: _period));
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0, end: _peak)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();

    _startSequence();
  }

  void _startSequence() async {
    for (var i = 0; i < 3; i++) {
      await Future.delayed(_stagger);
      if (!mounted) return;
      _ctrls[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  // ─── Style properties ─────────────────────────────────────────────────

  Color _dotColor(BuildContext ctx) {
    if (widget.color != null) return widget.color!;
    return switch (widget.style) {
      TypingStyle.chat => Colors.grey.shade500,
      TypingStyle.header => Colors.white.withOpacity(0.8),
      TypingStyle.list => const Color(0xFF2979FF),
      TypingStyle.pip => Colors.white,
    };
  }

  Color _bubbleBg(BuildContext ctx) => switch (widget.style) {
        TypingStyle.chat => Theme.of(ctx).brightness == Brightness.dark
            ? const Color(0xFF1E2233)
            : const Color(0xFFF0F4FF),
        TypingStyle.header => Colors.transparent,
        TypingStyle.list => Colors.transparent,
        TypingStyle.pip => Colors.transparent,
      };

  EdgeInsets get _padding => switch (widget.style) {
        TypingStyle.chat =>
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        TypingStyle.header =>
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        TypingStyle.list => EdgeInsets.zero,
        TypingStyle.pip => EdgeInsets.zero,
      };

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dotColor = _dotColor(context);
    final dots = _DotsRow(
      ctrls: _ctrls,
      anims: _anims,
      size: widget.dotSize,
      spacing: widget.spacing,
      color: dotColor,
    );

    // List style: "… Alice is typing"
    if (widget.style == TypingStyle.list) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dots,
          if (widget.peerName != null || widget.showLabel) ...[
            const SizedBox(width: 6),
            Text(
              widget.peerName != null
                  ? '${widget.peerName} đang nhập…'
                  : 'đang nhập…',
              style: TextStyle(
                  color: dotColor, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      );
    }

    // Chat bubble style
    if (widget.style == TypingStyle.chat) {
      return Semantics(
        label: widget.peerName != null
            ? '${widget.peerName} đang nhập tin nhắn'
            : 'Đang nhập tin nhắn',
        child: Container(
          padding: _padding,
          decoration: BoxDecoration(
            color: _bubbleBg(context),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: dots,
        ),
      );
    }

    // Header / PiP: bare dots
    return Padding(padding: _padding, child: dots);
  }
}

// ─── Dots row ─────────────────────────────────────────────────────────────

class _DotsRow extends StatelessWidget {
  final List<AnimationController> ctrls;
  final List<Animation<double>> anims;
  final double size, spacing;
  final Color color;

  const _DotsRow({
    required this.ctrls,
    required this.anims,
    required this.size,
    required this.spacing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          3,
          (i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                child: AnimatedBuilder(
                  animation: anims[i],
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, -size * 0.7 * anims[i].value),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                            color.withOpacity(0.45), color, anims[i].value)!,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPING STATE MANAGER
// ═══════════════════════════════════════════════════════════════════════════

/// Tracks which users are currently typing in a conversation.
/// Wraps a stream so widgets can reactively show/hide the indicator.
class TypingStateManager {
  static final TypingStateManager _i = TypingStateManager._();
  factory TypingStateManager() => _i;
  TypingStateManager._();

  final _states = <String, Set<String>>{}; // convId → {userId}
  final _ctrls = <String, StreamController<Set<String>>>{};

  // Timers to auto-clear stale typing events
  final _timers = <String, Timer>{}; // "$convId/$userId"

  static const _timeout = Duration(seconds: 4);

  /// Stream of currently-typing user IDs for [conversationId].
  Stream<Set<String>> typingStream(String conversationId) {
    _ctrls.putIfAbsent(
        conversationId, () => StreamController<Set<String>>.broadcast());
    return _ctrls[conversationId]!.stream;
  }

  /// Returns current typing users (synchronous).
  Set<String> typingUsers(String conversationId) =>
      Set.unmodifiable(_states[conversationId] ?? {});

  /// Mark [userId] as typing in [conversationId].
  void startTyping(String conversationId, String userId) {
    _states.putIfAbsent(conversationId, () => {}).add(userId);
    _emit(conversationId);
    _resetTimer(conversationId, userId);
  }

  /// Mark [userId] as stopped typing.
  void stopTyping(String conversationId, String userId) {
    _states[conversationId]?.remove(userId);
    _emit(conversationId);
    _timers['$conversationId/$userId']?.cancel();
  }

  void _resetTimer(String convId, String userId) {
    final key = '$convId/$userId';
    _timers[key]?.cancel();
    _timers[key] = Timer(_timeout, () => stopTyping(convId, userId));
  }

  void _emit(String convId) {
    final ctrl = _ctrls[convId];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(Set.unmodifiable(_states[convId] ?? {}));
    }
  }

  void clearConversation(String conversationId) {
    _states.remove(conversationId);
    _ctrls[conversationId]?.close();
    _ctrls.remove(conversationId);
    for (final key in _timers.keys
        .where((k) => k.startsWith('$conversationId/'))
        .toList()) {
      _timers.remove(key)?.cancel();
    }
  }

  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    for (final c in _ctrls.values) c.close();
    _ctrls.clear();
    _states.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPING ROW WIDGET  —  avatar + animated indicator
// ═══════════════════════════════════════════════════════════════════════════

/// Shows "peer avatar + typing dots" row, auto-appearing/disappearing.
/// Drop into a chat list above the input bar.
class TypingRow extends StatelessWidget {
  final String conversationId;
  final String? peerAvatarUrl;
  final String peerName;

  const TypingRow({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: TypingStateManager().typingStream(conversationId),
      builder: (ctx, snap) {
        final typing = snap.data ?? {};
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                      .animate(anim),
              child: child,
            ),
          ),
          child: typing.isNotEmpty
              ? Padding(
                  key: const ValueKey('typing'),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 13,
                        backgroundImage: peerAvatarUrl != null
                            ? NetworkImage(peerAvatarUrl!)
                            : null,
                        backgroundColor:
                            const Color(0xFF2979FF).withOpacity(0.15),
                        child: peerAvatarUrl == null
                            ? Text(
                                peerName.isNotEmpty
                                    ? peerName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF2979FF)))
                            : null,
                      ),
                      const SizedBox(width: 6),
                      const BubbleTypingIndicator.chat(),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('idle')),
        );
      },
    );
  }
}
