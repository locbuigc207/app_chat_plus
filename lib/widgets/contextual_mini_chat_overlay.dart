import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'bubble_adaptive_ui.dart';
import 'secure_view_once_widget.dart';
import 'shared_space_widget.dart';

const _kOverlayWidth = 348.0;
const _kCollapsedHeight = 56.0;
const _kExpandedHeight = 540.0;
const _kSharedHeight = 500.0;
const _kBorderRadius = 18.0;
const _kShadowBlur = 32.0;
const _kDefaultTopOffset = 90.0;
const _kDefaultLeftOffset = 18.0;

class ContextualMiniChatOverlay extends StatefulWidget {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String conversationId;
  final String currentUserId;

  final Widget chatContent;

  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const ContextualMiniChatOverlay({
    super.key,
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.conversationId,
    required this.currentUserId,
    required this.chatContent,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<ContextualMiniChatOverlay> createState() => _ContextualMiniChatOverlayState();
}

class _ContextualMiniChatOverlayState extends State<ContextualMiniChatOverlay>
    with TickerProviderStateMixin {
  final _ctxSvc = ContextualBubbleService();
  BubbleContext _ctx = BubbleContext(mode: BubbleMode.normal, updatedAt: DateTime.now());
  StreamSubscription<BubbleContext>? _ctxSub;

  Offset _pos = const Offset(_kDefaultLeftOffset, _kDefaultTopOffset);
  bool _dragging = false;

  bool _isExpanded = true;
  bool _isSharedOpen = false;
  bool _isSecureOn = false;
  int _activeTab = 0;

  late AnimationController _slideIn;
  late AnimationController _expandAnim;
  late AnimationController _sharedAnim;
  late AnimationController _dragScale;
  late Animation<double> _expandCurve;
  late Animation<double> _dragScaleCurve;

  @override
  void initState() {
    super.initState();

    _slideIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..forward();

    _expandAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      value: 1.0,
    );
    _expandCurve = CurvedAnimation(parent: _expandAnim, curve: Curves.easeInOutCubic);

    _sharedAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

    _dragScale = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _dragScaleCurve = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _dragScale, curve: Curves.easeIn));

