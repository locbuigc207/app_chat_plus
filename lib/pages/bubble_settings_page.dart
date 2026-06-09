// lib/pages/bubble_settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
const _kBlue = Color(0xFF2979FF);
const _kBlue2 = Color(0xFF1565C0);
const _kSurf = Color(0xFFF8FAFF);
const _kCard = Color(0xFFFFFFFF);

// ═════════════════════════════════════════════════════════════════════════════
// PAGE
// ═════════════════════════════════════════════════════════════════════════════

class BubbleSettingsPage extends StatefulWidget {
  const BubbleSettingsPage({super.key});

  @override
  State<BubbleSettingsPage> createState() => _BubbleSettingsPageState();
}

class _BubbleSettingsPageState extends State<BubbleSettingsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;

  final _svc = BubbleSettingsService();

  @override
  void initState() {
    super.initState();
    _svc.load();
    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _svc,
      child: Consumer<BubbleSettingsService>(
        builder: (ctx, svc, _) {
          final s = svc.settings;
          return Scaffold(
            backgroundColor: _kSurf,
            body: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildAppBar(ctx),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Master toggle ────────────────────────────────
                      FadeTransition(
                        opacity: _heroFade,
                        child: _MasterToggle(
                          enabled: s.enabled,
                          onChanged: svc.setEnabled,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Notification behaviour ───────────────────────
                      _Section(
                        title: 'Thông báo',
                        icon: Icons.notifications_rounded,
                        enabled: s.enabled,
                        children: [
                          _ToggleTile(
                            icon: Icons.volume_up_rounded,
                            color: Colors.orange,
                            title: 'Âm thanh',
                            subtitle: 'Phát âm thanh khi có tin nhắn mới',
                            value: s.soundEnabled,
                            onChanged: svc.setSound,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.vibration_rounded,
                            color: Colors.purple,
                            title: 'Rung',
                            subtitle: 'Rung nhẹ khi bong bóng cập nhật',
                            value: s.vibrationEnabled,
                            onChanged: svc.setVibration,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.lock_rounded,
                            color: Colors.teal,
                            title: 'Hiện trên màn hình khoá',
                            subtitle:
                                'Cho phép bong bóng hiện khi điện thoại khoá',
                            value: s.showOnLockScreen,
                            onChanged: svc.setShowOnLockScreen,
                            enabled: s.enabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Bubble appearance ────────────────────────────
                      _Section(
                        title: 'Hiển thị',
                        icon: Icons.chat_bubble_rounded,
                        enabled: s.enabled,
                        children: [
                          _ToggleTile(
                            icon: Icons.mark_chat_unread_rounded,
                            color: Colors.red,
                            title: 'Huy hiệu tin chưa đọc',
                            subtitle: 'Hiện số tin chưa đọc trên bong bóng',
                            value: s.showUnreadBadge,
                            onChanged: svc.setShowBadge,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.circle,
                            color: Colors.green,
                            title: 'Trạng thái trực tuyến',
                            subtitle: 'Hiện chấm xanh khi bạn bè đang online',
                            value: s.showOnlineIndicator,
                            onChanged: svc.setShowOnline,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.more_horiz_rounded,
                            color: Colors.blue,
                            title: 'Đang nhập…',
                            subtitle: 'Hiện chỉ báo typing trên bong bóng',
                            value: s.showTypingIndicator,
                            onChanged: svc.setShowTyping,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.auto_awesome_rounded,
                            color: Colors.deepPurple,
                            title: 'Header thông minh',
                            subtitle: 'Đổi màu header theo ngữ cảnh tin nhắn',
                            value: s.contextualHeaderEnabled,
                            onChanged: svc.setContextualHeader,
                            enabled: s.enabled,
                          ),
                          _SliderTile(
                            icon: Icons.bubble_chart_rounded,
                            color: _kBlue,
                            title: 'Kích thước bong bóng',
                            options: const ['Nhỏ', 'Vừa', 'Lớn'],
                            current: s.bubbleSize.index,
                            onChanged: (i) =>
                                svc.setBubbleSize(BubbleSize.values[i]),
                            enabled: s.enabled,
                          ),
                          _SliderTile(
                            icon: Icons.align_horizontal_right_rounded,
                            color: Colors.indigo,
                            title: 'Vị trí mặc định',
                            options: const ['Trái', 'Phải', 'Tự động'],
                            current: s.defaultPosition.index,
                            onChanged: (i) => svc
                                .setDefaultPosition(BubblePosition.values[i]),
                            enabled: s.enabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Behaviour ────────────────────────────────────
                      _Section(
                        title: 'Hành vi',
                        icon: Icons.tune_rounded,
                        enabled: s.enabled,
                        children: [
                          _ToggleTile(
                            icon: Icons.save_rounded,
                            color: Colors.brown,
                            title: 'Lưu khi khởi động lại',
                            subtitle: 'Khôi phục bong bóng sau khi đóng app',
                            value: s.persistAcrossRestart,
                            onChanged: svc.setPersist,
                            enabled: s.enabled,
                          ),
                          _ToggleTile(
                            icon: Icons.visibility_off_rounded,
                            color: Colors.blueGrey,
                            title: 'Tự ẩn khi mở chat',
                            subtitle:
                                'Ẩn bong bóng khi bạn đang xem cuộc trò chuyện',
                            value: s.autoHideWhenChatOpen,
                            onChanged: svc.setAutoHideWhenChatOpen,
                            enabled: s.enabled,
                          ),
                          _StepperTile(
                            icon: Icons.people_alt_rounded,
                            color: Colors.cyan,
                            title: 'Số bong bóng tối đa',
                            subtitle:
                                'Tối đa ${s.maxBubbles} cuộc trò chuyện cùng lúc',
                            value: s.maxBubbles,
                            min: 1,
                            max: 10,
                            onChanged: svc.setMaxBubbles,
                            enabled: s.enabled,
                          ),
                          _AutoHideTile(
                            value: s.autoHideMinutes,
                            onChanged: svc.setAutoHideMinutes,
                            enabled: s.enabled,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Permission + implementation info ─────────────
                      _PermissionCard(),
                      const SizedBox(height: 16),

                      // ── Actions ──────────────────────────────────────
                      _ActionsCard(svc: svc),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext ctx) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _kBlue,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text('Bong bóng chat',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kBlue, _kBlue2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Align(
            alignment: const Alignment(0.85, 0.6),
            child: Icon(Icons.chat_bubble_rounded,
                size: 80, color: Colors.white.withOpacity(0.12)),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MASTER TOGGLE
// ═════════════════════════════════════════════════════════════════════════════

class _MasterToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _MasterToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient:
            enabled ? const LinearGradient(colors: [_kBlue, _kBlue2]) : null,
        color: enabled ? null : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        boxShadow: enabled
            ? [
                BoxShadow(
                    color: _kBlue.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ]
            : [],
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_rounded,
              color: enabled ? Colors.white : Colors.grey, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bật bong bóng chat',
                    style: TextStyle(
                        color: enabled ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                Text(
                  enabled ? 'Đang hoạt động' : 'Đã tắt',
                  style: TextStyle(
                      color: enabled
                          ? Colors.white.withOpacity(0.75)
                          : Colors.grey,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withOpacity(0.35),
            inactiveThumbColor: Colors.grey.shade400,
            inactiveTrackColor: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SECTION CONTAINER
// ═════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool enabled;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.enabled,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.black54),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TOGGLE TILE
// ═════════════════════════════════════════════════════════════════════════════

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const _ToggleTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: (enabled ? color : Colors.grey).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: enabled ? color : Colors.grey, size: 20),
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
              color: enabled ? Colors.black87 : Colors.grey)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: enabled ? Colors.black45 : Colors.grey.shade400)),
      trailing: Switch.adaptive(
        value: enabled ? value : false,
        onChanged: enabled
            ? (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              }
            : null,
        activeColor: color,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SLIDER TILE (segmented options)
// ═════════════════════════════════════════════════════════════════════════════

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> options;
  final int current;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const _SliderTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.options,
    required this.current,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: (enabled ? color : Colors.grey).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon,
                      color: enabled ? color : Colors.grey, size: 20)),
              const SizedBox(width: 12),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: enabled ? Colors.black87 : Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(options.length, (i) {
              final sel = i == current && enabled;
              return Expanded(
                child: GestureDetector(
                  onTap: enabled
                      ? () {
                          HapticFeedback.selectionClick();
                          onChanged(i);
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? color : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: sel ? color : Colors.grey.shade300),
                    ),
                    child: Text(options[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: sel ? Colors.white : Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STEPPER TILE
// ═════════════════════════════════════════════════════════════════════════════

class _StepperTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const _StepperTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: (enabled ? color : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: enabled ? color : Colors.grey, size: 20)),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
              color: enabled ? Colors.black87 : Colors.grey)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: enabled ? Colors.black45 : Colors.grey.shade400)),
      trailing: enabled
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepBtn(
                    icon: Icons.remove,
                    onTap: value > min ? () => onChanged(value - 1) : null),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$value',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: color)),
                ),
                _StepBtn(
                    icon: Icons.add,
                    onTap: value < max ? () => onChanged(value + 1) : null),
              ],
            )
          : null,
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          HapticFeedback.selectionClick();
          onTap!();
        }
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? _kBlue.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? _kBlue.withOpacity(0.3) : Colors.grey.shade300),
        ),
        child:
            Icon(icon, size: 16, color: active ? _kBlue : Colors.grey.shade400),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AUTO HIDE TILE
// ═════════════════════════════════════════════════════════════════════════════

class _AutoHideTile extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  static const _options = [0, 5, 10, 30, 60];
  static const _labels = ['Không', '5 phút', '10 phút', '30 phút', '1 giờ'];

  const _AutoHideTile(
      {required this.value, required this.onChanged, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: (enabled ? Colors.orange : Colors.grey).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.timer_off_rounded,
              color: enabled ? Colors.orange : Colors.grey, size: 20)),
      title: Text('Tự ẩn sau',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
              color: enabled ? Colors.black87 : Colors.grey)),
      subtitle: Text('Tự động ẩn bong bóng không tương tác',
          style: TextStyle(
              fontSize: 12,
              color: enabled ? Colors.black45 : Colors.grey.shade400)),
      trailing: enabled
          ? DropdownButton<int>(
              value: _options.contains(value) ? value : 0,
              underline: const SizedBox.shrink(),
              items: List.generate(
                  _options.length,
                  (i) => DropdownMenuItem(
                      value: _options[i],
                      child: Text(_labels[i],
                          style: const TextStyle(fontSize: 13)))),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            )
          : null,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PERMISSION CARD
// ═════════════════════════════════════════════════════════════════════════════

class _PermissionCard extends StatefulWidget {
  @override
  State<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends State<_PermissionCard> {
  bool? _hasPermission;
  String _implInfo = 'Đang kiểm tra…';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final ctrl = BubbleManager.of(context);
    if (ctrl == null) return;
    final ok = await ctrl.hasPermission();
    final info = ctrl.implementationInfo;
    if (mounted)
      setState(() {
        _hasPermission = ok;
        _implInfo = info;
      });
  }

  @override
  Widget build(BuildContext context) {
    final ok = _hasPermission;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok == null
                    ? Icons.hourglass_empty_rounded
                    : ok
                        ? Icons.verified_rounded
                        : Icons.warning_rounded,
                color: ok == null
                    ? Colors.grey
                    : ok
                        ? Colors.green
                        : Colors.orange,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                ok == null
                    ? 'Đang kiểm tra quyền…'
                    : ok
                        ? 'Quyền đã được cấp'
                        : 'Cần cấp quyền hiển thị',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color:
                        ok == false ? Colors.orange.shade700 : Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Triển khai: $_implInfo',
              style: const TextStyle(fontSize: 12, color: Colors.black45)),
          if (ok == false) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: const Text('Cấp quyền ngay'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final ctrl = BubbleManager.of(context);
                  await ctrl?.requestPermission();
                  _checkPermission();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS CARD
// ═════════════════════════════════════════════════════════════════════════════

class _ActionsCard extends StatelessWidget {
  final BubbleSettingsService svc;
  const _ActionsCard({required this.svc});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          _ActionTile(
            icon: Icons.science_rounded,
            color: _kBlue,
            label: 'Thử bong bóng demo',
            onTap: () async {
              final ctrl = BubbleManager.of(context);
              await ctrl?.showBubble(
                  userId: 'demo_preview',
                  userName: 'Demo Bubble 🫧',
                  avatarUrl: '',
                  lastMessage: 'Đây là bong bóng thử nghiệm ✅',
                  isOnline: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Bong bóng demo đã hiện! Kiểm tra góc màn hình'),
                    behavior: SnackBarBehavior.floating));
              }
            },
          ),
          const Divider(height: 0, indent: 56),
          _ActionTile(
            icon: Icons.clear_all_rounded,
            color: Colors.orange,
            label: 'Ẩn tất cả bong bóng',
            onTap: () async {
              final ctrl = BubbleManager.of(context);
              await ctrl?.hideAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Đã ẩn tất cả bong bóng'),
                    behavior: SnackBarBehavior.floating));
              }
            },
          ),
          const Divider(height: 0, indent: 56),
          _ActionTile(
            icon: Icons.restore_rounded,
            color: Colors.red,
            label: 'Khôi phục mặc định',
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Khôi phục cài đặt?'),
                  content:
                      const Text('Mọi tuỳ chỉnh sẽ bị xoá và đặt về mặc định.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Huỷ')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Khôi phục',
                            style: TextStyle(color: Colors.white))),
                  ],
                ),
              );
              if (confirm == true) await svc.resetToDefaults();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}
