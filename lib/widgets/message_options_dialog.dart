import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

/// A lightweight, clean message options sheet. For the full-featured version
/// with emoji reactions and animations, use [EnhancedMessageOptionsDialog].
class MessageOptionsDialog extends StatelessWidget {
  final bool isOwnMessage;
  final bool isPinned;
  final bool isDeleted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onCopy;
  final VoidCallback onReply;
  final VoidCallback? onForward;
  final VoidCallback? onReminder;

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
    this.onForward,
    this.onReminder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Own-message actions ──────────────────────────────────────
          if (isOwnMessage && !isDeleted) ...[
            _buildOption(
              context,
              icon: Icons.edit_rounded,
              label: 'Chỉnh sửa',
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            _divider(),
            _buildOption(
              context,
              icon: Icons.delete_rounded,
              label: 'Thu hồi',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            _divider(),
          ],

          // ── Shared actions ───────────────────────────────────────────
          if (!isDeleted) ...[
            _buildOption(
              context,
              icon: Icons.reply_rounded,
              label: 'Trả lời',
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            _divider(),
            _buildOption(
              context,
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              label: isPinned ? 'Bỏ ghim' : 'Ghim',
              onTap: () {
                Navigator.pop(context);
                onPin();
              },
            ),
            _divider(),
            _buildOption(
              context,
              icon: Icons.copy_rounded,
              label: 'Sao chép',
              onTap: () {
                Navigator.pop(context);
                onCopy();
              },
            ),
            if (onForward != null) ...[
              _divider(),
              _buildOption(
                context,
                icon: Icons.forward_rounded,
                label: 'Chuyển tiếp',
                onTap: () {
                  Navigator.pop(context);
                  onForward!();
                },
              ),
            ],
            if (onReminder != null) ...[
              _divider(),
              _buildOption(
                context,
                icon: Icons.alarm_add_rounded,
                label: 'Đặt nhắc nhở',
                onTap: () {
                  Navigator.pop(context);
                  onReminder!();
                },
              ),
            ],
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
      );

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? ColorConstants.primaryColor;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      highlightColor: c.withOpacity(0.05),
      splashColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: c,
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
