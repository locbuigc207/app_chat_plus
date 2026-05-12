// lib/widgets/call_listener.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'; // Thêm dòng này
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
  StreamSubscription? _authSub; // Thêm biến này
  String? _activeIncomingCallId;

  @override
  void initState() {
    super.initState();
    // Lắng nghe sự thay đổi trạng thái đăng nhập
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Hủy lắng nghe cũ (nếu có)
      _incomingCallSub?.cancel();

      // Nếu user đã đăng nhập, bắt đầu lắng nghe cuộc gọi tới
      if (user != null) {
        _incomingCallSub = _callService.incomingCallStream.listen((call) {
          if (call == null) return;
          if (call.callId == _activeIncomingCallId) return;

          _activeIncomingCallId = call.callId;
          _showIncomingCall(call);
        });
      }
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
    _authSub?.cancel(); // Đừng quên cancel authSub
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
