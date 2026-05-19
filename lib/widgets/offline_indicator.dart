
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/offline_manager.dart';




class OfflineIndicator extends StatefulWidget {
  const OfflineIndicator({super.key});

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  final OfflineManager _offlineManager = OfflineManager();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    
    try {
      _offlineManager.onlineStream.listen((isOnline) {
        if (mounted) {
          setState(() => _isOnline = isOnline);
        }
      });
    } catch (e) {
      debugPrint("⚠️ Lỗi lắng nghe OfflineManager: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        
        final connectivityOffline = snapshot.hasData &&
            snapshot.data!.contains(ConnectivityResult.none);

        
        final showBanner = !_isOnline || connectivityOffline;

        if (!showBanner) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.orange.withOpacity(0.95),
          padding: const EdgeInsets.symmetric(
            vertical: 6,
            horizontal: 16,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off,
                color: Colors.white,
                size: 14,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đang ngoại tuyến. Tin nhắn sẽ tự động gửi khi có mạng.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
