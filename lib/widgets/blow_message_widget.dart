import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';

class BlowMessageWidget extends StatefulWidget {
  final String secretText;
  const BlowMessageWidget({super.key, required this.secretText});

  @override
  State<BlowMessageWidget> createState() => _BlowMessageWidgetState();
}

class _BlowMessageWidgetState extends State<BlowMessageWidget> {
  bool _isRevealed = false;
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;

  @override
  void initState() {
    super.initState();
    _noiseMeter = NoiseMeter();
    _startListening();
  }

  void _startListening() {
    try {
      _noiseSubscription = _noiseMeter?.noise.listen((NoiseReading reading) {
        if (reading.maxDecibel > 85.0 && !_isRevealed) {
          setState(() => _isRevealed = true);
          _noiseSubscription?.cancel();
        }
      });
    } catch (e) {
      debugPrint("Lỗi Mic: $e");
    }
  }

  @override
  void dispose() {
    _noiseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.deepPurple, borderRadius: BorderRadius.circular(20)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(widget.secretText,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          if (!_isRevealed)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.white.withOpacity(0.2),
                  child: const Center(
                    child: Text("🌬️ Thổi vào Mic để xem",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
