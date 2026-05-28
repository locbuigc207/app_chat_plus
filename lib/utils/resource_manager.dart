// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ResourceManager
// Quản lý toàn diện vòng đời tài nguyên: StreamSubscription, Timer,
// AnimationController, TextEditingController, ScrollController, FocusNode,
// ChangeNotifier, custom disposers.
// ─────────────────────────────────────────────────────────────────────────────

class ResourceManager {
  // ── Internal lists ─────────────────────────────────────────────────────────
  final List<_SubEntry> _subscriptions = [];
  final List<_TimerEntry> _timers = [];
  final List<_DisposerEntry> _disposers = [];

  bool _isDisposed = false;
  String? _debugName;

  // ── Constructor ─────────────────────────────────────────────────────────────

  ResourceManager({String? debugName}) : _debugName = debugName;

  // ── Subscription management ─────────────────────────────────────────────────

  /// Đăng ký một StreamSubscription để tự động hủy khi dispose.
  StreamSubscription<T> addSubscription<T>(
    StreamSubscription<T> sub, {
    String? tag,
  }) {
    if (_isDisposed) {
      sub.cancel();
      return sub;
    }
    _subscriptions.add(_SubEntry(sub, tag: tag));
    return sub;
  }

  /// Lắng nghe một Stream và tự quản lý subscription.
  StreamSubscription<T> listen<T>(
    Stream<T> stream,
    void Function(T data) onData, {
    Function? onError,
    void Function()? onDone,
    bool cancelOnError = false,
    String? tag,
  }) {
    final sub = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return addSubscription(sub, tag: tag);
  }

  /// Hủy subscription theo tag.
  Future<void> cancelSubscription(String tag) async {
    final entries = _subscriptions.where((e) => e.tag == tag).toList();
    for (final e in entries) {
      _subscriptions.remove(e);
      try {
        await e.sub.cancel();
      } catch (_) {}
    }
  }

  // ── Timer management ────────────────────────────────────────────────────────

  /// Đăng ký một Timer để tự động hủy khi dispose.
  Timer addTimer(Timer timer, {String? tag}) {
    if (_isDisposed) {
      timer.cancel();
      return timer;
    }
    _timers.add(_TimerEntry(timer, tag: tag));
    return timer;
  }

  /// Tạo Timer.periodic và tự quản lý.
  Timer addPeriodicTimer(
    Duration period,
    void Function(Timer) callback, {
    String? tag,
  }) =>
      addTimer(Timer.periodic(period, callback), tag: tag);

  /// Tạo Timer một lần và tự quản lý.
  Timer addDelayedTimer(
    Duration delay,
    VoidCallback callback, {
    String? tag,
  }) =>
      addTimer(Timer(delay, callback), tag: tag);

  /// Hủy timer theo tag.
  void cancelTimer(String tag) {
    final entries = _timers.where((e) => e.tag == tag).toList();
    for (final e in entries) {
      _timers.remove(e);
      try {
        e.timer.cancel();
      } catch (_) {}
    }
  }

  // ── Disposer management ─────────────────────────────────────────────────────

  /// Thêm custom disposer callback.
  void addDisposer(VoidCallback disposer, {String? tag}) {
    if (_isDisposed) {
      try {
        disposer();
      } catch (_) {}
      return;
    }
    _disposers.add(_DisposerEntry(disposer, tag: tag));
  }

  // ── Convenience helpers ──────────────────────────────────────────────────────

  /// Quản lý ChangeNotifier (gọi dispose khi rm.dispose).
  void addNotifier(ChangeNotifier notifier, {String? tag}) =>
      addDisposer(notifier.dispose, tag: tag);

  /// Quản lý TextEditingController.
  void addController(TextEditingController controller, {String? tag}) =>
      addDisposer(controller.dispose, tag: tag);

  /// Quản lý AnimationController.
  void addAnimationController(AnimationController controller, {String? tag}) =>
      addDisposer(controller.dispose, tag: tag);

  /// Quản lý ScrollController.
  void addScrollController(ScrollController controller, {String? tag}) =>
      addDisposer(controller.dispose, tag: tag);

  /// Quản lý FocusNode.
  void addFocusNode(FocusNode node, {String? tag}) =>
      addDisposer(node.dispose, tag: tag);

  /// Quản lý Disposable.
  void addDisposable(Disposable disposable, {String? tag}) =>
      addDisposer(disposable.dispose, tag: tag);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Hủy tất cả tài nguyên theo thứ tự: subscriptions → timers → disposers.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    _debugLog('Disposing...');

    // Cancel all subscriptions
    final subs = List.of(_subscriptions);
    _subscriptions.clear();
    for (final e in subs) {
      try {
        await e.sub.cancel();
      } catch (err) {
        _debugLog('Error canceling subscription [${e.tag}]: $err');
      }
    }

    // Cancel all timers
    final timers = List.of(_timers);
    _timers.clear();
    for (final e in timers) {
      try {
        e.timer.cancel();
      } catch (err) {
        _debugLog('Error canceling timer [${e.tag}]: $err');
      }
    }

    // Run all disposers in reverse order
    final disposers = List.of(_disposers).reversed.toList();
    _disposers.clear();
    for (final e in disposers) {
      try {
        e.disposer();
      } catch (err) {
        _debugLog('Error in disposer [${e.tag}]: $err');
      }
    }

