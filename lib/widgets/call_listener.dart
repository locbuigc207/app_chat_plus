// lib/widgets/call_listener.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';

/// Wrap app home để tự động bắt incoming calls
///
/// Dùng trong main.dart:
///   home: CallListener(
///     child: BubbleManager(
///       child: AppInitializer(...),
///     ),
///   ),
class CallListener extends StatefulWidget {
  final Widget child;

  const CallListener({super.key, required this.child});

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  final _callService = CallService();
  StreamSubscription? _incomingCallSub;
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    // Delay nhỏ để Navigator ready
    Future.delayed(const Duration(milliseconds: 800), _startListening);
  }

  void _startListening() {
    if (!mounted) return;

    _incomingCallSub = _callService.incomingCallStream.listen((call) {
      if (call == null) return;
      if (call.callId == _activeIncomingCallId) return; // Đã hiển thị

      _activeIncomingCallId = call.callId;
      _showIncomingCall(call);
    });
  }

  void _showIncomingCall(CallModel call) {
    if (!mounted) return;

    final nav = Navigator.of(context, rootNavigator: true);
    nav
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierDismissible: false,
            pageBuilder: (_, __, ___) => IncomingCallPage(call: call),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        )
        .then((_) => _activeIncomingCallId = null);
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
