// lib/widgets/call_listener.dart
//
// Wrap your app's home widget (or MaterialApp) with this
// to automatically handle incoming calls.
//
// Usage in main.dart:
//   home: CallListener(
//     child: BubbleManager(
//       child: MiniChatOverlayManager(
//         child: AppInitializer(...)
//       ),
//     ),
//   ),

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';

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
    // Small delay so Navigator is ready
    Future.delayed(const Duration(milliseconds: 500), _startListening);
  }

  void _startListening() {
    _incomingCallSub = _callService.incomingCallStream.listen((call) {
      if (call == null) return;
      if (call.callId == _activeIncomingCallId) return; // already showing

      _activeIncomingCallId = call.callId;
      _showIncomingCall(call);
    });
  }

  void _showIncomingCall(CallModel call) {
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
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
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
