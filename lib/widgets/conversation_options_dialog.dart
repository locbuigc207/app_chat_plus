import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ColorConstants.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.more_horiz_rounded,
                      color: ColorConstants.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Tùy chọn cuộc trò chuyện',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Divider(
              height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100),
          _buildListOption(
            context: context,
            isDark: isDark,
            icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: isPinned ? 'Bỏ ghim' : 'Ghim cuộc trò chuyện',
            subtitle: isPinned ? 'Xóa khỏi danh sách đã ghim' : 'Hiển thị ở đầu danh sách',
            color: ColorConstants.primaryColor,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              onPin();
            },
          ),
          _buildListOption(
            context: context,
            isDark: isDark,
            icon: isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            label: isMuted ? 'Bật thông báo' : 'Tắt thông báo',
            subtitle: isMuted ? 'Nhận thông báo từ cuộc trò chuyện' : 'Không nhận thông báo',
            color: const Color(0xFF9C27B0),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              onMute();
            },
          ),
          _buildListOption(
            context: context,
            isDark: isDark,
            icon: isArchived ? Icons.unarchive_rounded : Icons.archive_rounded,
            label: isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ',
            subtitle: isArchived ? 'Đưa về danh sách chính' : 'Chuyển vào mục lưu trữ',
            color: const Color(0xFFFF9800),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              onArchive();
            },
          ),
          _buildListOption(
            context: context,
            isDark: isDark,
            icon: Icons.mark_chat_read_rounded,
            label: 'Đánh dấu đã đọc',
            subtitle: 'Xóa badge tin nhắn chưa đọc',
            color: Colors.green,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
              onMarkAsRead();
            },
          ),
          Divider(
              height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100),
          _buildListOption(
            context: context,
            isDark: isDark,
            icon: Icons.delete_sweep_rounded,
            label: 'Xóa lịch sử trò chuyện',
            subtitle: 'Không thể hoàn tác sau khi xóa',
            color: Colors.red,
            onTap: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(context);
              _confirmClearHistory(context, isDark);
            },
          ),
          const SizedBox(height: 8),
          SafeArea(child: const SizedBox(height: 8)),
        ],
      ),
    );
  }

  Widget _buildListOption({
    required BuildContext context,
    required bool isDark,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? Colors.white12 : Colors.grey.shade300, size: 18),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Xóa lịch sử',
                style: TextStyle(
                    fontSize: 17,
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Toàn bộ tin nhắn sẽ bị xóa vĩnh viễn và không thể khôi phục. Bạn có chắc chắn?',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Huỷ',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onClearHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
