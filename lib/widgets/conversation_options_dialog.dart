// lib/widgets/conversation_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ConversationOptionsDialog extends StatelessWidget {
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onClearHistory;
  final VoidCallback onMarkAsRead;
  final VoidCallback onArchive;

  const ConversationOptionsDialog({
    super.key,
    required this.isPinned,
    required this.isMuted,
    required this.isArchived,
    required this.onPin,
    required this.onMute,
    required this.onClearHistory,
    required this.onMarkAsRead,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.16)
                  : ColorConstants.greyColor2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Text(
                  'Conversation Options',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Options grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _OptionCard(
                  icon: isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: isPinned ? 'Unpin' : 'Pin',
                  isDark: isDark,
                  color: ColorConstants.primaryColor,
                  onTap: () {
                    Navigator.pop(context);
                    onPin();
                  },
                ),
                _OptionCard(
                  icon: isMuted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  label: isMuted ? 'Unmute' : 'Mute',
                  isDark: isDark,
                  color: const Color(0xFF7B1FA2),
                  onTap: () {
                    Navigator.pop(context);
                    onMute();
                  },
                ),
                _OptionCard(
                  icon: isArchived
                      ? Icons.unarchive_rounded
                      : Icons.archive_outlined,
                  label: isArchived ? 'Unarchive' : 'Archive',
                  isDark: isDark,
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    onArchive();
                  },
                ),
                _OptionCard(
                  icon: Icons.mark_chat_read_outlined,
                  label: 'Mark Read',
                  isDark: isDark,
                  color: ColorConstants.accentGreen,
                  onTap: () {
                    Navigator.pop(context);
                    onMarkAsRead();
                  },
                ),
                _OptionCard(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Clear',
                  isDark: isDark,
                  color: ColorConstants.accentRed,
                  onTap: () {
                    Navigator.pop(context);
                    onClearHistory();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          SafeArea(child: const SizedBox()),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 62) / 4,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(isDark ? 0.2 : 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
