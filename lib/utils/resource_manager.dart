import 'dart:async';

import 'package:flutter/material.dart';


class ResourceManager {
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];
  final List<VoidCallback> _disposers = [];
  bool _isDisposed = false;

  
  void addSubscription(StreamSubscription subscription) {
    if (_isDisposed) {
      subscription.cancel();
      return;
    }
    _subscriptions.add(subscription);
  }

  
  void addTimer(Timer timer) {
    if (_isDisposed) {
      timer.cancel();
      return;
    }
    _timers.add(timer);
  }

  
  void addDisposer(VoidCallback disposer) {
    if (_isDisposed) {
      disposer();
      return;
    }
    _disposers.add(disposer);
  }

  
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    
    for (var subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (e) {
        debugPrint('Error canceling subscription: $e');
      }
    }
    _subscriptions.clear();

    
    for (var timer in _timers) {
      try {
        timer.cancel();
      } catch (e) {
        debugPrint('Error canceling timer: $e');
      }
    }
    _timers.clear();

    
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


mixin ResourceManagerMixin<T extends StatefulWidget> on State<T> {
  final ResourceManager _resourceManager = ResourceManager();

  ResourceManager get resourceManager => _resourceManager;

  @override
  void dispose() {
    _resourceManager.dispose();
    super.dispose();
  }
}
