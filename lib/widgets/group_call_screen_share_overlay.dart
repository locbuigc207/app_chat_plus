// ignore_for_file: deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _K {
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF22C55E);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// ScreenShareToolbar
// Floating toolbar shown while the local user is sharing their screen.
// Stays on top with a red "sharing" pill and a stop button.
// ══════════════════════════════════════════════════════════════════════════════
class ScreenShareToolbar extends StatefulWidget {
  final VoidCallback onStop;
  final int viewerCount;

  const ScreenShareToolbar({
    super.key,
    required this.onStop,
    required this.viewerCount,
  });

  @override
  State<ScreenShareToolbar> createState() => _ScreenShareToolbarState();
}

class _ScreenShareToolbarState extends State<ScreenShareToolbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.78),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _K.red.withOpacity(0.35), width: 1.5),
              boxShadow: [
                BoxShadow(color: _K.red.withOpacity(0.25), blurRadius: 16),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Live dot
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _K.red.withOpacity(_pulseAnim.value),
                    boxShadow: [
                      BoxShadow(
                          color: _K.red.withOpacity(_pulseAnim.value * 0.6),
                          blurRadius: 8)
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 7),
              if (_expanded) ...[
                const Icon(Icons.screen_share_rounded, color: _K.red, size: 14),
                const SizedBox(width: 5),
                const Text('Đang chia sẻ màn hình',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                if (widget.viewerCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_rounded,
                          color: Colors.white54, size: 10),
                      const SizedBox(width: 3),
                      Text('${widget.viewerCount}',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  // Stop button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onStop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _K.red,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: _K.red.withOpacity(0.4), blurRadius: 8)
                        ],
                      ),
                      child: const Text('Dừng',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ] else
                Text('Chia sẻ',
                    style: TextStyle(
                        color: _K.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ScreenShareViewerBanner
// Compact banner shown to viewers watching someone's screen share.
// ══════════════════════════════════════════════════════════════════════════════
class ScreenShareViewerBanner extends StatelessWidget {
  final String sharerName;
  final String? sharerAvatar;
  final VoidCallback? onPinTap;

  const ScreenShareViewerBanner({
    super.key,
    required this.sharerName,
    this.sharerAvatar,
    this.onPinTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _K.s2.withOpacity(0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _K.accent.withOpacity(0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 13,
              backgroundImage: sharerAvatar != null && sharerAvatar!.isNotEmpty
                  ? NetworkImage(sharerAvatar!)
                  : null,
              backgroundColor: _K.s2,
              child: sharerAvatar == null || sharerAvatar!.isEmpty
                  ? Text(
                      sharerName.isNotEmpty ? sharerName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 9))
                  : null,
            ),
            const SizedBox(width: 7),
            Text('$sharerName đang chia sẻ',
                style: const TextStyle(
                    color: _K.text, fontSize: 11, fontWeight: FontWeight.w600)),
            if (onPinTap != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPinTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _K.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _K.accent.withOpacity(0.25)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.push_pin_rounded, color: _K.accent, size: 11),
                    SizedBox(width: 3),
                    Text('Ghim',
                        style: TextStyle(
                            color: _K.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ScreenShareRequestDialog
// Dialog shown to participants when someone requests to share screen
// ══════════════════════════════════════════════════════════════════════════════
class ScreenShareRequestDialog extends StatelessWidget {
  final String requesterName;
  final String? requesterAvatar;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const ScreenShareRequestDialog({
    super.key,
    required this.requesterName,
    this.requesterAvatar,
    required this.onApprove,
    required this.onDeny,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String requesterName,
    String? requesterAvatar,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ScreenShareRequestDialog(
        requesterName: requesterName,
        requesterAvatar: requesterAvatar,
        onApprove: () => Navigator.pop(context, true),
        onDeny: () => Navigator.pop(context, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _K.surface.withOpacity(0.97),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _K.accent.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: _K.accent.withOpacity(0.25)),
                  ),
                  child: const Icon(Icons.screen_share_rounded,
                      color: _K.accent, size: 26)),
              const SizedBox(height: 14),
              const Text('Yêu cầu chia sẻ màn hình',
                  style: TextStyle(
                      color: _K.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircleAvatar(
                    radius: 14,
                    backgroundImage: requesterAvatar != null
                        ? NetworkImage(requesterAvatar!)
                        : null,
                    backgroundColor: _K.s2,
                    child: requesterAvatar == null
                        ? Text(
                            requesterName.isNotEmpty
                                ? requesterName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10))
                        : null),
                const SizedBox(width: 7),
                Flexible(
                  child: Text('$requesterName muốn chia sẻ màn hình',
                      style: const TextStyle(color: _K.sub, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ]),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                    child: TextButton(
                        onPressed: onDeny,
                        style: TextButton.styleFrom(
                            foregroundColor: _K.muted,
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: const Text('Từ chối',
                            style: TextStyle(fontWeight: FontWeight.w600)))),
                const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: ElevatedButton(
                        onPressed: onApprove,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _K.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        child: const Text('Cho phép',
                            style: TextStyle(fontWeight: FontWeight.w700)))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
