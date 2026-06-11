// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/group_call_model.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallPermissionGate
// Checks mic/camera permissions before allowing the user to enter a call.
// Shows a friendly, animated permission-request screen.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallPermissionGate extends StatefulWidget {
  final GroupCallType callType;
  final Widget child;
  final VoidCallback? onDenied;

  const GroupCallPermissionGate({
    super.key,
    required this.callType,
    required this.child,
    this.onDenied,
  });

  @override
  State<GroupCallPermissionGate> createState() =>
      _GroupCallPermissionGateState();
}

class _GroupCallPermissionGateState extends State<GroupCallPermissionGate>
    with TickerProviderStateMixin {
  _PermState _state = _PermState.checking;
  bool _micGranted = false;
  bool _camGranted = false;

  late AnimationController _iconCtrl;
  late Animation<double> _iconScale;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _iconCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _iconScale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _checkPermissions();
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final mic = await Permission.microphone.status;
    final cam = widget.callType == GroupCallType.video
        ? await Permission.camera.status
        : PermissionStatus.granted;

    final micOk = mic.isGranted;
    final camOk = cam.isGranted;

    if (micOk && camOk) {
      setState(() => _state = _PermState.granted);
    } else {
      setState(() {
        _state = _PermState.requesting;
        _micGranted = micOk;
        _camGranted = camOk;
      });
      _iconCtrl.forward();
      _fadeCtrl.forward();
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _state = _PermState.requesting);

    final perms = <Permission>[Permission.microphone];
    if (widget.callType == GroupCallType.video) {
      perms.add(Permission.camera);
    }

    final results = await perms.request();
    final micOk = results[Permission.microphone]?.isGranted ?? false;
    final camOk = widget.callType == GroupCallType.video
        ? (results[Permission.camera]?.isGranted ?? false)
        : true;

    setState(() {
      _micGranted = micOk;
      _camGranted = camOk;
    });

    if (micOk && camOk) {
      setState(() => _state = _PermState.granted);
    } else if (!micOk &&
        (results[Permission.microphone]?.isPermanentlyDenied ?? false)) {
      setState(() => _state = _PermState.permanentlyDenied);
    } else {
      setState(() => _state = _PermState.denied);
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _PermState.granted || _state == _PermState.checking) {
      return widget.child;
    }
    return _buildPermissionScreen();
  }

  Widget _buildPermissionScreen() {
    return Scaffold(
      backgroundColor: _K.bg,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                // Back button
                Row(children: [
                  GestureDetector(
                    onTap: () {
                      widget.onDenied?.call();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white60, size: 18),
                    ),
                  ),
                ]),

                const Spacer(flex: 2),

                // Icon
                ScaleTransition(
                  scale: _iconScale,
                  child: _buildPermIcon(),
                ),

                const SizedBox(height: 28),

                // Title
                Text(
                  _state == _PermState.permanentlyDenied
                      ? 'Quyền truy cập bị chặn'
                      : 'Cần cấp quyền truy cập',
                  style: const TextStyle(
                    color: _K.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  _buildDescription(),
                  style: const TextStyle(
                    color: _K.sub,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                // Permission items
                _buildPermissionItems(),

                const Spacer(flex: 2),

                // Action buttons
                _buildButtons(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermIcon() {
    final needMic = !_micGranted;
    final needCam = widget.callType == GroupCallType.video && !_camGranted;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _K.amber.withOpacity(0.15),
            _K.amber.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _K.amber.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: _K.amber.withOpacity(0.15), blurRadius: 30),
        ],
      ),
      child: Icon(
        needCam && needMic
            ? Icons.no_photography_rounded
            : needMic
                ? Icons.mic_off_rounded
                : Icons.videocam_off_rounded,
        color: _K.amber,
        size: 44,
      ),
    );
  }

  String _buildDescription() {
    if (_state == _PermState.permanentlyDenied) {
      return 'Bạn đã từ chối quyền truy cập trước đó.\n'
          'Vui lòng vào Cài đặt để cấp quyền thủ công.';
    }
    if (widget.callType == GroupCallType.video) {
      return 'Để thực hiện cuộc gọi video nhóm, ứng dụng cần '
          'quyền truy cập vào micro và camera của bạn.';
    }
    return 'Để thực hiện cuộc gọi thoại nhóm, ứng dụng cần '
        'quyền truy cập vào micro của bạn.';
  }

  Widget _buildPermissionItems() {
    return Column(
      children: [
        _PermItem(
          icon: Icons.mic_rounded,
          label: 'Microphone',
          description: 'Để người khác nghe thấy bạn',
          granted: _micGranted,
        ),
        if (widget.callType == GroupCallType.video) ...[
          const SizedBox(height: 10),
          _PermItem(
            icon: Icons.videocam_rounded,
            label: 'Camera',
            description: 'Để người khác nhìn thấy bạn',
            granted: _camGranted,
          ),
        ],
      ],
    );
  }

  Widget _buildButtons() {
    if (_state == _PermState.permanentlyDenied) {
      return Column(children: [
        _PrimaryBtn(
          label: 'Mở Cài đặt',
          icon: Icons.settings_rounded,
          color: _K.amber,
          onTap: _openSettings,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () {
            widget.onDenied?.call();
            Navigator.of(context).pop();
          },
          child: const Text('Huỷ',
              style: TextStyle(color: _K.muted, fontWeight: FontWeight.w600)),
        ),
      ]);
    }

    return Column(children: [
      _PrimaryBtn(
        label: 'Cấp quyền truy cập',
        icon: Icons.security_rounded,
        color: _K.accent,
        onTap: _requestPermissions,
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () {
          widget.onDenied?.call();
          Navigator.of(context).pop();
        },
        child: const Text('Bỏ qua',
            style: TextStyle(color: _K.muted, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

enum _PermState { checking, requesting, granted, denied, permanentlyDenied }

// ─── Permission item row ──────────────────────────────────────────────────────
class _PermItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool granted;

  const _PermItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.granted,
  });

  @override
  Widget build(BuildContext context) {
    final color = granted ? _K.green : _K.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: _K.text, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(description,
                style: const TextStyle(color: _K.sub, fontSize: 11)),
          ],
        )),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            granted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            key: ValueKey(granted),
            color: granted ? _K.green : _K.muted,
            size: 20,
          ),
        ),
      ]),
    );
  }
}