    _ctxSub = _ctxSvc.contextStream.listen((ctx) {
      if (mounted) setState(() => _ctx = ctx);
    });
  }

  @override
  void dispose() {
    _ctxSub?.cancel();
    _slideIn.dispose();
    _expandAnim.dispose();
    _sharedAnim.dispose();
    _dragScale.dispose();
    super.dispose();
  }

  double get _targetHeight {
    if (!_isExpanded) return _kCollapsedHeight;
    if (_isSharedOpen) return _kSharedHeight;
    return _kExpandedHeight;
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
    _isExpanded ? _expandAnim.forward() : _expandAnim.reverse();
    if (!_isExpanded) {
      _isSharedOpen = false;
      _sharedAnim.reverse();
    }
    HapticFeedback.lightImpact();
  }

  void _openTab(int tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    if (tab == 1 && !_isSharedOpen) _toggleShared();
    if (tab == 0 && _isSharedOpen) _toggleShared();
    HapticFeedback.selectionClick();
  }

  void _toggleShared() {
    setState(() => _isSharedOpen = !_isSharedOpen);
    _isSharedOpen ? _sharedAnim.forward() : _sharedAnim.reverse();
    _isSharedOpen ? _ctxSvc.activateSharedMode() : _ctxSvc.resetToNormal();
    HapticFeedback.mediumImpact();
  }

  void _toggleSecure() {
    setState(() => _isSecureOn = !_isSecureOn);
    _isSecureOn ? _ctxSvc.activateSecureMode() : _ctxSvc.resetToNormal();
    HapticFeedback.heavyImpact();
  }

  void _setMode(BubbleMode mode) {
    if (_ctx.mode == mode) {
      _ctxSvc.resetToNormal();
    } else {
      _ctxSvc.analyzeMessage(
        content: mode.name,
        messageType: 0,
      );
    }
    HapticFeedback.selectionClick();
  }

  void _onPanStart(DragStartDetails _) {
    setState(() => _dragging = true);
    _dragScale.forward();
  }

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    setState(() {
      _pos = Offset(
        (_pos.dx + d.delta.dx).clamp(0, screen.width - _kOverlayWidth),
        (_pos.dy + d.delta.dy).clamp(0, screen.height - _targetHeight),
      );
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    _dragScale.reverse();
    _snapIfNeeded();
  }

  void _snapIfNeeded() {
    final screenWidth = _lastScreenWidth;
    if (screenWidth <= 0) return;
    const snapThreshold = 60.0;
    if (_pos.dx < snapThreshold) {
      setState(() => _pos = Offset(8, _pos.dy));
    } else if (_pos.dx > screenWidth - _kOverlayWidth - snapThreshold) {
      setState(() => _pos = Offset(screenWidth - _kOverlayWidth - 8, _pos.dy));
    }
  }

  double _lastScreenWidth = 0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    _lastScreenWidth = screen.width;

    final clampedX = _pos.dx.clamp(0.0, screen.width - _kOverlayWidth);
    final clampedY = _pos.dy.clamp(0.0, screen.height - _targetHeight.clamp(0, screen.height));

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: _buildAnimatedEntry(),
    );
  }

  Widget _buildAnimatedEntry() {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _slideIn, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _slideIn, curve: Curves.easeOutBack)),
        child: ScaleTransition(
          scale: _dragScaleCurve,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: (d) => _onPanUpdate(d, MediaQuery.of(context).size),
            onPanEnd: _onPanEnd,
            child: _buildCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      width: _kOverlayWidth,
      height: _targetHeight,
      child: Material(
        elevation: _dragging ? 28 : 16,
        borderRadius: BorderRadius.circular(_kBorderRadius),
        shadowColor: Colors.black.withValues(alpha: 0.4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kBorderRadius),
          child: _buildCardContent(),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF5F7FD)),
      child: Column(
        children: [
          BubbleAdaptiveHeader(
            bubbleCtx: _ctx,
            peerName: widget.userName,
            peerAvatar: widget.avatarUrl,
            onMinimize: widget.onMinimize,
            onClose: widget.onClose,
          ),
          if (_isExpanded) _buildFeatureBar(),
          Expanded(child: _buildContent()),
          if (_isExpanded) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildFeatureBar() {
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEF1F8))),
      ),
      child: Row(
        children: [
          _FeatureTab(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            isActive: _activeTab == 0,
            onTap: () => _openTab(0),
          ),
          _FeatureTab(
            icon: Icons.palette_outlined,
            label: 'Space',
            isActive: _activeTab == 1,
            onTap: () => _openTab(1),
          ),
          const Spacer(),
          _ModePill(mode: _ctx.mode),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SecureModeToggle(
              isActive: _isSecureOn,
              onChanged: (_) => _toggleSecure(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!_isExpanded) {
      return GestureDetector(
        onTap: _toggleExpand,
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Text(
            '↑ Chạm để mở rộng',
            style: TextStyle(
              color: const Color(0xFF9AA5B8).withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: _activeTab == 1
          ? SharedSpaceWidget(
              key: const ValueKey('shared'),
              conversationId: widget.conversationId,
              currentUserId: widget.currentUserId,
              peerName: widget.userName,
            )
          : SecureOverlayManager(
              key: const ValueKey('chat'),
              isActive: _isSecureOn,
              onSecureStateChanged: () => HapticFeedback.heavyImpact(),
              child: widget.chatContent,
            ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF1F8))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _BottomBarBtn(
            icon: _isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
            label: _isExpanded ? 'Thu gọn' : 'Mở rộng',
            onTap: _toggleExpand,
          ),
          const Spacer(),
          _QuickModeBtn(
            icon: Icons.work_outline_rounded,
            mode: BubbleMode.work,
            current: _ctx.mode,
            onTap: () => _setMode(BubbleMode.work),
          ),
          _QuickModeBtn(
            icon: Icons.music_note_outlined,
            mode: BubbleMode.media,
            current: _ctx.mode,
            onTap: () => _setMode(BubbleMode.media),
          ),
          _QuickModeBtn(
            icon: Icons.location_on_outlined,
            mode: BubbleMode.location,
            current: _ctx.mode,
            onTap: () => _setMode(BubbleMode.location),
          ),
        ],
      ),
    );
  }
}

class _FeatureTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FeatureTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF1E88E5) : const Color(0xFF9AA5B8);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF1E88E5) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final BubbleMode mode;
  const _ModePill({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _data(mode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color, String) _data(BubbleMode m) {
    switch (m) {
      case BubbleMode.work:
        return (Icons.work_rounded, const Color(0xFF66BB6A), 'Work');
      case BubbleMode.media:
        return (Icons.music_note_rounded, const Color(0xFFE91E63), 'Media');
      case BubbleMode.location:
        return (Icons.location_on_rounded, const Color(0xFF43A047), 'Location');
      case BubbleMode.shared:
        return (Icons.palette_rounded, const Color(0xFF7E57C2), 'Shared');
      case BubbleMode.secure:
        return (Icons.shield_rounded, const Color(0xFF1565C0), 'Secure');
      default:
        return (Icons.chat_rounded, const Color(0xFF9AA5B8), 'Normal');
    }
  }
}

class _BottomBarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomBarBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF1F8),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF9AA5B8)),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(color: Color(0xFF9AA5B8), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _QuickModeBtn extends StatelessWidget {
  final IconData icon;
  final BubbleMode mode;
  final BubbleMode current;
  final VoidCallback onTap;

  const _QuickModeBtn({
    required this.icon,
    required this.mode,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == mode;
    return Tooltip(
      message: ContextualBubbleService.labelFor(mode),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E88E5).withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? const Color(0xFF1E88E5) : const Color(0xFF9AA5B8),
          ),
        ),
      ),
    );
  }
}
