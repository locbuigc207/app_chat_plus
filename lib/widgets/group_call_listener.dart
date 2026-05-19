
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:flutter/material.dart';

import '../models/group_call_model.dart';
import '../pages/incoming_group_call_page.dart';
import '../services/group_call_service.dart';

class GroupCallListener extends StatefulWidget {
  final Widget child;
  const GroupCallListener({super.key, required this.child});

  @override
  State<GroupCallListener> createState() => _GroupCallListenerState();
}

class _GroupCallListenerState extends State<GroupCallListener> {
  final _service = GroupCallService();
  StreamSubscription? _sub;
  StreamSubscription? _authSub; 
  String? _activeCallId;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      if (user != null) {
        _sub = _service.incomingGroupCallStream(user.uid).listen((call) {
          if (call == null) return;
          if (call.callId == _activeCallId) return;
          _activeCallId = call.callId;
          _showIncoming(call, user.uid);
        });
      }
    });
  }

  void _showIncoming(GroupCallModel call, String currentUserId) {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    nav
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierDismissible: false,
            pageBuilder: (_, __, ___) => IncomingGroupCallPage(
              call: call,
              currentUserId: currentUserId,
            ),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
        )
        .then((_) => _activeCallId = null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
