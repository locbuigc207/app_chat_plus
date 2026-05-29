// lib/utils/safe_state_mixin.dart
//
// Mixin dùng chung để tránh lỗi "setState() called after dispose()"
// trong toàn bộ dự án.
//
// Sử dụng:
//   class _MyState extends State<MyWidget> with SafeStateMixin<MyWidget> {
//     Future<void> _load() async {
//       final data = await fetch();
//       safeSetState(() => _data = data);
//     }
//   }

import 'package:flutter/material.dart';

/// Mixin cung cấp [safeSetState] và tự động đặt disposed flag.
///
/// Giải quyết lỗi:
///   `setState() called after dispose(): _SomeState#xxxxx(lifecycle state: defunct, not mounted)`
///
/// Nguyên nhân: Future async callback gọi setState() sau khi widget đã bị
/// remove khỏi widget tree (user navigate away, tab change, v.v.).
mixin SafeStateMixin<T extends StatefulWidget> on State<T> {
  bool _safeDisposed = false;

  /// Trả về true nếu State đã bị dispose.
  bool get isDisposed => _safeDisposed;

  @override
  void dispose() {
    _safeDisposed = true; // PHẢI đặt TRƯỚC super.dispose()
    super.dispose();
  }

  /// Gọi setState() an toàn: chỉ thực thi nếu widget vẫn còn mounted.
  ///
  /// Dùng thay cho setState() trong mọi async callback, timer, stream listener.
  void safeSetState(VoidCallback fn) {
    if (!_safeDisposed && mounted) {
      setState(fn);
    }
  }

  /// Thực thi callback chỉ khi mounted (không gọi setState).
  /// Dùng cho ScaffoldMessenger, Navigator, v.v.
  void ifMounted(VoidCallback fn) {
    if (!_safeDisposed && mounted) fn();
  }
}
