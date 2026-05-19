import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../pages/incoming_call_page.dart';
import '../services/call_service.dart';










class CallListener extends StatefulWidget {
  final Widget child;

  
  
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
      
      _subscribeToIncomingCalls(widget.currentUserId!);
    } else {
      
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
