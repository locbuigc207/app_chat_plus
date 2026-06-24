// lib/services/bubble_permission_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enum — khớp 1-1 với BubblePermissionChecker.Status.dartName bên Kotlin
// ─────────────────────────────────────────────────────────────────────────────

/// Trạng thái permission Bubble API.
/// Tên enum phải khớp chính xác với dartName trong BubblePermissionChecker.kt.
enum BubblePermissionStatus {
  /// Tất cả điều kiện đáp ứng — bubble sẽ hiển thị.
  fullySupported,

  /// Người dùng tắt thông báo — cần bật lại từ Settings.
  notificationDisabled,

  /// Notification channel chưa cho phép bubble (canBubble = false).
  /// Thường xảy ra sau lần cài đặt đầu tiên hoặc sau update hệ thống
  /// trên Samsung One UI 7.
  bubbleChannelDisabled,

  /// App đang bị giới hạn pin — FCM có thể không đến, bubble không trigger.
  /// Phổ biến trên Xiaomi HyperOS, Samsung, Vivo, Oppo.
  batteryNotWhitelisted,

  /// OEM chặn hoàn toàn — Huawei/Honor không có Google Mobile Services.
  /// Không thể khắc phục bằng user action.
  oemSystemBlocked,

  /// Không xác định được — thường là exception trong lúc check.
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension helpers
// ─────────────────────────────────────────────────────────────────────────────

extension BubblePermissionStatusX on BubblePermissionStatus {
  /// Trả về true nếu user có thể tự fix bằng cách vào Settings.
  bool get needsUserAction => switch (this) {
    BubblePermissionStatus.fullySupported => false,
    BubblePermissionStatus.oemSystemBlocked => false,
    BubblePermissionStatus.unknown => false,
    _ => true,
  };

  /// OEM chặn cứng — không có giải pháp programmatic.
  bool get isHardBlocked => this == BubblePermissionStatus.oemSystemBlocked;

  /// Bubble sẽ hoạt động.
  bool get isReady => this == BubblePermissionStatus.fullySupported;

