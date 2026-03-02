// lib/widgets/conversation_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ConversationOptionsDialog extends StatelessWidget {
  final bool isPinned;
  final bool isMuted;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onClearHistory;
  final VoidCallback onMarkAsRead;

  const ConversationOptionsDialog({
    super.key,
    required this.isPinned,
    required this.isMuted,
    required this.onPin,
    required this.onMute,
    required this.onClearHistory,
    required this.onMarkAsRead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: isPinned ? 'Unpin' : 'Pin',
            onTap: () {
              Navigator.pop(context);
              onPin();
            },
          ),
          _buildOption(
            icon: isMuted ? Icons.volume_up : Icons.volume_off,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: () {
              Navigator.pop(context);
              onMute();
            },
          ),
          _buildOption(
            icon: Icons.mark_chat_read,
            label: 'Mark as read',
            onTap: () {
              Navigator.pop(context);
              onMarkAsRead();
            },
          ),
          const Divider(height: 1),
          _buildOption(
            icon: Icons.delete_sweep,
            label: 'Clear history',
            color: Colors.orange,
            onTap: () {
              Navigator.pop(context);
              onClearHistory();
            },
          ),
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
