// lib/widgets/group_call_listener.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/group_call_model.dart';
import '../pages/incoming_group_call_page.dart';
import '../providers/auth_provider.dart';
import '../services/group_call_service.dart';

/// Wrap around CallListener in main.dart to handle incoming group calls
class GroupCallListener extends StatefulWidget {
  final Widget child;
  const GroupCallListener({super.key, required this.child});

  @override
  State<GroupCallListener> createState() => _GroupCallListenerState();
}

class _GroupCallListenerState extends State<GroupCallListener> {
  final _service = GroupCallService();
  StreamSubscription? _sub;
  String? _activeCallId;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), _startListening);
  }

  void _startListening() {
    final uid = context.read<AuthProvider>().userFirebaseId;
    if (uid == null || uid.isEmpty) return;

    _sub = _service.incomingGroupCallStream(uid).listen((call) {
      if (call == null) return;
      if (call.callId == _activeCallId) return;
      _activeCallId = call.callId;
      _showIncoming(call, uid);
    });
  }

  void _showIncoming(GroupCallModel call, String currentUserId) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
