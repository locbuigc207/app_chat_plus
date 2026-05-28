import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Animated dot indicator for a user's online / offline presence.
/// Supports text mode (shows "Online" / "3m ago") and dot-only mode.
class UserStatusIndicator extends StatelessWidget {
  final String userId;
  final double size;
  final bool showText;
  final Color? textColor;
  final bool animate;

  const UserStatusIndicator({
    super.key,
    required this.userId,
    this.size = 12,
    this.showText = false,
    this.textColor,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();

    return StreamBuilder<UserPresence>(
      stream: presenceProvider.getUserPresenceStream(userId),
      builder: (context, snapshot) {
        final presence = snapshot.data;
        final isOnline = presence?.isOnline ?? false;
        final lastSeen = presence?.lastSeen;

        return _StatusContent(
          isOnline: isOnline,
          lastSeen: lastSeen,
          size: size,
          showText: showText,
          textColor: textColor,
          animate: animate,
        );
      },
    );
  }
}

// ── Inner stateful widget so it can carry pulse animation ────────────────────

class _StatusContent extends StatefulWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  final double size;
  final bool showText;
  final Color? textColor;
  final bool animate;

  const _StatusContent({
    required this.isOnline,
    required this.lastSeen,
    required this.size,
    required this.showText,
    required this.textColor,
    required this.animate,
  });

  @override
  State<_StatusContent> createState() => _StatusContentState();
}

class _StatusContentState extends State<_StatusContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.isOnline && widget.animate) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_StatusContent old) {
    super.didUpdateWidget(old);
    if (widget.isOnline && widget.animate) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = _buildDot();
    if (!widget.showText) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            _statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.isOnline ? FontWeight.w600 : FontWeight.w400,
              color: widget.textColor ??
                  (widget.isOnline
                      ? const Color(0xFF34C759)
                      : ColorConstants.greyColor),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildDot() {
    if (!widget.isOnline || !widget.animate) {
      return _Dot(
          size: widget.size,
          color: widget.isOnline
              ? const Color(0xFF34C759)
              : ColorConstants.greyColor);
    }

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring
          Container(
            width: widget.size * 2,
            height: widget.size * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  const Color(0xFF34C759).withOpacity(0.25 * _pulseAnim.value),
            ),
          ),
          _Dot(size: widget.size, color: const Color(0xFF34C759)),
        ],
      ),
    );
  }

  String get _statusText {
    if (widget.isOnline) return 'Đang hoạt động';
    if (widget.lastSeen == null) return 'Ngoại tuyến';

    final diff = DateTime.now().difference(widget.lastSeen!);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return DateFormat('dd MMM').format(widget.lastSeen!);
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;

  const _Dot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Avatar widget with an animated online status dot overlay.
class AvatarWithStatus extends StatelessWidget {
  final String userId;
  final String photoUrl;
  final double size;
  final double indicatorSize;
  final bool showRing;

  const AvatarWithStatus({
    super.key,
    required this.userId,
    required this.photoUrl,
    this.size = 50,
    this.indicatorSize = 14,
    this.showRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();

    return StreamBuilder<UserPresence>(
      stream: presenceProvider.getUserPresenceStream(userId),
      builder: (context, snapshot) {
        final isOnline = snapshot.data?.isOnline ?? false;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Avatar ────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: showRing && isOnline
                    ? Border.all(
                        color: const Color(0xFF34C759),
                        width: 2.5,
                      )
                    : Border.all(color: Colors.transparent, width: 2.5),
              ),
              child: ClipOval(child: _buildImage()),
            ),

            // ── Status dot ────────────────────────────────────────────
            Positioned(
              right: 0,
              bottom: 0,
              child: UserStatusIndicator(
                userId: userId,
                size: indicatorSize,
                animate: isOnline,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage() {
    if (photoUrl.isEmpty) {
      return Icon(
        Icons.account_circle_rounded,
        size: size,
        color: ColorConstants.greyColor,
      );
    }

    return Image.network(
      photoUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 2).toInt(),
      cacheHeight: (size * 2).toInt(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: size,
          height: size,
          color: ColorConstants.greyColor2,
          child: Center(
            child: SizedBox(
              width: size * 0.35,
              height: size * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: ColorConstants.primaryColor,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Icon(
        Icons.account_circle_rounded,
        size: size,
        color: ColorConstants.greyColor,
      ),
    );
  }
}

/// Compact inline status badge — just text with a coloured dot.
/// Useful in chat headers and profile screens.
class StatusBadge extends StatelessWidget {
  final String userId;

  const StatusBadge({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return UserStatusIndicator(
      userId: userId,
      size: 8,
      showText: true,
      animate: true,
    );
  }
}
