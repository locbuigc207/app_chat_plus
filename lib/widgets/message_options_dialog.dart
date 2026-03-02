import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class MessageOptionsDialog extends StatelessWidget {
  final bool isOwnMessage;
  final bool isPinned;
  final bool isDeleted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onCopy;
  final VoidCallback onReply;

  const MessageOptionsDialog({
    super.key,
    required this.isOwnMessage,
    required this.isPinned,
    required this.isDeleted,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
    required this.onCopy,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOwnMessage && !isDeleted) ...[
            _buildOption(
              icon: Icons.edit,
              label: 'Edit',
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            _buildOption(
              icon: Icons.delete,
              label: 'Delete',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
          if (!isDeleted) ...[
            _buildOption(
              icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: isPinned ? 'Unpin' : 'Pin',
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            _buildOption(
              icon: Icons.copy,
              label: 'Copy',
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color ?? ColorConstants.primaryColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color ?? ColorConstants.primaryColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}