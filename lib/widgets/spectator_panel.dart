import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';

// ─── Design tokens ────────────────────────────────────────────────────────
abstract final class _C {
  static const bg       = Color(0xFF0D0F14);
  static const surface  = Color(0xFF141720);
  static const card     = Color(0xFF1A1F2E);
  static const accent   = Color(0xFF4F8EF7);
  static const live     = Color(0xFF00E676);
  static const text1    = Color(0xFFEEF2FF);
  static const text2    = Color(0xFF8B93B0);
  static const divider  = Color(0xFF252A3A);
}

const List<String> _kReactions = ['❤️', '😂', '🔥', '👏', '😮', '👍'];
const int _kChatMaxMessages = 50;

// =========================================================
// SPECTATOR PANEL
// =========================================================

/// Panel khán giả hiển thị ở dưới bàn cờ.
///
/// Tính năng:
/// • Viewer count realtime (stream từ Firestore spectatorIds)
/// • Nút thả reaction → emoji bay lên + sync lên Firestore
/// • Spectator chat compact (expand khi nhấn icon chat)
class SpectatorPanel extends StatefulWidget {
  final int spectatorCount;
  final String matchId;
  final String currentUserId;
  final bool isSpectator;

  const SpectatorPanel({
    super.key,
    required this.spectatorCount,
    required this.matchId,
    required this.currentUserId,
    required this.isSpectator,
  });

  @override
  State<SpectatorPanel> createState() => SpectatorPanelState();
}

