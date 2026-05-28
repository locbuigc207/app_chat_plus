import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/services/chat_bubble_service.dart';

class EnhancedConversationOptions extends StatefulWidget {
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool isBlocked;
  final String userId;
  final String userName;
  final String userAvatar;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onClearHistory;
  final VoidCallback onMarkAsRead;
  final VoidCallback? onArchive;
  final VoidCallback? onBlock;
  final VoidCallback? onViewProfile;
  final VoidCallback? onSearchMessages;

  const EnhancedConversationOptions({
    super.key,
    required this.isPinned,
    required this.isMuted,
    this.isArchived = false,
    this.isBlocked = false,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.onPin,
    required this.onMute,
    required this.onClearHistory,
    required this.onMarkAsRead,
    this.onArchive,
    this.onBlock,
    this.onViewProfile,
    this.onSearchMessages,
  });

  @override
  State<EnhancedConversationOptions> createState() =>
      _EnhancedConversationOptionsState();
}

class _EnhancedConversationOptionsState
    extends State<EnhancedConversationOptions>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubbleService = ChatBubbleService();

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) => FadeTransition(
        opacity: _fadeAnim,
        child: Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: child,
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // ── User header ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (widget.isPinned)
                              _buildTag(
                                Icons.push_pin_rounded,
                                'Đã ghim',
                                ColorConstants.primaryColor,
                              ),
                            if (widget.isMuted)
                              _buildTag(
                                Icons.volume_off_rounded,
                                'Tắt âm',
                                Colors.orange,
                              ),
                            if (!widget.isPinned && !widget.isMuted)
                              Text(
                                'Nhấn để xem tùy chọn',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                  ColorConstants.greyColor.withOpacity(0.7),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Quick action chips ───────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  _buildChip(
                    icon: widget.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    label: widget.isPinned ? 'Bỏ ghim' : 'Ghim',
                    color: ColorConstants.primaryColor,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      widget.onPin();
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildChip(
                    icon: widget.isMuted
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: widget.isMuted ? 'Bật âm' : 'Tắt âm',
                    color: Colors.orange,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      widget.onMute();
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildChip(
                    icon: Icons.mark_chat_read_rounded,
                    label: 'Đã đọc',
                    color: Colors.green,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      widget.onMarkAsRead();
                    },
                  ),
                  if (widget.onSearchMessages != null) ...[
                    const SizedBox(width: 10),
                    _buildChip(
                      icon: Icons.search_rounded,
                      label: 'Tìm kiếm',
                      color: const Color(0xFF5856D6),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        widget.onSearchMessages!();
                      },
                    ),
                  ],
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: Color(0xFFF2F2F7)),
            ),

            // ── Full options list ────────────────────────────────────────
            if (widget.onViewProfile != null)
              _buildListTile(
                icon: Icons.account_circle_rounded,
                label: 'Xem hồ sơ',
                subtitle: 'Thông tin cá nhân',
                color: ColorConstants.primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  widget.onViewProfile!();
                },
              ),

            _buildListTile(
              icon: Icons.bubble_chart_rounded,
              label: 'Tạo Chat Bubble',
              subtitle: 'Hiển thị nổi trên màn hình',
              color: const Color(0xFF007AFF),
              onTap: () async {
                Navigator.pop(context);
                final hasPermission =
                await bubbleService.hasOverlayPermission();
                if (!hasPermission) {
                  final granted =
                  await bubbleService.requestOverlayPermission();
                  if (!granted) {
                    if (context.mounted) {
                      _showSnackBar(
                        context,
                        message: 'Cần quyền hiển thị nổi cho chat bubble',
                        actionLabel: 'Cài đặt',
                        onAction: () => bubbleService.requestOverlayPermission(),
                        isError: true,
                      );
                    }
                    return;
                  }
                }
                final success = await bubbleService.showChatBubble(
                  userId: widget.userId,
                  userName: widget.userName,
                  avatarUrl: widget.userAvatar,
                );
                if (success && context.mounted) {
                  _showSnackBar(
                    context,
                    message: 'Chat bubble cho ${widget.userName} đã tạo',
                    icon: Icons.check_circle_rounded,
                    isSuccess: true,
                  );
                }
              },
            ),

            if (widget.onArchive != null)
              _buildListTile(
                icon: widget.isArchived
                    ? Icons.unarchive_rounded
                    : Icons.archive_rounded,
                label: widget.isArchived ? 'Bỏ lưu trữ' : 'Lưu trữ',
                subtitle: widget.isArchived
                    ? 'Khôi phục cuộc trò chuyện'
                    : 'Ẩn khỏi danh sách chính',
                color: const Color(0xFF636366),
                onTap: () {
                  Navigator.pop(context);
                  widget.onArchive!();
                },
              ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: Color(0xFFF2F2F7)),
            ),

            _buildListTile(
              icon: Icons.delete_sweep_rounded,
              label: 'Xóa lịch sử chat',
              subtitle: 'Không thể hoàn tác',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                widget.onClearHistory();
              },
            ),

            if (widget.onBlock != null)
              _buildListTile(
                icon: widget.isBlocked
                    ? Icons.block_rounded
                    : Icons.block_rounded,
                label: widget.isBlocked ? 'Bỏ chặn người dùng' : 'Chặn',
                subtitle: widget.isBlocked
                    ? 'Cho phép liên lạc trở lại'
                    : 'Không nhận tin nhắn từ người này',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  widget.onBlock!();
                },
              ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                ColorConstants.primaryColor.withOpacity(0.2),
                ColorConstants.primaryColor.withOpacity(0.05),
              ],
            ),
          ),
          child: ClipOval(
            child: widget.userAvatar.isNotEmpty
                ? Image.network(
              widget.userAvatar,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultAvatarIcon(),
            )
                : _defaultAvatarIcon(),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatarIcon() => Icon(
    Icons.account_circle_rounded,
    size: 52,
    color: ColorConstants.primaryColor.withOpacity(0.4),
  );

  Widget _buildTag(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      highlightColor: color.withOpacity(0.05),
      splashColor: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color == Colors.red || color == Colors.orange
                          ? color
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: const Color(0xFFD1D5DB),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(
      BuildContext context, {
        required String message,
        IconData? icon,
        String? actionLabel,
        VoidCallback? onAction,
        bool isError = false,
        bool isSuccess = false,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError
            ? Colors.red
            : (isSuccess ? Colors.green : Colors.grey[800]),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        action: actionLabel != null
            ? SnackBarAction(
          label: actionLabel,
          textColor: Colors.white,
          onPressed: onAction ?? () {},
        )
            : null,
      ),
    );
  }
}