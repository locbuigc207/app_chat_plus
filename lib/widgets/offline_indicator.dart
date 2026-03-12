import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/offline_manager.dart';

/// Widget hiển thị trạng thái offline
class OfflineIndicator extends StatefulWidget {
  final Widget child;

  const OfflineIndicator({
    super.key,
    required this.child,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  final OfflineManager _offlineManager = OfflineManager();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _offlineManager.onlineStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isOnline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.orange,
              elevation: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'You are offline. Messages will be sent when connection is restored.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