class SpectatorPanelState extends State<SpectatorPanel>
    with TickerProviderStateMixin {
  // ── Reaction state ────────────────────────────────────────────────────────
  final List<_FlyingEmoji> _flyingEmojis = [];
  bool _showReactionPicker = false;
  DateTime? _lastReaction;

  // ── Chat state ────────────────────────────────────────────────────────────
  bool _chatExpanded = false;
  final List<_ChatMsg> _chatMessages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  StreamSubscription<QuerySnapshot>? _chatSub;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _chatAnim;
  late final Animation<double> _chatHeight;

  @override
  void initState() {
    super.initState();
    _chatAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _chatHeight = CurvedAnimation(parent: _chatAnim, curve: Curves.easeOutCubic);

    if (widget.matchId.isNotEmpty) {
      _subscribeChatMessages();
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    _chatAnim.dispose();
    super.dispose();
  }

  // ── Firebase: Spectator chat ──────────────────────────────────────────────

  void _subscribeChatMessages() {
    _chatSub = FirebaseFirestore.instance
        .collection(FirestoreConstants.pathGameMatchCollection)
        .doc(widget.matchId)
        .collection(FirestoreConstants.pathSpectatorChatSubCollection)
        .orderBy('sentAt', descending: true)
        .limit(_kChatMaxMessages)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final msgs = snap.docs.map((doc) {
        final d = doc.data();
        return _ChatMsg(
          userId: d['userId'] as String? ?? '',
          text: d['text'] as String? ?? '',
          sentAt: d['sentAt'] as String? ?? '',
        );
      }).toList();
      setState(() => _chatMessages
        ..clear()
        ..addAll(msgs));
    });
  }

  Future<void> _sendChatMessage(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _chatCtrl.clear();

    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGameMatchCollection)
          .doc(widget.matchId)
          .collection(FirestoreConstants.pathSpectatorChatSubCollection)
          .doc(now)
          .set({
        'userId': widget.currentUserId,
        'text': t,
        'sentAt': now,
      });
    } catch (e) {
      debugPrint('[SpectatorPanel] sendChatMessage error: $e');
    }
  }

  // ── Firebase: Reaction sync ───────────────────────────────────────────────

  Future<void> _syncReactionToFirebase(String emoji) async {
    if (widget.matchId.isEmpty) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch.toString();
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGameMatchCollection)
          .doc(widget.matchId)
          .collection(FirestoreConstants.pathGameReactionsSubCollection)
          .doc(now)
          .set({
        'userId': widget.currentUserId,
        'emoji': emoji,
        'sentAt': now,
      });
    } catch (e) {
      debugPrint('[SpectatorPanel] syncReaction error: $e');
    }
  }

  // ── Reaction logic ────────────────────────────────────────────────────────

  void _sendReaction(String emoji) {
    final now = DateTime.now();
    if (_lastReaction != null &&
        now.difference(_lastReaction!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastReaction = now;
    HapticFeedback.lightImpact();

    final id = now.millisecondsSinceEpoch;
    setState(() {
      _flyingEmojis.add(_FlyingEmoji(emoji: emoji, id: id));
      _showReactionPicker = false;
    });

    // Sync lên Firebase không block UI
    _syncReactionToFirebase(emoji);

    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _flyingEmojis.removeWhere((e) => e.id == id));
    });
  }

  // ── Chat toggle ───────────────────────────────────────────────────────────

  void _toggleChat() {
    HapticFeedback.selectionClick();
    setState(() => _chatExpanded = !_chatExpanded);
    if (_chatExpanded) {
      _chatAnim.forward();
      // Scroll to bottom khi mở
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollChatToBottom());
    } else {
      _chatAnim.reverse();
    }
  }

  void _scrollChatToBottom() {
    if (_chatScroll.hasClients) {
      _chatScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Flying emojis (Positioned above panel)
        ..._flyingEmojis.map((fe) => Positioned(
          bottom: _chatExpanded ? 200 : 60,
          right: 20 + (fe.id % 80).toDouble(),
          child: _FlyingEmojiWidget(
            key: ValueKey(fe.id),
            emoji: fe.emoji,
          ),
        )),

        // Reaction picker popup
        if (_showReactionPicker)
          Positioned(
            bottom: _chatExpanded ? 196 : 52,
            right: 12,
            child: _ReactionPicker(
              onPick: _sendReaction,
              onDismiss: () => setState(() => _showReactionPicker = false),
            ),
          ),

        // Main panel
        Container(
          decoration: BoxDecoration(
            color: _C.bg,
            border: Border(top: BorderSide(color: _C.divider, width: 0.8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Chat expanded area
              SizeTransition(
                sizeFactor: _chatHeight,
                axisAlignment: -1,
                child: _SpectatorChat(
                  messages: _chatMessages,
                  scrollController: _chatScroll,
                  currentUserId: widget.currentUserId,
                  controller: _chatCtrl,
                  onSend: _sendChatMessage,
                ),
              ),

              // Control bar
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    // Viewer count
                    _ViewerCount(
                      matchId: widget.matchId,
                      fallbackCount: widget.spectatorCount,
                    ),
                    const Spacer(),
                    // Chat button (chỉ hiện cho spectator)
                    if (widget.isSpectator)
                      _BarBtn(
                        icon: _chatExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.chat_bubble_outline_rounded,
                        label: 'Chat',
                        isActive: _chatExpanded,
                        onTap: _toggleChat,
                      ),
                    const SizedBox(width: 4),
                    // Reaction button
                    _BarBtn(
                      icon: Icons.add_reaction_outlined,
                      label: 'React',
                      isActive: _showReactionPicker,
                      onTap: () => setState(
                            () => _showReactionPicker = !_showReactionPicker,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================
// SPECTATOR CHAT
// =========================================================

class _SpectatorChat extends StatelessWidget {
  final List<_ChatMsg> messages;
  final ScrollController scrollController;
  final String currentUserId;
  final TextEditingController controller;
  final void Function(String) onSend;

  const _SpectatorChat({
    required this.messages,
    required this.scrollController,
    required this.currentUserId,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.divider, width: 0.5)),
      ),
      child: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? const Center(
              child: Text(
                'Chưa có tin nhắn',
                style: TextStyle(color: _C.text2, fontSize: 12),
              ),
            )
                : ListView.builder(
              controller: scrollController,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[i];
                final isMe = msg.userId == currentUserId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe) ...[
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _C.accent.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              msg.userId.isNotEmpty
                                  ? msg.userId[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: _C.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isMe
                                ? _C.accent.withOpacity(0.15)
                                : _C.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            msg.text,
                            style: const TextStyle(
                              color: _C.text1,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Input
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _C.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: _C.text1, fontSize: 12),
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Nhắn cho khán giả...',
                      hintStyle: TextStyle(color: _C.text2, fontSize: 12),
                    ),
                    onSubmitted: onSend,
                  ),
                ),
                GestureDetector(
                  onTap: () => onSend(controller.text),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.send_rounded, color: _C.accent, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Viewer count (realtime) ──────────────────────────────────────────────

class _ViewerCount extends StatelessWidget {
  final String matchId;
  final int fallbackCount;

  const _ViewerCount({
    required this.matchId,
    required this.fallbackCount,
  });

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return _buildChip(fallbackCount);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreConstants.pathGameMatchCollection)
          .doc(matchId)
          .snapshots(),
      builder: (context, snap) {
        int count = fallbackCount;
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>?;
          final ids = data?[FirestoreConstants.spectatorIds] as List?;
          count = ids?.length ?? fallbackCount;
        }
        return _buildChip(count);
      },
    );
  }

  Widget _buildChip(int count) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: count > 0 ? _C.live : _C.text2,
          shape: BoxShape.circle,
          boxShadow: count > 0
              ? [BoxShadow(color: _C.live.withOpacity(0.5), blurRadius: 4)]
              : null,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        '$count đang xem',
        style: const TextStyle(
          color: _C.text2,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

// ─── Bar button ───────────────────────────────────────────────────────────

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BarBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? _C.accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? _C.accent : _C.text2,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? _C.accent : _C.text2,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Reaction picker ──────────────────────────────────────────────────────

class _ReactionPicker extends StatelessWidget {
  final void Function(String) onPick;
  final VoidCallback onDismiss;

  const _ReactionPicker({required this.onPick, required this.onDismiss});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onDismiss,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2438),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _kReactions
            .map((e) => GestureDetector(
          onTap: () => onPick(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(e, style: const TextStyle(fontSize: 22)),
          ),
        ))
            .toList(),
      ),
    ),
  );
}

// ─── Flying emoji ─────────────────────────────────────────────────────────

class _FlyingEmoji {
  final String emoji;
  final int id;
  const _FlyingEmoji({required this.emoji, required this.id});
}

class _FlyingEmojiWidget extends StatefulWidget {
  final String emoji;
  const _FlyingEmojiWidget({super.key, required this.emoji});

  @override
  State<_FlyingEmojiWidget> createState() => _FlyingEmojiWidgetState();
}

class _FlyingEmojiWidgetState extends State<_FlyingEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fly;
  late final Animation<double> _fade;
  late final double _drift;

  @override
  void initState() {
    super.initState();
    _drift = (math.Random().nextDouble() - 0.5) * 30;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _fly = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _fade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Transform.translate(
      offset: Offset(_drift * _fly.value, -_fly.value * 120),
      child: Opacity(
        opacity: _fade.value,
        child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
      ),
    ),
  );
}

// ─── Data classes ─────────────────────────────────────────────────────────

class _ChatMsg {
  final String userId;
  final String text;
  final String sentAt;
  const _ChatMsg({
    required this.userId,
    required this.text,
    required this.sentAt,
  });
}