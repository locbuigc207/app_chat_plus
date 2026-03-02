// lib/widgets/enhanced_conversation_options.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';

class EnhancedConversationOptions extends StatelessWidget {
  final bool isPinned;
  final bool isMuted;
  final String userId;
  final String userName;
  final String userAvatar;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onClearHistory;
  final VoidCallback onMarkAsRead;

  const EnhancedConversationOptions({
    super.key,
    required this.isPinned,
    required this.isMuted,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.onPin,
    required this.onMute,
    required this.onClearHistory,
    required this.onMarkAsRead,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleService = ChatBubbleService();

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

          Divider(height: 1, thickness: 1),

          // 🎯 NEW: Create Chat Bubble
          _buildOption(
            icon: Icons.bubble_chart,
            label: 'Create Chat Bubble',
            color: Colors.blue,
            onTap: () async {
              Navigator.pop(context);

              final hasPermission = await bubbleService.hasOverlayPermission();
              if (!hasPermission) {
                final granted = await bubbleService.requestOverlayPermission();
                if (!granted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Overlay permission required for chat bubbles'),
                      action: SnackBarAction(
                        label: 'Settings',
                        onPressed: () async {
                          await bubbleService.requestOverlayPermission();
                        },
                      ),
                    ),
                  );
                  return;
                }
              }

              final success = await bubbleService.showChatBubble(
                userId: userId,
                userName: userName,
                avatarUrl: userAvatar,
              );

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Chat bubble created for $userName'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),

          Divider(height: 1, thickness: 1),

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
