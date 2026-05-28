import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';

// ─── Message Status ────────────────────────────────────────────────────────
enum MessageStatus { sending, sent, delivered, read, failed }

// ═══════════════════════════════════════════════════════════════════════════
// ADAPTIVE CHAT BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

/// Full-featured chat bubble:
/// • Entry animation (fade + slide)
/// • Gradient (me) / flat (peer) styling
/// • Swipe-right to reply
/// • Long-press context menu
/// • Inline emoji reaction bar
/// • Scam-warning expandable banner
/// • Message status ticks (sending → read)
/// • Peer avatar with online dot
/// • Reply-preview card
/// • "Study Note" context indicator
/// • Voice message row
/// • Link-preview card stub
/// • Full AppMode support (student / work / elder)
class AdaptiveChatBubble extends StatefulWidget {
  final MessageChat message;
  final String currentUserId;
  final String peerId;
  final String conversationId;
  final String contextType;
  final String? peerAvatarUrl;
  final bool isPeerOnline;
  final MessageChat? replyToMessage;
  final MessageStatus status;
  final List<BubbleReaction> reactions;
  final ValueChanged<MessageChat>? onReply;
  final ValueChanged<MessageChat>? onDelete;
  final ValueChanged<MessageChat>? onForward;
  final ValueChanged<MessageChat>? onTapMedia;
  final void Function(String emoji)? onReact;
  final void Function(String emoji)? onRemoveReact;

  const AdaptiveChatBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.peerId,
    required this.conversationId,
    this.contextType = 'default',
    this.peerAvatarUrl,
    this.isPeerOnline = false,
    this.replyToMessage,
    this.status = MessageStatus.sent,
    this.reactions = const [],
    this.onReply,
    this.onDelete,
    this.onForward,
    this.onTapMedia,
    this.onReact,
    this.onRemoveReact,
  });

  @override
  State<AdaptiveChatBubble> createState() => _AdaptiveChatBubbleState();
}

