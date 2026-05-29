import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:geolocator/geolocator.dart';




class GeoLockedMessageWidget extends StatefulWidget {
  final String content;
  final bool isMe;

  const GeoLockedMessageWidget({
    super.key,
    required this.content,
    required this.isMe,
  });

  @override
  State<GeoLockedMessageWidget> createState() => _GeoLockedMessageWidgetState();
}

class _GeoLockedMessageWidgetState extends State<GeoLockedMessageWidget>
    with SingleTickerProviderStateMixin {
  bool _isUnlocked = false;
  bool _isLoading = false;
  String _distanceText = "Chạm để kiểm tra khoảng cách";

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    
    if (widget.isMe) {
      _isUnlocked = true;
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  
  
  
  Future<bool> _handlePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _distanceText = "GPS đang tắt. Vui lòng bật định vị!");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _distanceText = "Quyền định vị bị từ chối.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(
        () => _distanceText = "Quyền định vị bị chặn vĩnh viễn. Vào Cài đặt để cấp quyền.",
      );
      return false;
    }

    return true;
  }

  Future<void> _checkLocation(double targetLat, double targetLng) async {
    if (_isUnlocked || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final hasPermission = await _handlePermission();
      if (!hasPermission) {
        setState(() => _isLoading = false);
        return;
      }

      
      final LocationSettings locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      final double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      if (distanceInMeters <= 50.0) {
        setState(() => _isUnlocked = true);
      } else {
        final int dist = distanceInMeters.round();
        setState(
          () => _distanceText = "Bạn cách ${dist}m. Cần đến gần hơn (<50m) để mở khóa!",
        );
        _shakeController.forward(from: 0);
      }
    } on LocationServiceDisabledException {
      setState(() => _distanceText = "Dịch vụ GPS chưa được bật.");
      _shakeController.forward(from: 0);
    } on PermissionDeniedException catch (e) {
      setState(() => _distanceText = "Thiếu quyền định vị: ${e.message}");
      _shakeController.forward(from: 0);
    } catch (e) {
      setState(() => _distanceText = "Lỗi không xác định. Thử lại sau.");
      _shakeController.forward(from: 0);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  
  
  
  Widget _buildUnlocked(String secretText) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xFF1976D2) : Colors.green.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on,
            color: widget.isMe ? Colors.white70 : Colors.green.shade700,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              secretText,
              style: TextStyle(
                color: widget.isMe ? Colors.white : Colors.black87,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildLocked(double lat, double lng) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final offset = _shakeController.isAnimating ? _shakeAnimation.value : 0.0;
        return Transform.translate(
          offset: Offset(offset * (_shakeController.value < 0.5 ? 1 : -1), 0),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () => _checkLocation(lat, lng),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF37474F), Color(0xFF263238)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.pin_drop, color: Colors.amber, size: 44),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF263238),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.lock, color: Colors.amber, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "Tin nhắn ẩn theo tọa độ",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.amber,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : Text(
                      _distanceText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
              const SizedBox(height: 8),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}",
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  
  
  @override
  Widget build(BuildContext context) {
    late Map<String, dynamic> data;
    try {
      data = jsonDecode(widget.content) as Map<String, dynamic>;
    } catch (_) {
      return const Text(
        "⚠️ Nội dung tin nhắn không hợp lệ",
        style: TextStyle(color: Colors.red),
      );
    }

    final String secretText = (data['text'] as String?) ?? '';
    final double lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
    final double lng = (data['lng'] as num?)?.toDouble() ?? 0.0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _isUnlocked ? _buildUnlocked(secretText) : _buildLocked(lat, lng),
    );
  }
}
