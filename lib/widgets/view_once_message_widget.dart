// lib/widgets/view_once_message_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

// ==========================================
// ViewOnceMessageWidget
// ==========================================

class ViewOnceMessageWidget extends StatefulWidget {
  final String groupChatId;
  final String messageId;
  final String content;
  final int type;
  final String currentUserId;
  final bool isViewed;
  final ViewOnceProvider provider;

  const ViewOnceMessageWidget({
    super.key,
    required this.groupChatId,
    required this.messageId,
    required this.content,
    required this.type,
    required this.currentUserId,
    required this.isViewed,
    required this.provider,
  });

  @override
  State<ViewOnceMessageWidget> createState() => _ViewOnceMessageWidgetState();
}

class _ViewOnceMessageWidgetState extends State<ViewOnceMessageWidget> {
  bool _isRevealed = false;

  void _revealMessage() async {
    HapticFeedback.heavyImpact(); // Rung mạnh cảnh báo xem 1 lần
    setState(() => _isRevealed = true);

    // Mark as viewed and schedule auto-delete (10 seconds)
    await widget.provider.markAsViewed(
      groupChatId: widget.groupChatId,
      messageId: widget.messageId,
      userId: widget.currentUserId,
    );

    // Message will be auto-deleted by the provider after 10 seconds
  }

  @override
  Widget build(BuildContext context) {
    // Already viewed and not revealed = show "opened" message
    if (widget.isViewed && !_isRevealed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_rounded,
                color: Color(0xFF8E8E93), size: 18),
            SizedBox(width: 8),
            Text(
              'Tin nhắn đã được mở',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontStyle: FontStyle.italic,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Not yet viewed = show "tap to view" button
    if (!_isRevealed) {
      return GestureDetector(
        onTap: _revealMessage,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8A2387), Color(0xFFE94057)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE94057).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_clock_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Nhấn để xem bí mật',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Revealed = show actual message content (will auto-delete after 10s)
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE94057).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: widget.type == TypeMessage.text
          ? Text(
              widget.content,
              style: const TextStyle(
                color: Color(0xFF111418),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            )
          : widget.type == TypeMessage.image
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.content,
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 220,
                      height: 220,
                      color: const Color(0xFFF2F2F7),
                      child: const Icon(Icons.error),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
    );
  }
}

// ==========================================
// SendViewOnceDialog
// ==========================================

class SendViewOnceDialog extends StatefulWidget {
  final Function(String content, int type) onSend;

  const SendViewOnceDialog({
    super.key,
    required this.onSend,
  });

  @override
  State<SendViewOnceDialog> createState() => _SendViewOnceDialogState();
}

class _SendViewOnceDialogState extends State<SendViewOnceDialog> {
  final _textController = TextEditingController();
  bool _isText = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Send View Once Message',
        style: TextStyle(color: ColorConstants.primaryColor),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This message will disappear 10 seconds after being opened',
            style: TextStyle(
              color: ColorConstants.greyColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _isText = true),
                  icon: const Icon(Icons.text_fields),
                  label: const Text('Text'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isText
                        ? ColorConstants.primaryColor
                        : ColorConstants.greyColor2,
                    foregroundColor: _isText ? Colors.white : Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _isText = false),
                  icon: const Icon(Icons.image),
                  label: const Text('Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_isText
                        ? ColorConstants.primaryColor
                        : ColorConstants.greyColor2,
                    foregroundColor: !_isText ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isText)
            TextField(
              controller: _textController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                border: OutlineInputBorder(),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_isText && _textController.text.trim().isNotEmpty) {
              widget.onSend(
                _textController.text.trim(),
                TypeMessage.text,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Send'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
