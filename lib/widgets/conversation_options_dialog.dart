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
              color: isDark ? Colors.white16 : ColorConstants.greyColor2,
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
            child: Row(
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
                const SizedBox(width: 10),
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
                const SizedBox(width: 10),
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
                const SizedBox(width: 10),
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── ENHANCED MESSAGE OPTIONS ──────────────────────────────────────────────────
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
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white16 : ColorConstants.greyColor2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Message preview
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? ColorConstants.surfaceDark2
                  : ColorConstants.greyColor2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    messageContent.length > 80
                        ? '${messageContent.substring(0, 80)}…'
                        : messageContent,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontStyle:
                          isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Actions list
          if (!isDeleted) ...[
            _SheetItem(
              icon: Icons.reply_rounded,
              label: 'Reply',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            _SheetItem(
              icon: Icons.copy_rounded,
              label: 'Copy Text',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onCopy();
              },
            ),
            _SheetItem(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              label: isPinned ? 'Unpin' : 'Pin Message',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            _SheetItem(
              icon: Icons.alarm_add_outlined,
              label: 'Set Reminder',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onReminder();
              },
            ),
            _SheetItem(
              icon: Icons.translate_rounded,
              label: 'Translate',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onTranslate();
              },
            ),
          ],
          if (isOwnMessage && !isDeleted) ...[
            Divider(
              height: 1,
              color: isDark
                  ? ColorConstants.borderDark
                  : ColorConstants.greyColor2,
              indent: 16,
              endIndent: 16,
            ),
            _SheetItem(
              icon: Icons.edit_outlined,
              label: 'Edit Message',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            _SheetItem(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Message',
              isDark: isDark,
              color: ColorConstants.accentRed,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
          const SizedBox(height: 8),
          SafeArea(child: const SizedBox()),
        ],
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color? color;
  final VoidCallback onTap;

  const _SheetItem({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor =
        color ?? (isDark ? Colors.white : const Color(0xFF1A1D2E));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (color ?? ColorConstants.primaryColor)
                    .withOpacity(isDark ? 0.12 : 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: color ?? ColorConstants.primaryColor, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
