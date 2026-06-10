// lib/widgets/deepfake_alert_overlay.dart
import 'package:flutter/material.dart';

import '../models/deepfake_models.dart';
import '../services/deepfake_detector_service.dart';

class DeepfakeStatusBadge extends StatelessWidget {
  const DeepfakeStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeepfakeAnalysisResult>(
      stream: DeepfakeDetectorService().resultStream,
      builder: (context, snap) {
        final result = snap.data;
        final status = DeepfakeDetectorService().currentEnrollmentStatus;

        if (status == EnrollmentStatus.enrolling) {
          return const _EnrollmentIndicator();
        }
        if (result == null || !result.isLikelyDeepfake) {
          return const _SafeBadge();
        }
        return _AlertBadge(result: result);
      },
    );
  }
}

class _EnrollmentIndicator extends StatefulWidget {
  const _EnrollmentIndicator();
  @override
  State<_EnrollmentIndicator> createState() => _EnrollmentIndicatorState();
}

class _EnrollmentIndicatorState extends State<_EnrollmentIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade300.withOpacity(0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.rotate(
            angle: _ctrl.value * 2 * 3.14159,
            child: Icon(Icons.graphic_eq_rounded,
                color: Colors.blue.shade300, size: 14),
          ),
        ),
        const SizedBox(width: 6),
        Text('Học giọng nói...',
            style: TextStyle(
                color: Colors.blue.shade200,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _SafeBadge extends StatelessWidget {
  const _SafeBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade400.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_user_rounded,
            color: Colors.green.shade400, size: 13),
        const SizedBox(width: 5),
        Text('Giọng thật',
            style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  final DeepfakeAnalysisResult result;
  const _AlertBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final isHighConfidence = result.isHighConfidence;
    final color =
        isHighConfidence ? Colors.red.shade400 : Colors.orange.shade400;

    return GestureDetector(
      onTap: () => _showDetailSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.8), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.psychology_alt_rounded, color: color, size: 14),
          const SizedBox(width: 5),
          Text(isHighConfidence ? 'DEEPFAKE!' : 'Nghi ngờ AI',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DeepfakeDetailSheet(result: result),
    );
  }
}

class DeepfakeDetailSheet extends StatelessWidget {
  final DeepfakeAnalysisResult result;
  const DeepfakeDetailSheet({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.psychology_alt_rounded,
                  color: result.isHighConfidence ? Colors.red : Colors.orange,
                  size: 24),
              const SizedBox(width: 10),
              Text(
                  result.isHighConfidence
                      ? 'Cảnh báo Deepfake'
                      : 'Nghi ngờ Deepfake',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            Text('Mức độ tin cậy: ${(result.confidenceScore * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            LinearProgressIndicator(
                value: result.confidenceScore,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(
                    result.isHighConfidence ? Colors.red : Colors.orange),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 16),
            if (result.signals.isNotEmpty) ...[
              const Text('Dấu hiệu phát hiện:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: result.signals
                      .map((s) => _SignalChip(signal: s))
                      .toList()),
              const SizedBox(height: 12),
            ],
            if (result.explanation.isNotEmpty)
              Text(result.explanation,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 12, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54),
                      child: const Text('Bỏ qua'))),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700),
                      child: const Text('Tắt máy'))),
            ]),
          ]),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final DeepfakeSignal signal;
  const _SignalChip({required this.signal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3))),
      child: Text(_label,
          style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
    );
  }

  String get _label {
    switch (signal) {
      case DeepfakeSignal.pitchAnomalous:
        return 'Pitch bất thường';
      case DeepfakeSignal.spectralFlat:
        return 'Thiếu texture âm';
      case DeepfakeSignal.pauseUnnatural:
        return 'Ngừng nghỉ cứng';
      case DeepfakeSignal.backgroundArtifact:
        return 'Nhiễu nền nhân tạo';
      case DeepfakeSignal.voiceprintMismatch:
        return 'Đổi giọng nói';
      default:
        return signal.name;
    }
  }
}
