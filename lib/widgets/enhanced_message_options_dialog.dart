// lib/widgets/enhanced_message_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (isOwnMessage && !isDeleted) ...[
            _buildOption(
              icon: Icons.edit,
              label: 'Edit Message',
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            _buildOption(
              icon: Icons.delete,
              label: 'Delete Message',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            Divider(height: 1),
          ],

          if (!isDeleted) ...[
            _buildOption(
              icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: isPinned ? 'Unpin Message' : 'Pin Message',
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            _buildOption(
              icon: Icons.copy,
              label: 'Copy Text',
              onTap: () {
                Navigator.pop(context);
                onCopy();
              },
            ),
            _buildOption(
              icon: Icons.reply,
              label: 'Reply',
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            Divider(height: 1),
            _buildOption(
              icon: Icons.alarm_add,
              label: 'Set Reminder',
              onTap: () {
                Navigator.pop(context);
                onReminder();
              },
            ),
            _buildOption(
              icon: Icons.translate,
              label: 'Translate',
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
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color ?? ColorConstants.primaryColor, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color ?? ColorConstants.primaryColor,
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