  /// Mô tả ngắn gọn tiếng Việt cho log / debug.
  String get description => switch (this) {
    BubblePermissionStatus.fullySupported =>
      'Bong bóng chat hoạt động bình thường',
    BubblePermissionStatus.notificationDisabled => 'Thông báo bị tắt',
    BubblePermissionStatus.bubbleChannelDisabled =>
      'Channel chưa cho phép bong bóng',
    BubblePermissionStatus.batteryNotWhitelisted => 'App bị giới hạn nền (pin)',
    BubblePermissionStatus.oemSystemBlocked => 'OEM chặn hoàn toàn Bubble API',
    BubblePermissionStatus.unknown => 'Không xác định được trạng thái',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// BubblePermissionService
// ─────────────────────────────────────────────────────────────────────────────

/// Service tập trung toàn bộ logic kiểm tra và yêu cầu permission bubble.
///
/// Là singleton — dùng factory constructor hoặc [instance].
///
/// Tích hợp:
/// ```dart
/// // Trong AppInitializer, sau khi auth state có user:
/// await BubblePermissionService.instance.initialize();
///
/// // Khi user lần đầu bật bubble trong Settings của app:
/// final granted = await BubblePermissionService.instance
///     .requestIfNeeded(context);
///
/// // Trong AppInitializer.didChangeAppLifecycleState (resumed):
/// BubblePermissionService.instance.onAppResumed();
/// ```
class BubblePermissionService {
  BubblePermissionService._();

  static final BubblePermissionService instance = BubblePermissionService._();
  factory BubblePermissionService() => instance;

  // ── Channels ────────────────────────────────────────────────────────────
  static const _method = MethodChannel('chat_bubbles_v2');

  // ── State ────────────────────────────────────────────────────────────────
  BubblePermissionStatus _currentStatus = BubblePermissionStatus.unknown;
  bool _isInitialized = false;
  SharedPreferences? _prefs;

  /// Key lưu thời điểm user chọn "Để sau" — không hiện lại dialog trong 24h.
  static const _prefKeyDismissedAt = 'bubble_onboarding_dismissed_at';

  /// Key lưu số lần đã hiện onboarding — tránh spam user.
  static const _prefKeyShownCount = 'bubble_onboarding_shown_count';

  static const _maxOnboardingShows = 3;
  static const _dismissCooldown = Duration(hours: 24);

  // ── Stream ───────────────────────────────────────────────────────────────
  final StreamController<BubblePermissionStatus> _statusCtrl =
      StreamController<BubblePermissionStatus>.broadcast();

  /// Stream phát ra trạng thái permission mỗi khi thay đổi.
  /// UI widget có thể lắng nghe để cập nhật icon/badge.
  Stream<BubblePermissionStatus> get statusStream => _statusCtrl.stream;

  /// Trạng thái hiện tại (đồng bộ).
  BubblePermissionStatus get currentStatus => _currentStatus;

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALISATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Khởi tạo service, thực hiện check lần đầu và bắt đầu monitoring.
  /// Gọi một lần sau khi auth state có user.
  Future<void> initialize() async {
    if (_isInitialized || !Platform.isAndroid) return;

    _prefs ??= await SharedPreferences.getInstance();
    _isInitialized = true;

    // Check ngay lần đầu
    await refresh();

    debugPrint(
      '✅ BubblePermissionService initialized: '
      '${_currentStatus.description}',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHECK & REFRESH
  // ─────────────────────────────────────────────────────────────────────────

  /// Gọi Native để lấy trạng thái permission mới nhất.
  /// Cập nhật [currentStatus] và phát lên [statusStream].
  Future<BubblePermissionStatus> refresh() async {
    if (!Platform.isAndroid) return BubblePermissionStatus.unknown;

    try {
      final raw = await _method.invokeMethod<String>(
        'getBubblePermissionStatus',
      );
      final status = _parseStatus(raw);
      _updateStatus(status);
      return status;
    } on PlatformException catch (e) {
      debugPrint('❌ BubblePermissionService.refresh: ${e.message}');
      _updateStatus(BubblePermissionStatus.unknown);
      return BubblePermissionStatus.unknown;
    } catch (e) {
      debugPrint('❌ BubblePermissionService.refresh unexpected: $e');
      _updateStatus(BubblePermissionStatus.unknown);
      return BubblePermissionStatus.unknown;
    }
  }

  /// Kiểm tra nhanh chỉ channel canBubble — không cần round-trip đầy đủ.
  /// Dùng trong MainActivityonResume để detect Samsung permission reset.
  Future<bool> isChannelEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('checkBubblesEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REQUEST FLOW
  // ─────────────────────────────────────────────────────────────────────────

  /// Kiểm tra và yêu cầu permission nếu cần.
  ///
  /// Nếu permission đầy đủ: trả về true ngay.
  /// Nếu OEM chặn cứng: trả về false ngay (không hiện dialog).
  /// Nếu cần user action: hiện [BubbleOnboardingDialog] (import từ widgets).
  ///
  /// [onShowDialog] là callback để caller (thường là widget) tự hiển thị dialog.
  /// Pattern này tránh dependency circular giữa service và widget.
  ///
  /// ```dart
  /// final granted = await BubblePermissionService.instance.requestIfNeeded(
  ///   onShowDialog: (status, oemName, steps) async {
  ///     return await showDialog<bool>(
  ///       context: context,
  ///       builder: (_) => BubbleOnboardingDialog(
  ///         status: status,
  ///         oemName: oemName,
  ///         setupSteps: steps,
  ///       ),
  ///     ) ?? false;
  ///   },
  /// );
  /// ```
  Future<bool> requestIfNeeded({
    required Future<bool> Function(
      BubblePermissionStatus status,
      String oemName,
      List<String> setupSteps,
    )
    onShowDialog,
  }) async {
    if (!Platform.isAndroid) return false;
    if (!_isInitialized) await initialize();

    final status = await refresh();

    // Đã ok
    if (status.isReady) return true;

    // OEM chặn cứng — không hiện dialog vô ích
    if (status.isHardBlocked) return false;

    // User không cần action (unknown) — không làm phiền
    if (!status.needsUserAction) return false;

    // Kiểm tra cooldown "Để sau"
    if (_isInDismissCooldown()) {
      debugPrint('⏳ BubblePermission: trong cooldown 24h, bỏ qua dialog');
      return false;
    }

    // Kiểm tra đã hiện quá nhiều lần
    final shownCount = _prefs?.getInt(_prefKeyShownCount) ?? 0;
    if (shownCount >= _maxOnboardingShows) {
      debugPrint(
        '⚠️ BubblePermission: đã hiện onboarding $shownCount lần, bỏ qua',
      );
      return false;
    }

    // Lấy thông tin OEM và các bước hướng dẫn từ Native
    final oemName = await _getOemName();
    final setupSteps = await _getBubbleSetupSteps();

    // Tăng counter trước khi hiện dialog
    await _prefs?.setInt(_prefKeyShownCount, shownCount + 1);

    // Delegate việc hiện dialog về caller
    final userGranted = await onShowDialog(status, oemName, setupSteps);

    if (userGranted) {
      // User đã thao tác — refresh lại để xác nhận
      await Future.delayed(const Duration(milliseconds: 800));
      final newStatus = await refresh();
      return newStatus.isReady;
    } else {
      // User chọn "Để sau" — ghi cooldown
      await _markDismissed();
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE HOOKS
  // ─────────────────────────────────────────────────────────────────────────

  /// Gọi khi app resume về foreground.
  /// Samsung One UI 7 có thể reset bubble permission sau system update.
  Future<void> onAppResumed() async {
    if (!Platform.isAndroid || !_isInitialized) return;
    final status = await refresh();
    if (status != _currentStatus) {
      debugPrint(
        '🔄 BubblePermission changed on resume: ${status.description}',
      );
    }
  }

  /// Gọi khi nhận event "bubble_permission_lost" từ Native (MainActivity).
  void onPermissionLost() {
    _updateStatus(BubblePermissionStatus.bubbleChannelDisabled);
    debugPrint('⚠️ BubblePermission lost (OEM reset detected)');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS — Mở Settings theo OEM
  // ─────────────────────────────────────────────────────────────────────────

  /// Mở màn hình cài đặt bubble phù hợp theo OEM.
  Future<void> openBubbleSettings() async {
    try {
      await _method.invokeMethod('openBubbleSettings');
    } catch (e) {
      debugPrint('❌ openBubbleSettings: $e');
    }
  }

  /// Mở màn hình whitelist pin theo OEM.
  Future<void> openBatteryWhitelist() async {
    try {
      await _method.invokeMethod('openBatteryWhitelist');
    } catch (e) {
      debugPrint('❌ openBatteryWhitelist: $e');
    }
  }

  /// Mở màn hình tự khởi động theo OEM.
  Future<void> openAutoStartSettings() async {
    try {
      await _method.invokeMethod('openAutoStartSettings');
    } catch (e) {
      debugPrint('❌ openAutoStartSettings: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _updateStatus(BubblePermissionStatus status) {
    _currentStatus = status;
    if (!_statusCtrl.isClosed) {
      _statusCtrl.add(status);
    }
  }

  BubblePermissionStatus _parseStatus(String? raw) {
    if (raw == null) return BubblePermissionStatus.unknown;
    try {
      return BubblePermissionStatus.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => BubblePermissionStatus.unknown,
      );
    } catch (_) {
      return BubblePermissionStatus.unknown;
    }
  }

  Future<String> _getOemName() async {
    try {
      return await _method.invokeMethod<String>('getOemName') ?? 'Android';
    } catch (_) {
      return 'Android';
    }
  }

  Future<List<String>> _getBubbleSetupSteps() async {
    try {
      final raw = await _method.invokeListMethod<String>('getBubbleSetupSteps');
      return raw ?? _defaultSetupSteps();
    } catch (_) {
      return _defaultSetupSteps();
    }
  }

  List<String> _defaultSetupSteps() => [
    'Cài đặt → Thông báo → tên ứng dụng → bật Cho phép bong bóng',
  ];

  bool _isInDismissCooldown() {
    final dismissedAt = _prefs?.getInt(_prefKeyDismissedAt);
    if (dismissedAt == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - dismissedAt;
    return elapsed < _dismissCooldown.inMilliseconds;
  }

  Future<void> _markDismissed() async {
    await _prefs?.setInt(
      _prefKeyDismissedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEBUG / TESTING
  // ─────────────────────────────────────────────────────────────────────────

  /// Reset cooldown và counter — dùng cho testing.
  Future<void> resetOnboardingState() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.remove(_prefKeyDismissedAt);
    await _prefs?.remove(_prefKeyShownCount);
    debugPrint('🔄 BubblePermission onboarding state reset');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────────────────────

  void dispose() {
    if (!_statusCtrl.isClosed) _statusCtrl.close();
    _isInitialized = false;
  }
}
