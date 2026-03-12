import 'dart:async';

import 'package:flutter/foundation.dart';

/// Quản lý lifecycle của resources để tránh memory leaks
class ResourceManager {
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];
  final List<VoidCallback> _disposers = [];
  bool _isDisposed = false;

  /// Add subscription để auto-cancel khi dispose
  void addSubscription(StreamSubscription subscription) {
    if (_isDisposed) {
      subscription.cancel();
      return;
    }
    _subscriptions.add(subscription);
  }

  /// Add timer để auto-cancel khi dispose
  void addTimer(Timer timer) {
    if (_isDisposed) {
      timer.cancel();
      return;
    }
    _timers.add(timer);
  }

  /// Add custom disposer
  void addDisposer(VoidCallback disposer) {
    if (_isDisposed) {
      disposer();
      return;
    }
    _disposers.add(disposer);
  }

  /// Dispose tất cả resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // Cancel all subscriptions
    for (var subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (e) {
        debugPrint('Error canceling subscription: $e');
      }
    }
    _subscriptions.clear();

    // Cancel all timers
    for (var timer in _timers) {
      try {
        timer.cancel();
      } catch (e) {
        debugPrint('Error canceling timer: $e');
      }
    }
    _timers.clear();

    // Call custom disposers
    for (var disposer in _disposers) {
      try {
        disposer();
      } catch (e) {
        debugPrint('Error calling disposer: $e');
      }
    }
    _disposers.clear();
  }

  bool get isDisposed => _isDisposed;
}

/// Mixin để tự động quản lý resources
mixin ResourceManagerMixin<T extends StatefulWidget> on State<T> {
  final ResourceManager _resourceManager = ResourceManager();

  ResourceManager get resourceManager => _resourceManager;

  @override
  void dispose() {
    _resourceManager.dispose();
    super.dispose();
  }
}
