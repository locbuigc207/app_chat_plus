import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_chat.dart';
import '../models/smart_reply_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS & MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum CardType { text, sticker }

class SwipeReply {
  final String text;
  final CardType cardType;
  final List<Color> gradient;
  final String? emoji;
  final String? stickerId;

  const SwipeReply({
    required this.text,
    this.cardType = CardType.text,
    required this.gradient,
    this.emoji,
    this.stickerId,
  });

  bool get isSticker => cardType == CardType.sticker;

  factory SwipeReply.fromString(String text, int index) => SwipeReply(
        text: text,
        cardType: CardType.text,
        gradient: _kCardGradients[index % _kCardGradients.length],
        emoji: _kCardEmojis[index % _kCardEmojis.length],
      );

  factory SwipeReply.fromSticker(String stickerId) => SwipeReply(
        text: stickerId,
        cardType: CardType.sticker,
        stickerId: stickerId,
        gradient: [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
      );

  factory SwipeReply.fromSmartReplyItem(SmartReplyItem item, int index) {
    if (item.isSticker) {
      return SwipeReply.fromSticker(item.stickerId ?? item.text);
    }
    return SwipeReply(
      text: item.text,
      cardType: CardType.text,
      gradient: _kCardGradients[index % _kCardGradients.length],
      emoji: _kCardEmojis[index % _kCardEmojis.length],
    );
  }

  /// Payload để gửi
  String get sendPayload => stickerId ?? text;

  /// Message type: 0=text, 2=sticker
  int get messageType => isSticker ? TypeMessage.sticker : TypeMessage.text;
}

const List<List<Color>> _kCardGradients = [
  [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  [Color(0xFF10B981), Color(0xFF0EA5E9)],
  [Color(0xFFF59E0B), Color(0xFFEF4444)],
  [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  [Color(0xFF14B8A6), Color(0xFF3B82F6)],
];

const List<String> _kCardEmojis = ['💬', '✨', '🔥', '👍', '😄'];

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class SwipeReplyCards extends StatefulWidget {
  /// List các text replies (legacy interface)
  final List<String> replies;

  /// List SmartReplyItem đầy đủ (text + sticker) — ưu tiên hơn [replies]
  final List<SmartReplyItem>? richItems;

  /// Sticker cards từ AI (IDs)
  final List<String> stickerCards;

  final Future<void> Function(String payload, int messageType) onSend;
  final VoidCallback onCancel;
  final String? incomingMessage;

  const SwipeReplyCards({
    super.key,
    required this.replies,
    required this.onSend,
    required this.onCancel,
    this.richItems,
    this.stickerCards = const [],
    this.incomingMessage,
  });

  @override
  State<SwipeReplyCards> createState() => _SwipeReplyCardsState();
}

class _SwipeReplyCardsState extends State<SwipeReplyCards>
    with TickerProviderStateMixin {
  late List<SwipeReply> _cards;
  int _currentIndex = 0;
  bool _isSending = false;

  Offset _dragOffset = Offset.zero;
  double _dragAngle = 0;
  bool _isDragging = false;

  late AnimationController _overlayController;
  late Animation<double> _overlayAnim;
  late AnimationController _entryController;
  late Animation<double> _entryAnim;

  static const double _swipeThreshold = 100.0;
  static const double _maxAngle = 0.15;
  _SwipeFeedback _feedback = _SwipeFeedback.none;

  @override
  void initState() {
    super.initState();
    _buildCards();
    _overlayController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _overlayAnim =
        CurvedAnimation(parent: _overlayController, curve: Curves.easeOut);
    _entryController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _entryAnim =
        CurvedAnimation(parent: _entryController, curve: Curves.elasticOut);
    _entryController.forward();
  }

  void _buildCards() {
    _cards = [];

    // Rich items từ EnhancedSmartReplyResult
    if (widget.richItems != null && widget.richItems!.isNotEmpty) {
      for (int i = 0; i < widget.richItems!.length; i++) {
        _cards.add(SwipeReply.fromSmartReplyItem(widget.richItems![i], i));
      }
    } else {
      // Legacy text replies
      for (int i = 0; i < widget.replies.length; i++) {
        _cards.add(SwipeReply.fromString(widget.replies[i], i));
      }
      // Append sticker cards
      for (final id in widget.stickerCards) {
        _cards.add(SwipeReply.fromSticker(id));
      }
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _isDragging = true;
      _dragOffset += d.delta;
      _dragAngle = (_dragOffset.dx / 300) * _maxAngle;
    });
    _updateOverlay();
  }

  void _onPanEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_dragOffset.dx > _swipeThreshold || vx > 600) {
      _commitSwipe(right: true);
    } else if (_dragOffset.dx < -_swipeThreshold || vx < -600) {
      _commitSwipe(right: false);
    } else {
      _snapBack();
    }
  }

