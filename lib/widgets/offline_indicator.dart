// lib/widgets/offline_indicator.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/offline_manager.dart';

/// Widget hiển thị banner offline phía trên cùng.
/// Có thể đặt trực tiếp vào Column (như trong chat_page.dart).
/// Kết hợp cả hai nguồn: OfflineManager stream (Firestore) và Connectivity stream (Hệ thống mạng).
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
    // Lắng nghe từ OfflineManager (Trạng thái kết nối của Firestore)
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
    // Lắng nghe thêm từ connectivity_plus để bắt trạng thái mạng thiết bị (Wifi/4G)
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        // Kiểm tra xem thiết bị có thực sự mất toàn bộ mạng không
        final connectivityOffline = snapshot.hasData &&
            snapshot.data!.contains(ConnectivityResult.none);

        // Hiển thị banner cảnh báo nếu Firestore mất kết nối HOẶC thiết bị tắt mạng
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