class _AdaptiveChatBubbleState extends State<AdaptiveChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _showReactionBar = false;
  bool _isWarningExpanded = false;

  // Swipe-to-reply
  double _dragOffset = 0;
  bool _replyTriggered = false;

  static final _scannedIds = <String>{};

  bool get _isMe => widget.message.idFrom == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: Offset(_isMe ? 0.08 : -0.08, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

    if (!_isMe &&
        widget.message.scamWarning != true &&
        !_scannedIds.contains(widget.message.timestamp)) {
      _scannedIds.add(widget.message.timestamp);
      _doAiScan();
    }
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _doAiScan() {
    AIBackendService().analyzeDecryptedMessage(
      plainText: widget.message.content,
      conversationId: widget.conversationId,
      messageId: widget.message.timestamp,
      idFrom: widget.peerId,
      idTo: widget.currentUserId,
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppModeProvider>();
    final t = provider.tokens;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Column(
            crossAxisAlignment:
                _isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              _buildRow(context, provider, t),
              if (widget.reactions.isNotEmpty)
                _ReactionRow(
                  reactions: widget.reactions,
                  isMe: _isMe,
                  primaryColor: t.primaryColor,
                  onTap: widget.onReact,
                  fontSize: t.bubbleFontSize - 3,
                ),
              if (_showReactionBar)
                _EmojiPickerBar(
                  isMe: _isMe,
                  onPick: (e) {
                    setState(() => _showReactionBar = false);
                    widget.onReact?.call(e);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext ctx,
    AppModeProvider provider,
    AppModeTokens t,
  ) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: AlwaysStoppedAnimation(_dragOffset),
        builder: (_, child) => Transform.translate(
          offset: Offset(_isMe ? -_dragOffset : _dragOffset, 0),
          child: child,
        ),
        child: Row(
          mainAxisAlignment:
              _isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!_isMe) ...[
              _PeerAvatar(
                url: widget.peerAvatarUrl,
                primaryColor: t.primaryColor,
                radius: _avatarRadius(provider.currentMode),
                isOnline: widget.isPeerOnline,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: GestureDetector(
                onLongPress: () => _showContextMenu(ctx, t, provider),
                child: _buildBubbleContent(ctx, t, provider),
              ),
            ),
            if (_isMe) ...[
              const SizedBox(width: 4),
              _StatusTick(
                status: widget.status,
                color: t.primaryColor,
                size: provider.currentMode == AppMode.elder ? 20 : 14,
              ),
            ],
            // Swipe reply indicator
            if (_dragOffset > 0)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6),
                child: Opacity(
                  opacity: (_dragOffset / 60).clamp(0.0, 1.0),
                  child: Icon(
                    Icons.reply_rounded,
                    color: t.primaryColor,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext ctx,
    AppModeTokens t,
    AppModeProvider provider,
  ) {
    if (widget.message.type == TypeMessage.text) {
      return _TextBubble(
        message: widget.message,
        isMe: _isMe,
        tokens: t,
        contextType: widget.contextType,
        appMode: provider.currentMode,
        replyToMessage: widget.replyToMessage,
        isWarningExpanded: _isWarningExpanded,
        onToggleWarning: () =>
            setState(() => _isWarningExpanded = !_isWarningExpanded),
      );
    }
    if (widget.message.type == TypeMessage.voice) {
      return _VoiceBubble(
        message: widget.message,
        isMe: _isMe,
        tokens: t,
      );
    }
    return _MediaBubble(
      message: widget.message,
      isMe: _isMe,
      tokens: t,
      onTap: () => widget.onTapMedia?.call(widget.message),
    );
  }

  // ─── Swipe-to-Reply ──────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    // Only swipe in the "outward" direction per side
    final delta = _isMe ? -d.delta.dx : d.delta.dx;
    if (delta < 0 && _dragOffset == 0) return;
    setState(() {
      _dragOffset =
          (_dragOffset + delta.clamp(0.0, double.infinity)).clamp(0.0, 80.0);
    });
    if (_dragOffset >= 60 && !_replyTriggered) {
      _replyTriggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_replyTriggered) {
      widget.onReply?.call(widget.message);
    }
    _replyTriggered = false;
    setState(() => _dragOffset = 0);
  }

  // ─── Context Menu ────────────────────────────────────────────────────────

  void _showContextMenu(
    BuildContext ctx,
    AppModeTokens t,
    AppModeProvider provider,
  ) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextMenu(
        isMe: _isMe,
        tokens: t,
        appMode: provider.currentMode,
        onCopy: () {
          Clipboard.setData(ClipboardData(text: widget.message.content));
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: const Text('Đã sao chép tin nhắn'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        onReply: () => widget.onReply?.call(widget.message),
        onReact: () => setState(() => _showReactionBar = !_showReactionBar),
        onForward: widget.onForward != null
            ? () => widget.onForward!.call(widget.message)
            : null,
        onDelete: _isMe ? () => widget.onDelete?.call(widget.message) : null,
      ),
    );
  }

  double _avatarRadius(AppMode mode) => switch (mode) {
        AppMode.elder => 20,
        AppMode.work => 14,
        AppMode.student => 16,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// TEXT BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

class _TextBubble extends StatelessWidget {
  final MessageChat message;
  final bool isMe;
  final AppModeTokens tokens;
  final String contextType;
  final AppMode appMode;
  final MessageChat? replyToMessage;
  final bool isWarningExpanded;
  final VoidCallback onToggleWarning;

  const _TextBubble({
    required this.message,
    required this.isMe,
    required this.tokens,
    required this.contextType,
    required this.appMode,
    this.replyToMessage,
    required this.isWarningExpanded,
    required this.onToggleWarning,
  });

  @override
  Widget build(BuildContext context) {
    final isScam = message.scamWarning == true;
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
        minWidth: 56,
      ),
      decoration: BoxDecoration(
        gradient: isMe && !isScam
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tokens.myBubbleGradientStart,
                  tokens.myBubbleGradientEnd,
                ],
              )
            : null,
        color: isScam
            ? const Color(0xFFFFF3E0)
            : (!isMe ? tokens.peerBubbleColor : null),
        borderRadius: _radius(),
        boxShadow: tokens.bubbleShadow,
        border: isScam
            ? Border.all(color: const Color(0xFFFFA726), width: 1.2)
            : null,
      ),
      child: ClipRRect(
        borderRadius: _radius(),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyToMessage != null)
              _ReplyPreview(replyTo: replyToMessage!, isMe: isMe),
            Padding(
              padding: EdgeInsets.all(tokens.bubblePadding),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (contextType == 'study' && appMode == AppMode.student)
                    _StudyIndicator(isMe: isMe),
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: isScam
                          ? const Color(0xFF7B3F00)
                          : (isMe
                              ? tokens.myBubbleTextColor
                              : tokens.peerBubbleTextColor),
                      fontSize: tokens.bubbleFontSize,
                      fontWeight: tokens.bubbleFontWeight,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: tokens.bubbleFontSize - 4.5,
                      color: isMe ? Colors.white54 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            if (isScam)
              _ScamWarningBanner(
                isExpanded: isWarningExpanded,
                onToggle: onToggleWarning,
              ),
          ],
        ),
      ),
    );
  }

  BorderRadius _radius() {
    final r = tokens.bubbleRadius;
    return isMe
        ? BorderRadius.only(
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            bottomRight: Radius.circular(r * 0.25),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(r * 0.25),
            topRight: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            bottomRight: Radius.circular(r),
          );
  }

  String _formatTime(String ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(int.parse(ts));
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VOICE BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

class _VoiceBubble extends StatefulWidget {
  final MessageChat message;
  final bool isMe;
  final AppModeTokens tokens;

  const _VoiceBubble({
    required this.message,
    required this.isMe,
    required this.tokens,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.isMe ? Colors.white70 : widget.tokens.primaryColor;
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: widget.isMe
            ? LinearGradient(colors: [
                widget.tokens.myBubbleGradientStart,
                widget.tokens.myBubbleGradientEnd
              ])
            : null,
        color: widget.isMe ? null : widget.tokens.peerBubbleColor,
        borderRadius: BorderRadius.circular(widget.tokens.bubbleRadius),
        boxShadow: widget.tokens.bubbleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _playing = !_playing),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: accent,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WaveformBar(color: accent, playing: _playing),
                const SizedBox(height: 4),
                Text(
                  '0:12',
                  style: TextStyle(
                    color: accent.withOpacity(0.7),
                    fontSize: 11,
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

class _WaveformBar extends StatelessWidget {
  final Color color;
  final bool playing;
  static const _heights = [
    0.4,
    0.7,
    1.0,
    0.6,
    0.9,
    0.5,
    0.8,
    0.4,
    0.6,
    1.0,
    0.7,
    0.5,
    0.9,
    0.6,
    0.4
  ];

  const _WaveformBar({required this.color, required this.playing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: List.generate(_heights.length, (i) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: FractionallySizedBox(
                heightFactor: _heights[i],
                child: AnimatedContainer(
                  duration:
                      Duration(milliseconds: playing ? 400 + i * 60 : 200),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: color.withOpacity(
                        playing ? 0.8 + (_heights[i] * 0.2) : 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MEDIA BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

class _MediaBubble extends StatelessWidget {
  final MessageChat message;
  final bool isMe;
  final AppModeTokens tokens;
  final VoidCallback? onTap;

  const _MediaBubble({
    required this.message,
    required this.isMe,
    required this.tokens,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
        decoration: BoxDecoration(
          color: isMe ? tokens.myBubbleGradientStart : tokens.peerBubbleColor,
          borderRadius: BorderRadius.circular(tokens.bubbleRadius),
          boxShadow: tokens.bubbleShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: message.type == TypeMessage.image
            ? _ImagePreview(url: message.content)
            : _FileTile(
                content: message.content,
                textColor: isMe
                    ? tokens.myBubbleTextColor
                    : tokens.peerBubbleTextColor,
                fontSize: tokens.bubbleFontSize,
              ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String url;
  const _ImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'img_$url',
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        loadingBuilder: (_, child, prog) => prog == null
            ? child
            : Container(
                height: 200,
                color: Colors.grey.shade100,
                child: Center(
                  child: CircularProgressIndicator(
                    value: prog.expectedTotalBytes != null
                        ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                        : null,
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 80,
          child: Center(
              child: Icon(Icons.broken_image_rounded,
                  size: 32, color: Colors.grey)),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final String content;
  final Color textColor;
  final double fontSize;
  const _FileTile(
      {required this.content, required this.textColor, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_rounded, color: textColor, size: 28),
          const SizedBox(width: 8),
          Flexible(
            child: Text(content,
                style: TextStyle(color: textColor, fontSize: fontSize),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPLY PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

class _ReplyPreview extends StatelessWidget {
  final MessageChat replyTo;
  final bool isMe;
  const _ReplyPreview({required this.replyTo, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white60 : Colors.blueAccent,
            width: 3,
          ),
        ),
      ),
      child: Text(
        replyTo.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: isMe ? Colors.white70 : Colors.black54,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STUDY INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

class _StudyIndicator extends StatelessWidget {
  final bool isMe;
  const _StudyIndicator({required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded,
              size: 11, color: isMe ? Colors.white70 : Colors.black45),
          const SizedBox(width: 4),
          Text(
            'Study Note',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isMe ? Colors.white70 : Colors.black45,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCAM WARNING BANNER
// ═══════════════════════════════════════════════════════════════════════════

class _ScamWarningBanner extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;
  const _ScamWarningBanner({required this.isExpanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xFFFFF8E1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: Color(0xFFF57C00)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Tin nhắn có dấu hiệu đáng ngờ',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B3F00)),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 15,
                  color: const Color(0xFF7B3F00),
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 6),
              const Text(
                'Hệ thống AI phát hiện tin nhắn này có thể là lừa đảo hoặc spam. '
                'Không chia sẻ thông tin cá nhân hay chuyển tiền.',
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF7B3F00), height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STATUS TICK
// ═══════════════════════════════════════════════════════════════════════════

class _StatusTick extends StatelessWidget {
  final MessageStatus status;
  final Color color;
  final double size;
  const _StatusTick(
      {required this.status, required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: color.withOpacity(0.5)),
        );
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: size, color: Colors.grey);
      case MessageStatus.failed:
        return Icon(Icons.error_outline_rounded, size: size, color: Colors.red);
      case MessageStatus.delivered:
        return _DoubleCheck(size: size, color: Colors.grey);
      case MessageStatus.read:
        return _DoubleCheck(size: size, color: color);
    }
  }
}

class _DoubleCheck extends StatelessWidget {
  final double size;
  final Color color;
  const _DoubleCheck({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.5,
      height: size,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Positioned(
            left: 0,
            child: Icon(Icons.check_rounded, size: size, color: color),
          ),
          Icon(Icons.check_rounded, size: size, color: color),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PEER AVATAR
// ═══════════════════════════════════════════════════════════════════════════

class _PeerAvatar extends StatelessWidget {
  final String? url;
  final Color primaryColor;
  final double radius;
  final bool isOnline;
  const _PeerAvatar(
      {this.url,
      required this.primaryColor,
      required this.radius,
      this.isOnline = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: primaryColor.withOpacity(0.15),
          backgroundImage:
              (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
          child: (url == null || url!.isEmpty)
              ? Icon(Icons.person_rounded,
                  size: radius, color: primaryColor.withOpacity(0.7))
              : null,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REACTION ROW
// ═══════════════════════════════════════════════════════════════════════════

class _ReactionRow extends StatelessWidget {
  final List<BubbleReaction> reactions;
  final bool isMe;
  final Color primaryColor;
  final void Function(String)? onTap;
  final double fontSize;

  const _ReactionRow({
    required this.reactions,
    required this.isMe,
    required this.primaryColor,
    this.onTap,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        left: isMe ? 0 : 44,
        right: isMe ? 18 : 0,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: reactions.map((r) {
          return GestureDetector(
            onTap: () => onTap?.call(r.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Text(
                '${r.emoji} ${r.count}',
                style: TextStyle(fontSize: fontSize + 1, height: 1.2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMOJI PICKER BAR
// ═══════════════════════════════════════════════════════════════════════════

class _EmojiPickerBar extends StatelessWidget {
  final bool isMe;
  final void Function(String) onPick;
  static const _emojis = ['❤️', '😂', '👍', '😮', '😢', '🙏', '🔥', '👏'];

  const _EmojiPickerBar({required this.isMe, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(top: 4, left: isMe ? 0 : 44, right: isMe ? 18 : 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _emojis
              .map((e) => GestureDetector(
                    onTap: () => onPick(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT MENU (Bottom Sheet)
// ═══════════════════════════════════════════════════════════════════════════

class _ContextMenu extends StatelessWidget {
  final bool isMe;
  final AppModeTokens tokens;
  final AppMode appMode;
  final VoidCallback onCopy;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  const _ContextMenu({
    required this.isMe,
    required this.tokens,
    required this.appMode,
    required this.onCopy,
    required this.onReply,
    required this.onReact,
    this.onForward,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = appMode == AppMode.elder
        ? 26.0
        : (appMode == AppMode.work ? 20.0 : 22.0);
    final fontSize = appMode == AppMode.elder
        ? 17.0
        : (appMode == AppMode.work ? 14.0 : 15.0);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _Item(
            icon: Icons.copy_rounded,
            label: 'Sao chép',
            iconSize: iconSize,
            fontSize: fontSize,
            color: tokens.primaryColor,
            onTap: () {
              Navigator.pop(context);
              onCopy();
            },
          ),
          const _Div(),
          _Item(
            icon: Icons.reply_rounded,
            label: 'Trả lời',
            iconSize: iconSize,
            fontSize: fontSize,
            color: tokens.primaryColor,
            onTap: () {
              Navigator.pop(context);
              onReply();
            },
          ),
          const _Div(),
          _Item(
            icon: Icons.add_reaction_outlined,
            label: 'Biểu cảm',
            iconSize: iconSize,
            fontSize: fontSize,
            color: tokens.primaryColor,
            onTap: () {
              Navigator.pop(context);
              onReact();
            },
          ),
          if (onForward != null) ...[
            const _Div(),
            _Item(
              icon: Icons.forward_rounded,
              label: 'Chuyển tiếp',
              iconSize: iconSize,
              fontSize: fontSize,
              color: tokens.primaryColor,
              onTap: () {
                Navigator.pop(context);
                onForward!();
              },
            ),
          ],
          if (onDelete != null) ...[
            const _Div(),
            _Item(
              icon: Icons.delete_outline_rounded,
              label: 'Xóa tin nhắn',
              iconSize: iconSize,
              fontSize: fontSize,
              color: Colors.red.shade400,
              onTap: () {
                Navigator.pop(context);
                onDelete!();
              },
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final double iconSize;
  final double fontSize;
  final Color color;
  final VoidCallback onTap;
  const _Item({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.fontSize,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: iconSize, color: color),
            const SizedBox(width: 14),
            Text(label,
                style:
                    TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) => Divider(
      height: 0,
      thickness: 0.5,
      indent: 20,
      endIndent: 20,
      color: Colors.black12);
}
