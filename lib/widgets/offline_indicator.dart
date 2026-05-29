import 'dart:async';

import 'package:flutter/material.dart';

import 'package:connectivity_plus/connectivity_plus.dart';




class OfflineIndicator extends StatefulWidget {
  const OfflineIndicator({super.key});

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _heightAnim;
  late Animation<double> _fadeAnim;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  _BannerState _bannerState = _BannerState.hidden;
  Timer? _recoveryTimer;

  static const Duration _animDuration = Duration(milliseconds: 350);
  static const Duration _recoveryDisplay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(vsync: this, duration: _animDuration);
    _heightAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _sub = Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);

    
    Connectivity().checkConnectivity().then((results) {
      if (mounted) _applyConnectivity(results);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recoveryTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (!mounted) return;
    _applyConnectivity(results);
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (!isOnline) {
      _recoveryTimer?.cancel();
      _show(_BannerState.offline);
    } else if (_bannerState == _BannerState.offline) {
      _show(_BannerState.recovering);
      _recoveryTimer = Timer(_recoveryDisplay, () {
        if (mounted) _hide();
      });
    }
    
  }

  void _show(_BannerState state) {
    setState(() => _bannerState = state);
    _ctrl.forward();
  }

  void _hide() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _bannerState = _BannerState.hidden);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerState == _BannerState.hidden) return const SizedBox.shrink();

    final isOffline = _bannerState == _BannerState.offline;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SizeTransition(
        sizeFactor: _heightAnim,
        axisAlignment: -1,
        child: _BannerContent(isOffline: isOffline),
      ),
    );
  }
}





class _BannerContent extends StatelessWidget {
  final bool isOffline;
  const _BannerContent({required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
      decoration: BoxDecoration(
        gradient: isOffline
            ? const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              )
            : const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
        boxShadow: [
          BoxShadow(
            color: (isOffline ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                .withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AnimatedStatusIcon(isOffline: isOffline),
          const SizedBox(width: 8),
          Text(
            isOffline ? 'Không có kết nối mạng' : 'Đã kết nối lại',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          if (isOffline) ...[
            const SizedBox(width: 10),
            _RetryDots(),
          ],
        ],
      ),
    );
  }
}





class _AnimatedStatusIcon extends StatefulWidget {
  final bool isOffline;
  const _AnimatedStatusIcon({required this.isOffline});

  @override
  State<_AnimatedStatusIcon> createState() => _AnimatedStatusIconState();
}

class _AnimatedStatusIconState extends State<_AnimatedStatusIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedStatusIcon old) {
    super.didUpdateWidget(old);
    if (old.isOffline != widget.isOffline) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Icon(
        widget.isOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}





class _RetryDots extends StatefulWidget {
  @override
  State<_RetryDots> createState() => _RetryDotsState();
}

class _RetryDotsState extends State<_RetryDots> with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];
  final List<Animation<double>> _anims = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true, period: const Duration(milliseconds: 900));

      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) ctrl.forward();
      });

      _ctrls.add(ctrl);
      _anims.add(Tween<double>(begin: 0.3, end: 1.0)
          .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut)));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: _anims[i].value),
            ),
          ),
        );
      }),
    );
  }
}





enum _BannerState { hidden, offline, recovering }
