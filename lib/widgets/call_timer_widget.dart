import 'dart:async';

import 'package:flutter/material.dart';

class CallTimerWidget extends StatefulWidget {
  final DateTime startTime;
  final TextStyle? style;

  const CallTimerWidget({
    super.key,
    required this.startTime,
    this.style,
  });

  @override
  State<CallTimerWidget> createState() => _CallTimerWidgetState();
}

class _CallTimerWidgetState extends State<CallTimerWidget> {
  late Duration _elapsed;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.startTime);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${_pad(m)}:${_pad(s)}';
    }
    return '${_pad(m)}:${_pad(s)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(_elapsed),
      style: widget.style ??
          const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}
