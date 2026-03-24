// lib/pages/outgoing_call_page.dart
//
// This page is shown immediately after initiating a call,
// while waiting for the remote party to answer.
// It transitions to CallPage when connected.

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';
import 'call_page.dart';

class OutgoingCallPage extends StatefulWidget {
  final CallModel call;

  const OutgoingCallPage({super.key, required this.call});

  @override
  State<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends State<OutgoingCallPage>
    with SingleTickerProviderStateMixin {
  final _callService = CallService();
  StreamSubscription? _callStatusSub;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _watchCallStatus();
  }

  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || !mounted) return;

      switch (call.status) {
        case CallStatus.connected:
          _callStatusSub?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => CallPage(
                call: call,
                isOutgoing: true,
              ),
            ),
          );
          break;
        case CallStatus.declined:
          _showEndDialog(
              'Call Declined', '${widget.call.calleeName} declined the call.');
          break;
        case CallStatus.missed:
          _showEndDialog(
              'No Answer', '${widget.call.calleeName} did not answer.');
          break;
        case CallStatus.failed:
          _showEndDialog('Call Failed', 'Could not connect the call.');
          break;
        default:
          break;
      }
    });
  }

  void _showEndDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              Navigator.of(context).pop(); // close outgoing page
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelCall() async {
    await _callService.endCall(widget.call.callId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _callStatusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.isVideoCall;
    final name = widget.call.calleeName;
    final avatar = widget.call.calleeAvatar;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isVideo
                ? [const Color(0xFF0f3460), const Color(0xFF16213e)]
                : [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Call type ────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.phone,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isVideo ? 'Video Calling…' : 'Voice Calling…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Animated avatar ──────────────────────
              _AnimatedAvatar(
                controller: _waveController,
                avatarUrl: avatar,
                name: name,
              ),

              const SizedBox(height: 32),

              // ── Name ─────────────────────────────────
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // ── Status ───────────────────────────────
              _RingingDotsText(label: 'Ringing'),

              const Spacer(),

              // ── Cancel button ────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _cancelCall,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE53935).withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.call_end,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated avatar with wave rings ──────────────────────────
class _AnimatedAvatar extends StatelessWidget {
  final Animation<double> controller;
  final String avatarUrl;
  final String name;

  const _AnimatedAvatar({
    required this.controller,
    required this.avatarUrl,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Wave rings
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final progress = (controller.value + (i * 0.33)) % 1.0;
              return Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: Container(
                  width: 110 + (progress * 90),
                  height: 110 + (progress * 90),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            },
          );
        }),

        // Avatar
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: ClipOval(
            child: avatarUrl.isNotEmpty
                ? Image.network(avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultAvatar())
                : _defaultAvatar(),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar() {
    return Container(
      color: Colors.blueGrey[700],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Animated ringing dots ──────────────────────────────────
class _RingingDotsText extends StatefulWidget {
  final String label;
  const _RingingDotsText({required this.label});

  @override
  State<_RingingDotsText> createState() => _RingingDotsTextState();
}

class _RingingDotsTextState extends State<_RingingDotsText> {
  int _dots = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.label}${'.' * _dots}',
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontSize: 16,
        letterSpacing: 1,
      ),
    );
  }
}
