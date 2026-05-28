import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';

// ─────────────────────────────────────────────────────────────
// CallListener
//
// Wrap your app's root widget with this to automatically handle
// incoming call notifications anywhere in the app.
//
// Usage:
//   MaterialApp(
//     home: CallListener(
//       child: MyHomePage(),
//     ),
//   );
// ─────────────────────────────────────────────────────────────

class CallListener extends StatefulWidget {
  final Widget child;

  /// Override user ID (useful if you manage auth outside Firebase Auth).
  /// When null, the listener auto-resolves from [FirebaseAuth].
  final String? currentUserId;

  const CallListener({
    super.key,
    required this.child,
    this.currentUserId,
  });

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener>
    with WidgetsBindingObserver {
  final _callService = CallService.instance;

  StreamSubscription<CallModel?>? _incomingCallSub;
  StreamSubscription<User?>? _authSub;

  String? _activeIncomingCallId;
  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.currentUserId != null) {
      _subscribeToIncomingCalls(widget.currentUserId!);
    } else {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _cancelIncomingSubscription();
        if (user != null) {
          _subscribeToIncomingCalls(user.uid);
        }
      });
    }
  }

  void _subscribeToIncomingCalls(String userId) {
    _incomingCallSub = _callService.incomingCallStream.listen((call) {
      if (call == null) return;

      // Deduplicate — same call can re-emit if Firestore updates
      if (call.callId == _activeIncomingCallId) return;

      // Don't show if we're already on a call page
      // (guard: check the call is truly incoming / ringing)
      if (!call.status.isActive) return;

      _activeIncomingCallId = call.callId;
      _showIncomingCall(call);
    });
  }

  void _cancelIncomingSubscription() {
    _incomingCallSub?.cancel();
    _incomingCallSub = null;
    _activeIncomingCallId = null;
  }

  void _showIncomingCall(CallModel call) {
    if (!mounted) return;

    // Find the root navigator so the incoming call overlays everything
    final navigator = Navigator.of(context, rootNavigator: true);

    navigator
        .push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        fullscreenDialog: true,
        pageBuilder: (_, __, ___) => IncomingCallPage(call: call),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 420),
      ),
    )
        .then((_) {
      // After the incoming call page dismisses, allow next call
      _activeIncomingCallId = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelIncomingSubscription();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
