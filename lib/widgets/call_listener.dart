import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';

/// Wraps any widget tree and automatically shows [IncomingCallPage] whenever
/// an incoming call arrives for the current user.
///
/// Usage:
///   // Option A – let the widget resolve the user from FirebaseAuth:
///   CallListener(child: MyApp())
///
///   // Option B – pass the userId explicitly (e.g. from a provider):
///   CallListener(currentUserId: uid, child: MyApp())
class CallListener extends StatefulWidget {
  final Widget child;

  /// Optional. When provided the listener uses this id directly and skips
  /// the FirebaseAuth subscription.
  final String? currentUserId;

  const CallListener({
    super.key,
    required this.child,
    this.currentUserId,
  });

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  final _callService = CallService();

  StreamSubscription? _incomingCallSub;
  StreamSubscription? _authSub;
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();

    if (widget.currentUserId != null) {
      // Option B: userId provided directly – start listening immediately.
      _subscribeToIncomingCalls(widget.currentUserId!);
    } else {
      // Option A: resolve userId from FirebaseAuth, re-subscribe on auth changes.
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _incomingCallSub?.cancel();
        _incomingCallSub = null;
        _activeIncomingCallId = null;

        if (user != null) {
          _subscribeToIncomingCalls(user.uid);
        }
      });
    }
  }

  void _subscribeToIncomingCalls(String userId) {
    _incomingCallSub = _callService.incomingCallStream.listen((call) {
      if (call == null) return;
      // Ignore if we're already showing this call.
      if (call.callId == _activeIncomingCallId) return;

      _activeIncomingCallId = call.callId;
      _showIncomingCall(call);
    });
  }

  void _showIncomingCall(CallModel call) {
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true)
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
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