// ─── Primary button ───────────────────────────────────────────────────────────
class _PrimaryBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PrimaryBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 9),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallNetworkWarning
// Warning snackbar/overlay when network quality drops during a call
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallNetworkWarning extends StatefulWidget {
  final int rtt;
  final int packetLoss;

  const GroupCallNetworkWarning({
    super.key,
    required this.rtt,
    required this.packetLoss,
  });

  @override
  State<GroupCallNetworkWarning> createState() =>
      _GroupCallNetworkWarningState();
}

class _GroupCallNetworkWarningState extends State<GroupCallNetworkWarning>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  bool get _isBad => widget.rtt > 300 || widget.packetLoss > 12;
  bool get _isWeak => widget.rtt > 160 || widget.packetLoss > 5;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    if (_isBad || _isWeak) _ctrl.forward();
  }

  @override
  void didUpdateWidget(GroupCallNetworkWarning old) {
    super.didUpdateWidget(old);
    if ((_isBad || _isWeak) && _ctrl.value == 0) {
      _ctrl.forward();
    } else if (!_isBad && !_isWeak) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBad && !_isWeak) return const SizedBox.shrink();

    final color = _isBad ? _K.red : _K.amber;

    // Sửa icon báo mạng yếu thành wifi_2_bar_rounded (hoặc wifi_1_bar_rounded)
    final icon =
        _isBad ? Icons.signal_wifi_bad_rounded : Icons.wifi_1_bar_rounded;

    final label = _isBad
        ? 'Mạng rất kém — chất lượng cuộc gọi thấp'
        : 'Mạng yếu — hình ảnh có thể bị giật';

    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero)
            .animate(_anim),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(
                alpha: 0.15), // Cập nhật withValues thay cho withOpacity
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 7),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}
