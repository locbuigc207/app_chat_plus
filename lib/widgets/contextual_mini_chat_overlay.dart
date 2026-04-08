// lib/widgets/contextual_mini_chat_overlay.dart
// Contextual Bubble Universe - Main Integration Widget
// Thay thế/bổ sung cho MiniChatOverlayWidget hiện tại

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/contextual_bubble_service.dart';
import 'bubble_adaptive_ui.dart';
import 'secure_view_once_widget.dart';
import 'shared_space_widget.dart';

// ─── CONTEXTUAL MINI CHAT OVERLAY ─────────────────────────────────────────────

/// Widget overlay mini chat với đầy đủ tính năng Contextual Bubble Universe
/// Drop-in replacement / wrapper cho MiniChatOverlayWidget
class ContextualMiniChatOverlay extends StatefulWidget {
  final String userId;
  final String userName;
  final String avatarUrl;
  final String conversationId;
  final String currentUserId;
  final Widget chatContent; // Truyền vào ChatPage hiện có
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
  State<ContextualMiniChatOverlay> createState() =>
      _ContextualMiniChatOverlayState();
}

class _ContextualMiniChatOverlayState extends State<ContextualMiniChatOverlay>
    with TickerProviderStateMixin {
  final _contextService = ContextualBubbleService();

  // Layout
  Offset _position = const Offset(20, 100);
  bool _isDragging = false;
  bool _isExpanded = true;
  bool _isSharedSpaceOpen = false;
  bool _isSecureModeOn = false;

  static const double _width = 340;
  static const double _collapsedHeight = 56;
  static const double _expandedHeight = 520;
  static const double _sharedSpaceHeight = 480;

  // Animations
  late AnimationController _expandAnim;
  late AnimationController _sharedSpaceAnim;
  late AnimationController _slideInAnim;
  late Animation<double> _expandCurve;

  // Context
  BubbleContext _context = BubbleContext(
    mode: BubbleMode.normal,
    updatedAt: DateTime.now(),
  );
  StreamSubscription? _contextSub;

  @override
  void initState() {
    super.initState();

    _expandAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1.0,
    );
    _expandCurve = CurvedAnimation(
      parent: _expandAnim,
      curve: Curves.easeInOutCubic,
    );

    _sharedSpaceAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideInAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _contextSub = _contextService.contextStream.listen((ctx) {
      if (mounted) setState(() => _context = ctx);
    });
  }

  @override
  void dispose() {
    _expandAnim.dispose();
    _sharedSpaceAnim.dispose();
    _slideInAnim.dispose();
    _contextSub?.cancel();
    super.dispose();
  }

  // ─── LAYOUT ────────────────────────────────────────────────────────────────

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandAnim.forward();
    } else {
      _expandAnim.reverse();
      _isSharedSpaceOpen = false;
      _sharedSpaceAnim.reverse();
    }
    HapticFeedback.lightImpact();
  }

  void _toggleSharedSpace() {
    setState(() => _isSharedSpaceOpen = !_isSharedSpaceOpen);
    if (_isSharedSpaceOpen) {
      _sharedSpaceAnim.forward();
      _contextService.activateSharedMode();
    } else {
      _sharedSpaceAnim.reverse();
      _contextService.resetToNormal();
    }
    HapticFeedback.mediumImpact();
  }

  void _toggleSecureMode() {
    setState(() => _isSecureModeOn = !_isSecureModeOn);
    if (_isSecureModeOn) {
      _contextService.activateSecureMode();
    } else {
      _contextService.resetToNormal();
    }
    HapticFeedback.heavyImpact();
  }

  double get _currentHeight {
    if (!_isExpanded) return _collapsedHeight;
    if (_isSharedSpaceOpen) return _sharedSpaceHeight;
    return _expandedHeight;
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _clampX(screenSize),
      top: _clampY(screenSize),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _slideInAnim,
          curve: Curves.easeOutBack,
        )),
        child: FadeTransition(
          opacity: _slideInAnim,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _isDragging = true),
            onPanUpdate: (d) => _onPanUpdate(d, screenSize),
            onPanEnd: (_) => setState(() => _isDragging = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
              width: _width,
              height: _currentHeight,
              child: _buildCard(context),
            ),
          ),
        ),
      ),
    );
  }

  double _clampX(Size screen) => _position.dx.clamp(0, screen.width - _width);

  double _clampY(Size screen) => _position.dy
      .clamp(0, screen.height - _currentHeight.clamp(0, screen.height));

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    setState(() {
      _position = Offset(
        (_position.dx + d.delta.dx).clamp(0, screen.width - _width),
        (_position.dy + d.delta.dy).clamp(0, screen.height - _currentHeight),
      );
    });
  }

  Widget _buildCard(BuildContext ctx) {
    return Material(
      elevation: _isDragging ? 20 : 12,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.black.withOpacity(0.3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FE),
          ),
          child: Column(
            children: [
              // ── Adaptive Header ──────────────────────────────────────────
              BubbleAdaptiveHeader(
                context: _context,
                peerName: widget.userName,
                peerAvatar: widget.avatarUrl,
                conversationId: widget.conversationId,
                currentUserId: widget.currentUserId,
                onMinimize: widget.onMinimize,
                onClose: widget.onClose,
              ),

              // ── Feature Bar ──────────────────────────────────────────────
              if (_isExpanded) _buildFeatureBar(),

              // ── Content ──────────────────────────────────────────────────
              Expanded(
                child: _buildContent(),
              ),

              // ── Bottom bar ───────────────────────────────────────────────
              if (_isExpanded) _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── FEATURE BAR ──────────────────────────────────────────────────────────

  Widget _buildFeatureBar() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEF1F8), width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildFeatureTab(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            isActive: !_isSharedSpaceOpen,
            onTap: () {
              if (_isSharedSpaceOpen) _toggleSharedSpace();
            },
          ),
          _buildFeatureTab(
            icon: Icons.palette_outlined,
            label: 'Space',
            isActive: _isSharedSpaceOpen,
            badge: null,
            onTap: _toggleSharedSpace,
          ),
          const Spacer(),
          // Mode indicator
          _buildModeChip(),
          const SizedBox(width: 6),
          // Secure toggle
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SecureModeToggle(
              isActive: _isSecureModeOn,
              onChanged: (_) => _toggleSecureMode(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTab({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF2196F3) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color:
                  isActive ? const Color(0xFF2196F3) : const Color(0xFF9AA5B8),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? const Color(0xFF2196F3)
                    : const Color(0xFF9AA5B8),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip() {
    final modeData = _getModeData(_context.mode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: modeData.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(modeData.icon, size: 10, color: modeData.color),
          const SizedBox(width: 3),
          Text(
            modeData.label,
            style: TextStyle(
              color: modeData.color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  _ModeData _getModeData(BubbleMode mode) {
    switch (mode) {
      case BubbleMode.work:
        return _ModeData(Icons.work_rounded, const Color(0xFF4CAF50), 'Work');
      case BubbleMode.media:
        return _ModeData(
            Icons.music_note_rounded, const Color(0xFFE91E63), 'Media');
      case BubbleMode.location:
        return _ModeData(
            Icons.location_on_rounded, const Color(0xFF4CAF50), 'Location');
      case BubbleMode.shared:
        return _ModeData(
            Icons.palette_rounded, const Color(0xFF9C27B0), 'Shared');
      case BubbleMode.secure:
        return _ModeData(
            Icons.shield_rounded, const Color(0xFF1565C0), 'Secure');
      default:
        return _ModeData(Icons.chat_rounded, const Color(0xFF9AA5B8), 'Normal');
    }
  }

  // ─── CONTENT ──────────────────────────────────────────────────────────────

  Widget _buildContent() {
    if (!_isExpanded) {
      return _buildCollapsedPreview();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _isSharedSpaceOpen
          ? SharedSpaceWidget(
              key: const ValueKey('shared'),
              conversationId: widget.conversationId,
              currentUserId: widget.currentUserId,
              peerName: widget.userName,
            )
          : _buildChatWithSecureOverlay(),
    );
  }

  Widget _buildChatWithSecureOverlay() {
    return SecureOverlayManager(
      isActive: _isSecureModeOn,
      onSecureStateChanged: () => HapticFeedback.heavyImpact(),
      child: widget.chatContent,
    );
  }

  Widget _buildCollapsedPreview() {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: Text(
            'Chạm để mở rộng',
            style: TextStyle(
              color: const Color(0xFF9AA5B8).withOpacity(0.8),
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  // ─── BOTTOM BAR ───────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFEEF1F8), width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          // Collapse toggle
          GestureDetector(
            onTap: _toggleExpand,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 14,
                    color: const Color(0xFF9AA5B8),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _isExpanded ? 'Thu gọn' : 'Mở rộng',
                    style:
                        const TextStyle(color: Color(0xFF9AA5B8), fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Quick context switch buttons
          _buildQuickModeBtn(
            Icons.work_outline_rounded,
            BubbleMode.work,
            'Work',
          ),
          _buildQuickModeBtn(
            Icons.music_note_outlined,
            BubbleMode.media,
            'Media',
          ),
          _buildQuickModeBtn(
            Icons.location_on_outlined,
            BubbleMode.location,
            'Location',
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildQuickModeBtn(
    IconData icon,
    BubbleMode mode,
    String tooltip,
  ) {
    final isActive = _context.mode == mode;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            _contextService.resetToNormal();
          } else {
            // Activate mode manually for demo
            _contextService.analyzeMessage(
              content: tooltip.toLowerCase(),
              messageType: 0,
            );
          }
          HapticFeedback.selectionClick();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF2196F3).withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isActive ? const Color(0xFF2196F3) : const Color(0xFF9AA5B8),
          ),
        ),
      ),
    );
  }
}

// ─── HELPER ──────────────────────────────────────────────────────────────────

class _ModeData {
  final IconData icon;
  final Color color;
  final String label;
  const _ModeData(this.icon, this.color, this.label);
}
