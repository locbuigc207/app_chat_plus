import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EnhancedMessageOptionsDialog extends StatefulWidget {
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
  final Function(String emoji)? onReact;
  final VoidCallback? onForward;
  final VoidCallback? onReport;

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
    this.onReact,
    this.onForward,
    this.onReport,
  });

  @override
  State<EnhancedMessageOptionsDialog> createState() => _EnhancedMessageOptionsDialogState();
}

class _EnhancedMessageOptionsDialogState extends State<EnhancedMessageOptionsDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;

  static const List<String> _quickEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _slideAnim = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
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
    return AnimatedBuilder(
      animation: _animController,
      builder: (ctx, child) => FadeTransition(
        opacity: _animController,
        child: Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: ScaleTransition(
            scale: _scaleAnim,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 48,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (!widget.isDeleted && widget.messageContent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.isOwnMessage
                        ? const Color(0xFF007AFF).withValues(alpha: 0.08)
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    widget.messageContent,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3A3A3C),
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (!widget.isDeleted && widget.onReact != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _quickEmojis
                      .map(
                        (e) => _EmojiButton(
                          emoji: e,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            Navigator.pop(context);
                            widget.onReact!(e);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Color(0xFFF2F2F7)),
              ),
            ] else
              const SizedBox(height: 8),
            if (widget.isOwnMessage && !widget.isDeleted) ...[
              _buildOption(
                icon: Icons.edit_rounded,
                label: 'Chỉnh sửa',
                onTap: () {
                  Navigator.pop(context);
                  widget.onEdit();
                },
              ),
              _buildOption(
                icon: Icons.delete_rounded,
                label: 'Thu hồi',
                color: const Color(0xFFFF3B30),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete();
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Color(0xFFF2F2F7)),
              ),
            ],
            if (!widget.isDeleted) ...[
              _buildOption(
                icon: Icons.reply_rounded,
                label: 'Trả lời',
                onTap: () {
                  Navigator.pop(context);
                  widget.onReply();
                },
              ),
              _buildOption(
                icon: widget.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                label: widget.isPinned ? 'Bỏ ghim' : 'Ghim tin nhắn',
                onTap: () {
                  Navigator.pop(context);
                  widget.onPin();
                },
              ),
              _buildOption(
                icon: Icons.copy_rounded,
                label: 'Sao chép',
                onTap: () {
                  Navigator.pop(context);
                  widget.onCopy();
                },
              ),
              if (widget.onForward != null)
                _buildOption(
                  icon: Icons.forward_rounded,
                  label: 'Chuyển tiếp',
                  onTap: () {
                    Navigator.pop(context);
                    widget.onForward!();
                  },
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Color(0xFFF2F2F7)),
              ),
              _buildOption(
                icon: Icons.alarm_add_rounded,
                label: 'Đặt nhắc nhở',
                onTap: () {
                  Navigator.pop(context);
                  widget.onReminder();
                },
              ),
              _buildOption(
                icon: Icons.translate_rounded,
                label: 'Dịch',
                onTap: () {
                  Navigator.pop(context);
                  widget.onTranslate();
                },
              ),
              if (!widget.isOwnMessage && widget.onReport != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1, color: Color(0xFFF2F2F7)),
                ),
                _buildOption(
                  icon: Icons.flag_rounded,
                  label: 'Báo cáo',
                  color: const Color(0xFFFF3B30),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReport!();
                  },
                ),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? const Color(0xFF1C1C1E);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      highlightColor: effectiveColor.withValues(alpha: 0.04),
      splashColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: effectiveColor, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 15.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: const Color(0xFFC7C7CC),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiButton({required this.emoji, required this.onTap});

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _ctrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Text(widget.emoji, style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }
}
