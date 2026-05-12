// lib/widgets/enhanced_message_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EnhancedMessageOptionsDialog extends StatelessWidget {
  final bool isOwnMessage;
  final bool isPinned;
  final bool isDeleted;
  final String messageContent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onCopy;
  final VoidCallback onReply;
  final VoidCallback onReminder;
  final VoidCallback onTranslate;

  const EnhancedMessageOptionsDialog({
    super.key,
    required this.isOwnMessage,
    required this.isPinned,
    required this.isDeleted,
    required this.messageContent,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onCopy,
    required this.onReply,
    required this.onReminder,
    required this.onTranslate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 40,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 48,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          if (isOwnMessage && !isDeleted) ...[
            _buildOption(
              icon: Icons.edit_rounded,
              label: 'Chỉnh sửa',
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            _buildOption(
              icon: Icons.delete_rounded,
              label: 'Thu hồi',
              color: const Color(0xFFFF3B30),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1, color: Color(0xFFF2F2F7)),
            ),
          ],

          if (!isDeleted) ...[
            _buildOption(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              label: isPinned ? 'Bỏ ghim' : 'Ghim tin nhắn',
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            _buildOption(
              icon: Icons.copy_rounded,
              label: 'Sao chép',
              onTap: () {
                Navigator.pop(context);
                onCopy();
              },
            ),
            _buildOption(
              icon: Icons.reply_rounded,
              label: 'Trả lời',
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1, color: Color(0xFFF2F2F7)),
            ),
            _buildOption(
              icon: Icons.alarm_add_rounded,
              label: 'Hẹn giờ nhắc nhở',
              onTap: () {
                Navigator.pop(context);
                onReminder();
              },
            ),
            _buildOption(
              icon: Icons.translate_rounded,
              label: 'Dịch',
              onTap: () {
                Navigator.pop(context);
                onTranslate();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      highlightColor: const Color(0xFFF2F2F7),
      splashColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? const Color(0xFF111418),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color ?? const Color(0xFF111418),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