  void _updateOverlay() {
    final progress = (_dragOffset.dx / _swipeThreshold).clamp(-1.0, 1.0);
    _overlayController.value = progress.abs();
    final newFeedback = _dragOffset.dx > 0
        ? _SwipeFeedback.send
        : _dragOffset.dx < 0
            ? _SwipeFeedback.skip
            : _SwipeFeedback.none;
    if (newFeedback != _feedback) setState(() => _feedback = newFeedback);
  }

  Future<void> _commitSwipe({required bool right}) async {
    HapticFeedback.mediumImpact();
    final targetX = right ? 500.0 : -500.0;
    await _animateTo(Offset(targetX, _dragOffset.dy),
        right ? _maxAngle * 2 : -_maxAngle * 2);

    if (right && !_isSending) {
      setState(() => _isSending = true);
      await widget.onSend(
          _cards[_currentIndex].sendPayload, _cards[_currentIndex].messageType);
      if (!mounted) return;
      setState(() => _isSending = false);
      widget.onCancel();
      return;
    }
    _advance();
  }

  Future<void> _animateTo(Offset target, double angle) async {
    final from = _dragOffset;
    final fromAngle = _dragAngle;
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    ctrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _dragOffset = Offset.lerp(from, target, anim.value)!;
        _dragAngle = _lerpDouble(fromAngle, angle, anim.value);
      });
    });
    await ctrl.forward();
    ctrl.dispose();
  }

  void _snapBack() {
    final from = _dragOffset;
    final fromAngle = _dragAngle;
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.elasticOut);
    ctrl.addListener(() {
      if (!mounted) return;
      setState(() {
        _dragOffset = Offset.lerp(from, Offset.zero, anim.value)!;
        _dragAngle = _lerpDouble(fromAngle, 0, anim.value);
      });
    });
    ctrl.forward().then((_) {
      ctrl.dispose();
      if (mounted) {
        setState(() {
          _isDragging = false;
          _feedback = _SwipeFeedback.none;
          _overlayController.value = 0;
        });
      }
    });
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      _dragOffset = Offset.zero;
      _dragAngle = 0;
      _isDragging = false;
      _feedback = _SwipeFeedback.none;
      _overlayController.value = 0;
      _currentIndex++;
      if (_currentIndex >= _cards.length) {
        widget.onCancel();
      } else {
        _entryController.forward(from: 0);
      }
    });
  }

  void _tapSkip() {
    setState(() {
      _dragOffset = const Offset(-10, 0);
      _feedback = _SwipeFeedback.skip;
    });
    Future.delayed(
        const Duration(milliseconds: 80), () => _commitSwipe(right: false));
  }

  void _tapSend() {
    setState(() {
      _dragOffset = const Offset(10, 0);
      _feedback = _SwipeFeedback.send;
    });
    Future.delayed(
        const Duration(milliseconds: 80), () => _commitSwipe(right: true));
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= _cards.length) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F14),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 40,
              offset: const Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            if (widget.incomingMessage != null) _buildIncomingContext(),
            _buildCardStack(),
            _buildActionRow(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader() {
    final totalCards = _cards.length;
    final textCount = _cards.where((c) => !c.isSticker).length;
    final stickerCount = _cards.where((c) => c.isSticker).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zero-Type Reply',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3),
                ),
                Text(
                  stickerCount > 0
                      ? '$textCount văn bản · $stickerCount sticker  •  Vuốt PHẢI → Gửi'
                      : 'Vuốt PHẢI → Gửi  •  Vuốt TRÁI → Bỏ',
                  style:
                      const TextStyle(color: Color(0xFF6B7280), fontSize: 10.5),
                ),
              ],
            ),
          ),
          _buildProgressDots(),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: widget.onCancel,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF6B7280), size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressDots() {
    return Row(
      children: List.generate(_cards.length, (i) {
        final active = i == _currentIndex;
        final isSticker = _cards[i].isSticker;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? (isSticker
                    ? const Color(0xFF10B981)
                    : const Color(0xFF6366F1))
                : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildIncomingContext() => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.incomingMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Widget _buildCardStack() {
    final remaining = _cards.length - _currentIndex;
    final stackCount = math.min(remaining, 3);

    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (int i = stackCount - 1; i >= 1; i--)
            _buildBackCard(i, _cards[(_currentIndex + i) % _cards.length]),
          _buildTopCard(_cards[_currentIndex]),
        ],
      ),
    );
  }

  Widget _buildBackCard(int depth, SwipeReply reply) {
    final scale = 1.0 - depth * 0.06;
    final translateY = depth * 10.0;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..translate(0.0, translateY)
        ..scale(scale),
      child: _CardFace(reply: reply, opacity: 0.5 - depth * 0.1),
    );
  }

  Widget _buildTopCard(SwipeReply reply) => GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: AnimatedBuilder(
          animation: _entryAnim,
          builder: (_, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(_dragOffset.dx, _dragOffset.dy)
              ..rotateZ(_dragAngle),
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _CardFace(reply: reply, opacity: 1),
              if (_feedback == _SwipeFeedback.send)
                AnimatedBuilder(
                  animation: _overlayAnim,
                  builder: (_, __) => _CardOverlay(
                    label: reply.isSticker ? 'SEND 🎉' : 'GỬI',
                    icon: Icons.send_rounded,
                    color: const Color(0xFF10B981),
                    opacity: _overlayAnim.value,
                  ),
                ),
              if (_feedback == _SwipeFeedback.skip)
                AnimatedBuilder(
                  animation: _overlayAnim,
                  builder: (_, __) => _CardOverlay(
                    label: 'BỎ QUA',
                    icon: Icons.close_rounded,
                    color: const Color(0xFFEF4444),
                    opacity: _overlayAnim.value,
                    alignRight: false,
                  ),
                ),
              if (_isSending)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _buildActionRow() => Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ActionButton(
              onTap: _tapSkip,
              icon: Icons.close_rounded,
              label: 'Bỏ qua',
              color: const Color(0xFFEF4444),
              backgroundColor: const Color(0xFFEF4444).withOpacity(0.12),
            ),
            Text(
              '${_currentIndex + 1} / ${_cards.length}',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
            _ActionButton(
              onTap: _tapSend,
              icon: _cards[_currentIndex].isSticker
                  ? Icons.emoji_emotions_rounded
                  : Icons.send_rounded,
              label: _cards[_currentIndex].isSticker ? 'Sticker' : 'Gửi',
              color: const Color(0xFF10B981),
              backgroundColor: const Color(0xFF10B981).withOpacity(0.12),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD FACE — renders text OR sticker differently
// ─────────────────────────────────────────────────────────────────────────────

class _CardFace extends StatelessWidget {
  final SwipeReply reply;
  final double opacity;

  const _CardFace({required this.reply, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: reply.isSticker
          ? _buildStickerCard(context)
          : _buildTextCard(context),
    );
  }

  Widget _buildTextCard(BuildContext context) => Container(
        width: MediaQuery.of(context).size.width - 56,
        height: 185,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: reply.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: reply.gradient.last.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (reply.emoji != null)
                      Text(reply.emoji!, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text(
                      reply.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 2))
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Swipe hint arrows
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left_rounded,
                      color: Colors.white.withOpacity(0.2), size: 20),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.2), size: 20),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildStickerCard(BuildContext context) {
    final stickerId = reply.stickerId ?? reply.text;
    return Container(
      width: MediaQuery.of(context).size.width - 56,
      height: 185,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF10B981).withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle glow background
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withOpacity(0.06),
              ),
            ),
          ),
          // Sticker GIF
          Center(
            child: Image.asset(
              StickerCatalog.assetPath(stickerId),
              width: 110,
              height: 110,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.emoji_emotions_outlined,
                size: 60,
                color: Color(0xFF10B981),
              ),
            ),
          ),
          // "Sticker" label top-center
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_emotions_outlined,
                          size: 12, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'Sticker',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Swipe hint
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.15), size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _CardOverlay extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double opacity;
  final bool alignRight;

  const _CardOverlay({
    required this.label,
    required this.icon,
    required this.color,
    required this.opacity,
    this.alignRight = true,
  });

  @override
  Widget build(BuildContext context) => Positioned(
        top: 16,
        left: alignRight ? null : 16,
        right: alignRight ? 16 : null,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: alignRight ? -0.2 : 0.2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 2.5),
                borderRadius: BorderRadius.circular(10),
                color: color.withOpacity(0.12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.0),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.88,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.animateTo(0.88, curve: Curves.easeOut),
        onTapUp: (_) {
          _ctrl.animateTo(1.0, curve: Curves.elasticOut);
          widget.onTap();
        },
        onTapCancel: () => _ctrl.animateTo(1.0, curve: Curves.easeOut),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) =>
              Transform.scale(scale: _ctrl.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: widget.color.withOpacity(0.3), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: widget.color, size: 22),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  style: TextStyle(
                      color: widget.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}

enum _SwipeFeedback { none, send, skip }

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
