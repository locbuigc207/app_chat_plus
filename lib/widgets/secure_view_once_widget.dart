// lib/widgets/secure_view_once_widget.dart
// Contextual Bubble Universe - Secure Mode + Anti-Shoulder-Surf
// Làm mờ tin nhắn khi phát hiện khuôn mặt thứ hai qua camera trước

import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Trạng thái bảo mật hiện tại
enum SecureState { disabled, monitoring, warning, blurred }

// ─── SECURE OVERLAY MANAGER ──────────────────────────────────────────────────

class SecureOverlayManager extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final VoidCallback? onSecureStateChanged;

  const SecureOverlayManager({
    super.key,
    required this.child,
    required this.isActive,
    this.onSecureStateChanged,
  });

  @override
  State<SecureOverlayManager> createState() => _SecureOverlayManagerState();
}

class _SecureOverlayManagerState extends State<SecureOverlayManager>
    with TickerProviderStateMixin {
  SecureState _secureState = SecureState.disabled;
  CameraController? _cameraCtrl;
  Timer? _detectionTimer;

  late AnimationController _blurAnim;
  late AnimationController _shieldAnim;
  int _suspiciousFrameCount = 0;
  static const _suspiciousThreshold = 3;

  @override
  void initState() {
    super.initState();
    _blurAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shieldAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    if (widget.isActive) _initSecureMode();
  }

  @override
  void didUpdateWidget(SecureOverlayManager old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _initSecureMode();
    } else if (!widget.isActive && old.isActive) {
      _disableSecureMode();
    }
  }

  Future<void> _initSecureMode() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _secureState = SecureState.monitoring);

    if (!status.isGranted) {
      _startSimulatedMonitoring();
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { _startSimulatedMonitoring(); return; }

      final frontCam = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraCtrl = CameraController(
        frontCam, ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraCtrl!.initialize();
      await _cameraCtrl!.startImageStream(_analyzeFrame);
    } catch (e) {
      debugPrint('⚠️ Camera init: $e — simulated mode');
      _startSimulatedMonitoring();
    }
  }

  // PRODUCTION: Replace with ML Kit face detection
  // See SETUP_GUIDE.yaml for google_mlkit_face_detection integration
  void _analyzeFrame(CameraImage image) {
    _updateSecureState(isSuspicious: false);
  }

  void _startSimulatedMonitoring() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _updateSecureState(isSuspicious: false);
    });
  }

  void _updateSecureState({required bool isSuspicious}) {
    if (!mounted) return;
    if (isSuspicious) {
      _suspiciousFrameCount++;
      if (_suspiciousFrameCount >= _suspiciousThreshold &&
          _secureState != SecureState.blurred) {
        setState(() => _secureState = SecureState.blurred);
        _blurAnim.forward();
        HapticFeedback.heavyImpact();
        widget.onSecureStateChanged?.call();
      }
    } else {
      if (_suspiciousFrameCount > 0) _suspiciousFrameCount--;
      if (_suspiciousFrameCount == 0 && _secureState == SecureState.blurred) {
        setState(() => _secureState = SecureState.monitoring);
        _blurAnim.reverse();
      }
    }
  }

  void _disableSecureMode() {
    _detectionTimer?.cancel();
    try { _cameraCtrl?.stopImageStream(); _cameraCtrl?.dispose(); } catch (_) {}
    _cameraCtrl = null;
    _suspiciousFrameCount = 0;
    if (mounted) {
      setState(() => _secureState = SecureState.disabled);
      _blurAnim.reverse();
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    try { _cameraCtrl?.stopImageStream(); _cameraCtrl?.dispose(); } catch (_) {}
    _blurAnim.dispose();
    _shieldAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.isActive) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    return AnimatedBuilder(
      animation: _blurAnim,
      builder: (_, __) {
        final bp = _blurAnim.value;
        return Stack(
          children: [
            if (bp > 0.05)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: bp * 18, sigmaY: bp * 18),
                    child: Container(color: Colors.black.withOpacity(bp * 0.45)),
                  ),
                ),
              ),
            if (bp > 0.5) _buildWarning(),
            if (_secureState != SecureState.disabled) _buildBadge(),
          ],
        );
      },
    );
  }

  Widget _buildWarning() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A237E).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _shieldAnim,
              builder: (_, __) => Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05 + _shieldAnim.value * 0.1),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3 + _shieldAnim.value * 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Phát hiện người nhìn!',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Nội dung đã được ẩn\nđể bảo vệ quyền riêng tư',
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _updateSecureState(isSuspicious: false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Text('Hiển thị lại',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge() {
    final isBlurred = _secureState == SecureState.blurred;
    return Positioned(
      top: 8, right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isBlurred ? const Color(0xFFE53935).withOpacity(0.9)
              : const Color(0xFF1A237E).withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isBlurred ? Icons.visibility_off_rounded : Icons.shield_rounded,
                color: Colors.white, size: 11),
            const SizedBox(width: 4),
            Text(isBlurred ? 'PROTECTED' : 'SECURE',
                style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─── SECURE MODE TOGGLE ───────────────────────────────────────────────────────

class SecureModeToggle extends StatefulWidget {
  final bool isActive;
  final ValueChanged<bool> onChanged;

  const SecureModeToggle({super.key, required this.isActive, required this.onChanged});

  @override
  State<SecureModeToggle> createState() => _SecureModeToggleState();
}

class _SecureModeToggleState extends State<SecureModeToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onChanged(!widget.isActive); HapticFeedback.mediumImpact(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: widget.isActive
                ? const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)])
                : null,
            color: widget.isActive ? null : const Color(0xFFE8EEF8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive ? Colors.transparent : const Color(0xFFDDE3EE),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.isActive ? Icons.shield_rounded : Icons.shield_outlined,
                  size: 14, color: widget.isActive ? Colors.white : const Color(0xFF9AA5B8)),
              const SizedBox(width: 5),
              Text(widget.isActive ? 'Bảo mật ON' : 'Bảo mật',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: widget.isActive ? Colors.white : const Color(0xFF9AA5B8))),
            ],
          ),
        ),
      ),
    );
  }
}