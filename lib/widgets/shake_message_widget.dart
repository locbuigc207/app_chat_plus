import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeMessageWidget extends StatefulWidget {
  final String secretText;
  const ShakeMessageWidget({super.key, required this.secretText});

  @override
  State<ShakeMessageWidget> createState() => _ShakeMessageWidgetState();
}

class _ShakeMessageWidgetState extends State<ShakeMessageWidget> {
  bool _isRevealed = false;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;

  @override
  void initState() {
    super.initState();
    _accelSubscription =
        userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      // Tính vector gia tốc, nếu > 15 thì coi là lắc mạnh
      double acceleration = event.x.abs() + event.y.abs() + event.z.abs();
      if (acceleration > 15.0 && !_isRevealed) {
        setState(() => _isRevealed = true);
        _accelSubscription?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
          color: Colors.orangeAccent, borderRadius: BorderRadius.circular(20)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _isRevealed
            ? Text(widget.secretText,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold))
            : const Column(
                children: [
                  Icon(Icons.card_giftcard, color: Colors.white, size: 40),
                  SizedBox(height: 8),
                  Text("Lắc máy để mở quà!",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }
}
