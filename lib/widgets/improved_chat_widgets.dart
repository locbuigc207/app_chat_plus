import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImprovedMessageBubble
// ─────────────────────────────────────────────────────────────────────────────

class ImprovedMessageBubble extends StatefulWidget {
  final String content;
  final bool isMe;
  final String timestamp;
  final bool isRead;
  final bool isDeleted;
  final bool isPinned;
  final bool isDark;
  final String? editedAt;
  final String? replyToContent;
  final String? replyToSender;
  final Widget? reactions;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSwipeReply;

  const ImprovedMessageBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.timestamp,
    required this.isDark,
    this.isRead = false,
    this.isDeleted = false,
    this.isPinned = false,
    this.editedAt,
    this.replyToContent,
    this.replyToSender,
    this.reactions,
    this.onLongPress,
    this.onDoubleTap,
    this.onSwipeReply,
  });

  @override
  State<ImprovedMessageBubble> createState() => _ImprovedMessageBubbleState();
}

class _ImprovedMessageBubbleState extends State<ImprovedMessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late Animation<double> _entryScale;
  late Animation<double> _entryFade;

  double _dragOffset = 0;
  bool _replyTriggered = false;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _entryScale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack));
    _entryFade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.onSwipeReply == null) return;
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(-60.0, 60.0);
    });
    if (!_replyTriggered &&
        ((widget.isMe && _dragOffset < -48) ||
            (!widget.isMe && _dragOffset > 48))) {
      _replyTriggered = true;
      HapticFeedback.mediumImpact();
      widget.onSwipeReply?.call();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    setState(() {
      _dragOffset = 0;
      _replyTriggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entryFade,
      child: ScaleTransition(
        scale: _entryScale,
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          child: AnimatedSlide(
            offset: Offset(_dragOffset / 300, 0),
            duration: Duration.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
              child: Align(
                alignment:
                    widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.74,
                  ),
                  child: Column(
                    crossAxisAlignment: widget.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      // Swipe reply icon
                      if (_dragOffset.abs() > 12)
                        _SwipeReplyHint(
                          isMe: widget.isMe,
                          progress: _dragOffset.abs() / 60,
                        ),
                      GestureDetector(
                        onLongPress: widget.onLongPress,
                        onDoubleTap: widget.onDoubleTap,
                        child: _BubbleBody(
                          content: widget.content,
                          isMe: widget.isMe,
                          isDeleted: widget.isDeleted,
                          isDark: widget.isDark,
                          isPinned: widget.isPinned,
                          editedAt: widget.editedAt,
                          timestamp: widget.timestamp,
                          isRead: widget.isRead,
                          replyToContent: widget.replyToContent,
                          replyToSender: widget.replyToSender,
                        ),
                      ),
                      if (widget.reactions != null) ...[
                        const SizedBox(height: 4),
                        widget.reactions!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeReplyHint extends StatelessWidget {
  final bool isMe;
  final double progress;

  const _SwipeReplyHint({required this.isMe, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ColorConstants.primaryColor.withOpacity(0.15),
          ),
          child: Icon(Icons.reply_rounded,
              size: 18, color: ColorConstants.primaryColor),
        ),
      ),
    );
  }
}

class _BubbleBody extends StatelessWidget {
  final String content;
  final bool isMe;
  final bool isDeleted;
  final bool isDark;
  final bool isPinned;
  final String? editedAt;
  final String timestamp;
  final bool isRead;
  final String? replyToContent;
  final String? replyToSender;

  const _BubbleBody({
    required this.content,
    required this.isMe,
    required this.isDeleted,
    required this.isDark,
    required this.isPinned,
    required this.timestamp,
    required this.isRead,
    this.editedAt,
    this.replyToContent,
    this.replyToSender,
  });

  Color get _bubbleBg {
    if (isMe) {
      return isDark ? const Color(0xFF1A6EC7) : ColorConstants.primaryColor;
    }
    return isDark ? const Color(0xFF252A3D) : Colors.white;
  }

  Color get _textColor {
    if (isMe) return Colors.white;
    return isDark ? const Color(0xFFF0F2F8) : const Color(0xFF1A1D2E);
  }

  /// Render text với các URL được highlight và bấm được.
  Widget _buildRichText(String text, Color baseColor) {
    final RegExp urlExp = RegExp(
      r'(?:(?:https?|ftp):\/\/|www\.)'
      r'[\w\-]+(\.[\w\-]+)+'
      r"(?:[\/\w\-._~:/?#\[\]@!$&'()*+,;=%]*)?", // Dùng ngoặc kép r"..." ở đây
      caseSensitive: false,
    );

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in urlExp.allMatches(text)) {
      // Text trước URL
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(color: baseColor, fontSize: 14.5, height: 1.45),
        ));
      }

      // URL span — bấm được
      var rawUrl = text.substring(match.start, match.end);
      final linkUrl = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.lightImpact();
              final uri = Uri.parse(linkUrl);
              try {
                final ok =
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok) {
                  await launchUrl(uri, mode: LaunchMode.inAppWebView);
                }
              } catch (_) {}
            },
            child: Text(
              rawUrl,
              style: TextStyle(
                color: isMe ? const Color(0xFFBDD7FF) : const Color(0xFF4F46E5),
                fontSize: 14.5,
                height: 1.45,
                decoration: TextDecoration.underline,
                decorationColor:
                    isMe ? const Color(0xFFBDD7FF) : const Color(0xFF4F46E5),
              ),
            ),
          ),
        ),
      );

      lastEnd = match.end;
    }

    // Phần text còn lại sau URL cuối
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(color: baseColor, fontSize: 14.5, height: 1.45),
      ));
    }

    // Nếu không có URL nào, render Text thường
    if (spans.isEmpty) {
      return Text(
        text,
        style: TextStyle(color: baseColor, fontSize: 14.5, height: 1.45),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    // URL detection
    final RegExp urlExp =
        RegExp(r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    final matches = urlExp.allMatches(content);
    String? firstUrl = matches.isNotEmpty
        ? content.substring(matches.first.start, matches.first.end)
        : null;
    if (firstUrl != null && !firstUrl.startsWith('http')) {
      firstUrl = 'https://$firstUrl';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: _bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: isMe
                ? ColorConstants.primaryColor.withOpacity(0.2)
                : Colors.black.withOpacity(isDark ? 0.15 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pinned badge
          if (isPinned) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withOpacity(0.15)
                    : ColorConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin_rounded,
                    size: 10,
                    color: isMe ? Colors.white70 : ColorConstants.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Đã ghim',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color:
                          isMe ? Colors.white70 : ColorConstants.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Reply preview
          if (replyToContent != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withOpacity(0.12)
                    : ColorConstants.primaryColor.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: isMe
                        ? Colors.white.withOpacity(0.6)
                        : ColorConstants.primaryColor,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyToSender != null)
                    Text(
                      replyToSender!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color:
                            isMe ? Colors.white70 : ColorConstants.primaryColor,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    replyToContent!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Deleted
          if (isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.do_not_disturb_rounded,
                  size: 13,
                  color: isMe ? Colors.white54 : Colors.grey.shade400,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tin nhắn đã bị xóa',
                  style: TextStyle(
                    color: isMe ? Colors.white54 : Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                    fontSize: 13.5,
                  ),
                ),
              ],
            )
          else ...[
            // Content
            _buildRichText(content, _textColor),
            if (firstUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinkPreviewWidget(url: firstUrl, isMe: isMe),
              ),
          ],

          const SizedBox(height: 5),

          // Footer: time + edited + read receipt
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (editedAt != null) ...[
                Text(
                  'đã sửa · ',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withOpacity(0.5)
                        : Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              Text(
                _formatTime(timestamp),
                style: TextStyle(
                  fontSize: 10.5,
                  color: isMe ? Colors.white60 : Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    key: ValueKey(isRead),
                    isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: isRead
                        ? const Color(0xFF80DEEA)
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// DateSeparator
// ─────────────────────────────────────────────────────────────────────────────

class DateSeparator extends StatelessWidget {
  final String label;
  final bool isDark;

  const DateSeparator({
    super.key,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _gradientLine(isDark, toRight: true),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : ColorConstants.primaryColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : ColorConstants.primaryColor.withOpacity(0.15),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: isDark
                    ? Colors.white.withOpacity(0.5)
                    : ColorConstants.primaryColor.withOpacity(0.7),
              ),
            ),
          ),
          _gradientLine(isDark, toRight: false),
        ],
      ),
    );
  }

  Widget _gradientLine(bool isDark, {required bool toRight}) {
    final baseColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.07);
    return Expanded(
      child: Container(
        height: 1,
        margin:
            EdgeInsets.only(left: toRight ? 0 : 12, right: toRight ? 12 : 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: toRight
                ? [Colors.transparent, baseColor]
                : [baseColor, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImprovedChatInput
// ─────────────────────────────────────────────────────────────────────────────

class ImprovedChatInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDark;
  final bool isMiniChat;
  final bool isBubbleMode;
  final bool isRecording;
  final String recordingDuration;
  final bool showFeatures;
  final MessageChat? replyingTo;
  final Function(String) onTextChanged;
  final VoidCallback onSend;
  final VoidCallback onImagePick;
  final VoidCallback onSticker;
  final VoidCallback onRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onCancelRecord;
  final VoidCallback onToggleFeatures;
  final VoidCallback? onClearReply;
  final VoidCallback? onCamera;
  final VoidCallback? onFile;

  const ImprovedChatInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isDark,
    this.isMiniChat = false,
    this.isBubbleMode = false,
    this.isRecording = false,
    this.recordingDuration = '0:00',
    this.showFeatures = false,
    this.replyingTo,
    required this.onTextChanged,
    required this.onSend,
    required this.onImagePick,
    required this.onSticker,
    required this.onRecord,
    required this.onStopRecord,
    required this.onCancelRecord,
    required this.onToggleFeatures,
    this.onClearReply,
    this.onCamera,
    this.onFile,
  });

  @override
  State<ImprovedChatInput> createState() => _ImprovedChatInputState();
}

class _ImprovedChatInputState extends State<ImprovedChatInput>
    with SingleTickerProviderStateMixin {
  late AnimationController _featureCtrl;
  late Animation<double> _featureAnim;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _featureCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _featureAnim = CurvedAnimation(parent: _featureCtrl, curve: Curves.easeOut);
    widget.controller.addListener(_onTextChange);
  }

  void _onTextChange() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _featureCtrl.dispose();
    super.dispose();
  }

  bool get _showFull => !widget.isMiniChat && !widget.isBubbleMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? ColorConstants.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(
            color: widget.isDark
                ? Colors.white.withOpacity(0.07)
                : Colors.grey.shade200,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.25 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply preview
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: widget.replyingTo != null
                  ? _buildReplyPreview()
                  : const SizedBox.shrink(),
            ),

            // Feature tray
            if (_showFull)
              SizeTransition(
                sizeFactor: _featureAnim,
                child: _buildFeatureTray(),
              ),

            // Recording bar
            if (widget.isRecording) _buildRecordingBar(),

            // Input row
            if (!widget.isRecording)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Toggle features
                    if (_showFull)
                      _InputIconBtn(
                        icon: widget.showFeatures
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.add_rounded,
                        isDark: widget.isDark,
                        onTap: () {
                          widget.onToggleFeatures();
                          if (!widget.showFeatures) {
                            _featureCtrl.forward();
                          } else {
                            _featureCtrl.reverse();
                          }
                        },
                        filled: widget.showFeatures,
                      ),

                    const SizedBox(width: 4),

                    // Text field
                    Expanded(
                      child: _buildTextField(),
                    ),

                    const SizedBox(width: 6),

                    // Send / media
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: child,
                      ),
                      child: _hasText
                          ? _SendButton(
                              key: const ValueKey('send'),
                              onTap: widget.onSend,
                              isDark: widget.isDark,
                            )
                          : _buildMediaButtons(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(minHeight: 46, maxHeight: 130),
      decoration: BoxDecoration(
        color:
            widget.isDark ? ColorConstants.surfaceDark2 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.focusNode.hasFocus
              ? ColorConstants.primaryColor.withOpacity(0.4)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              maxLines: 6,
              minLines: 1,
              onChanged: widget.onTextChanged,
              autofocus: widget.isMiniChat || widget.isBubbleMode,
              style: TextStyle(
                color: widget.isDark ? Colors.white : const Color(0xFF1A1D2E),
                fontSize: 15,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: widget.isMiniChat || widget.isBubbleMode
                    ? 'Nhắn tin...'
                    : 'Nhập tin nhắn...',
                hintStyle: TextStyle(
                  color: widget.isDark ? Colors.white30 : Colors.grey.shade400,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
            ),
          ),
          // Emoji
          if (_showFull)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 10),
              child: GestureDetector(
                onTap: widget.onSticker,
                child: Icon(
                  Icons.emoji_emotions_outlined,
                  size: 22,
                  color: widget.isDark ? Colors.white30 : Colors.grey.shade400,
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: widget.isDark
            ? ColorConstants.primaryColor.withOpacity(0.12)
            : ColorConstants.primaryColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: ColorConstants.primaryColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trả lời',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ColorConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.replyingTo!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClearReply,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.withOpacity(0.15),
              ),
              child: Icon(Icons.close_rounded,
                  size: 14, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTray() {
    final features = [
      (Icons.photo_library_outlined, 'Ảnh', widget.onImagePick),
      (Icons.camera_alt_outlined, 'Camera', widget.onCamera ?? () {}),
      (Icons.insert_drive_file_outlined, 'File', widget.onFile ?? () {}),
      (Icons.gif_box_outlined, 'GIF', widget.onSticker),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: features.map((f) {
          final (icon, label, fn) = f;
          return _FeatureTrayBtn(
              icon: icon, label: label, isDark: widget.isDark, onTap: fn);
        }).toList(),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const PulsingDot(),
          const SizedBox(width: 10),
          Text(
            '🎙  ${widget.recordingDuration}',
            style: const TextStyle(
              color: ColorConstants.accentRed,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: widget.onCancelRecord,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 16, color: ColorConstants.accentRed),
            label: const Text('Huỷ',
                style: TextStyle(
                    color: ColorConstants.accentRed,
                    fontWeight: FontWeight.w500)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          const SizedBox(width: 8),
          _SendButton(onTap: widget.onStopRecord, isDark: widget.isDark),
        ],
      ),
    );
  }

  Widget _buildMediaButtons() {
    return Row(
      key: const ValueKey('media'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showFull) ...[
          _InputIconBtn(
            icon: Icons.image_outlined,
            isDark: widget.isDark,
            onTap: widget.onImagePick,
          ),
          const SizedBox(width: 4),
        ],
        _InputIconBtn(
          icon: Icons.mic_none_rounded,
          isDark: widget.isDark,
          onTap: widget.onRecord,
          filled: true,
        ),
      ],
    );
  }
}

class _FeatureTrayBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _FeatureTrayBtn({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.grey.shade200,
              ),
            ),
            child: Icon(icon, size: 24, color: ColorConstants.primaryColor),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputIconBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final bool filled;
  final Color? iconColor;

  const _InputIconBtn({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.filled = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: filled
              ? ColorConstants.primaryColor.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          size: 23,
          color: iconColor ??
              (isDark ? Colors.white54 : ColorConstants.primaryColor),
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _SendButton({super.key, required this.onTap, required this.isDark});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.9)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
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
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: ColorConstants.primaryGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: ColorConstants.primaryColor.withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatAppBar
// ─────────────────────────────────────────────────────────────────────────────

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String peerName;
  final String peerAvatar;
  final String peerId;
  final bool isDark;
  final VoidCallback? onBackPressed;
  final VoidCallback? onAvatarTap;
  final List<Widget> actions;

  const ChatAppBar({
    super.key,
    required this.peerName,
    required this.peerAvatar,
    required this.peerId,
    required this.isDark,
    this.onBackPressed,
    this.onAvatarTap,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark : Colors.white,
        border: Border(
          bottom: BorderSide(
            color:
                isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade200,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            // Back
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : ColorConstants.primaryColor),
              onPressed: onBackPressed ?? () => Navigator.pop(context),
            ),

            // Avatar
            GestureDetector(
              onTap: onAvatarTap,
              child: _buildAvatar(),
            ),

            const SizedBox(width: 10),

            // Name + status
            Expanded(
              child: GestureDetector(
                onTap: onAvatarTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    _OnlineStatus(userId: peerId, isDark: isDark),
                  ],
                ),
              ),
            ),

            // Actions
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final colorIndex = peerName.isEmpty
        ? 0
        : peerName.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarColor.withOpacity(0.12),
        border: Border.all(color: avatarColor.withOpacity(0.2), width: 1.5),
      ),
      child: ClipOval(
        child: peerAvatar.isNotEmpty
            ? Image.network(
                peerAvatar,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarInitials(avatarColor),
              )
            : _avatarInitials(avatarColor),
      ),
    );
  }

  Widget _avatarInitials(Color color) {
    return Container(
      color: color.withOpacity(0.1),
      child: Center(
        child: Text(
          peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  final String userId;
  final bool isDark;
  const _OnlineStatus({required this.userId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();

    return StreamBuilder<UserPresence>(
      stream: presenceProvider.getUserPresenceStream(userId),
      builder: (_, snap) {
        final isOnline = snap.data?.isOnline ?? false;
        final lastSeen = snap.data?.lastSeen;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Row(
            key: ValueKey(isOnline),
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline
                      ? ColorConstants.accentGreen
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                isOnline
                    ? 'Đang hoạt động'
                    : (lastSeen != null
                        ? _formatLastSeen(lastSeen)
                        : 'Offline'),
                style: TextStyle(
                  fontSize: 12,
                  color: isOnline
                      ? ColorConstants.accentGreen
                      : (isDark ? Colors.white38 : Colors.grey.shade500),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Vừa truy cập';
    if (diff.inMinutes < 60) return 'Truy cập ${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return 'Truy cập ${diff.inHours} giờ trước';
    return 'Truy cập ${diff.inDays} ngày trước';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScrollToBottomButton
// ─────────────────────────────────────────────────────────────────────────────

class ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;
  final int unreadCount;

  const ScrollToBottomButton({
    super.key,
    required this.onTap,
    required this.isDark,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252A3D) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.grey.shade200,
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: ColorConstants.primaryColor,
              size: 24,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: ColorConstants.primaryColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