    _debugLog('Disposed.');
  }

  // ── State getters ────────────────────────────────────────────────────────────

  bool get isDisposed => _isDisposed;
  int get subscriptionCount => _subscriptions.length;
  int get timerCount => _timers.length;
  int get disposerCount => _disposers.length;

  // ── Debug ────────────────────────────────────────────────────────────────────

  void _debugLog(String msg) {
    if (kDebugMode) {
      final name = _debugName != null ? '[$_debugName] ' : '';
      debugPrint('🔧 ResourceManager ${name}$msg');
    }
  }

  @override
  String toString() => 'ResourceManager('
      'name: $_debugName, '
      'disposed: $_isDisposed, '
      'subs: ${_subscriptions.length}, '
      'timers: ${_timers.length}, '
      'disposers: ${_disposers.length}'
      ')';
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry helpers (private)
// ─────────────────────────────────────────────────────────────────────────────

class _SubEntry {
  final StreamSubscription sub;
  final String? tag;
  const _SubEntry(this.sub, {this.tag});
}

class _TimerEntry {
  final Timer timer;
  final String? tag;
  const _TimerEntry(this.timer, {this.tag});
}

class _DisposerEntry {
  final VoidCallback disposer;
  final String? tag;
  const _DisposerEntry(this.disposer, {this.tag});
}

// ─────────────────────────────────────────────────────────────────────────────
// Mixin: ResourceManagerMixin
// Dành cho State<T extends StatefulWidget>
// ─────────────────────────────────────────────────────────────────────────────

mixin ResourceManagerMixin<T extends StatefulWidget> on State<T> {
  late final ResourceManager _resourceManager =
      ResourceManager(debugName: T.toString());

  /// Truy cập ResourceManager.
  ResourceManager get resourceManager => _resourceManager;

  @override
  void dispose() {
    _resourceManager.dispose();
    super.dispose();
  }

  // ── Shortcuts ────────────────────────────────────────────────────────────────

  StreamSubscription<E> listenStream<E>(
    Stream<E> stream,
    void Function(E data) onData, {
    Function? onError,
    void Function()? onDone,
    String? tag,
  }) =>
      _resourceManager.listen(
        stream,
        onData,
        onError: onError,
        onDone: onDone,
        tag: tag,
      );

  Timer addTimer(Timer timer, {String? tag}) =>
      _resourceManager.addTimer(timer, tag: tag);

  Timer periodicTimer(
    Duration period,
    void Function(Timer) callback, {
    String? tag,
  }) =>
      _resourceManager.addPeriodicTimer(period, callback, tag: tag);

  Timer delayedTimer(
    Duration delay,
    VoidCallback callback, {
    String? tag,
  }) =>
      _resourceManager.addDelayedTimer(delay, callback, tag: tag);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mixin: ResourceManagerNotifierMixin
// Dành cho ChangeNotifier (Provider, ViewModel...)
// ─────────────────────────────────────────────────────────────────────────────

mixin ResourceManagerNotifierMixin on ChangeNotifier {
  late final ResourceManager _resourceManager =
      ResourceManager(debugName: runtimeType.toString());

  ResourceManager get resourceManager => _resourceManager;

  @override
  void dispose() {
    _resourceManager.dispose();
    super.dispose();
  }

  StreamSubscription<T> listenStream<T>(
    Stream<T> stream,
    void Function(T data) onData, {
    Function? onError,
    String? tag,
  }) =>
      _resourceManager.listen(
        stream,
        onData,
        onError: onError,
        tag: tag,
      );

  Timer addTimer(Timer timer, {String? tag}) =>
      _resourceManager.addTimer(timer, tag: tag);

  Timer periodicTimer(
    Duration period,
    void Function(Timer) callback, {
    String? tag,
  }) =>
      _resourceManager.addPeriodicTimer(period, callback, tag: tag);

  Timer delayedTimer(
    Duration delay,
    VoidCallback callback, {
    String? tag,
  }) =>
      _resourceManager.addDelayedTimer(delay, callback, tag: tag);
}

// ─────────────────────────────────────────────────────────────────────────────
// Disposable interface
// ─────────────────────────────────────────────────────────────────────────────

abstract interface class Disposable {
  void dispose();
}

extension DisposableExtension on ResourceManager {
  void addDisposableObject(Disposable d) => addDisposer(d.dispose);
}

// ─────────────────────────────────────────────────────────────────────────────
// ManagedValueNotifier<T>
// ValueNotifier tự động dispose thông qua ResourceManager
// ─────────────────────────────────────────────────────────────────────────────

class ManagedValueNotifier<T> extends ValueNotifier<T> {
  ManagedValueNotifier(super.value);

  /// Đăng ký vào ResourceManager để tự dispose.
  void attachTo(ResourceManager rm, {String? tag}) =>
      rm.addDisposer(dispose, tag: tag);
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoDisposeStream – wrapper tiện lợi cho stream với tự dispose
// ─────────────────────────────────────────────────────────────────────────────

class AutoDisposeStream<T> implements Disposable {
  StreamSubscription<T>? _subscription;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  AutoDisposeStream(Stream<T> source) {
    _subscription = source.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  Stream<T> get stream => _controller.stream;

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
