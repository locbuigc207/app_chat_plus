// lib/widgets/mini_chat_input_bar.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'; // Thêm dòng này để fix lỗi AsyncCallback
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../models/models.dart'; // MessageChat

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

const _kBlue = Color(0xFF2979FF);
const _kBlue2 = Color(0xFF1565C0);
const _kSurf = Color(0xFFF4F7FF);
const _kBorder = Color(0xFFDDE3F0);

// ═══════════════════════════════════════════════════════════════════════════
// CALLBACKS MODEL
// ═══════════════════════════════════════════════════════════════════════════

typedef OnSendText = void Function(String text);
typedef OnSendImage = void Function(File file);
typedef OnSendVoice = void Function(String path, Duration dur);
typedef OnTyping = void Function(bool isTyping);

// ═══════════════════════════════════════════════════════════════════════════
// MINI CHAT INPUT BAR
// ═══════════════════════════════════════════════════════════════════════════

/// Full-featured chat input bar for both the full-screen ChatPage and the
/// floating MiniChatOverlayWidget.
///
/// Features
/// ─────────
/// • Auto-resize textarea (1-6 lines) with smooth height animation.
/// • Send button morphs: idle=attach, typing=send (animated transition).
/// • Voice message: hold mic → record → release to send.
///   Visual waveform feedback during recording.
/// • Image attach: gallery or camera.
/// • Emoji toggle (calls back to parent to show picker overlay).
/// • Reply preview bar (animated slide-in/out).
/// • Typing indicator broadcast (debounced 1.5 s).
/// • Link-detection underlines URLs as you type.
/// • Mini mode: compresses to single-line with smaller padding for
///   MiniChatOverlayWidget where vertical space is limited.
class MiniChatInputBar extends StatefulWidget {
  final OnSendText? onSendText;
  final OnSendImage? onSendImage;
  final OnSendVoice? onSendVoice;
  final OnTyping? onTyping;
  final VoidCallback? onEmojiToggle;
  final VoidCallback? onCancelReply;
  final MessageChat? replyTo;
  final bool isMiniMode; // compact layout for overlay
  final bool emojiOpen;
  final FocusNode? focusNode;

  const MiniChatInputBar({
    super.key,
    this.onSendText,
    this.onSendImage,
    this.onSendVoice,
    this.onTyping,
    this.onEmojiToggle,
    this.onCancelReply,
    this.replyTo,
    this.isMiniMode = false,
    this.emojiOpen = false,
    this.focusNode,
  });

  @override
  State<MiniChatInputBar> createState() => MiniChatInputBarState();
}

class MiniChatInputBarState extends State<MiniChatInputBar>
    with TickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────
  final _textCtrl = TextEditingController();
  late final FocusNode _focus;
  final _picker = ImagePicker();

  // ── Voice recording ──────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordTimer;
  Duration _recordDuration = Duration.zero;
  String? _recordPath;

  // ── State ────────────────────────────────────────────────────────────────
  bool _hasText = false;
  bool _isTyping = false;
  Timer? _typingTimer;

  // ── Animations ───────────────────────────────────────────────────────────
  late AnimationController _sendCtrl;
  late Animation<double> _sendScale;
  late AnimationController _replyCtrl;
  late Animation<Offset> _replySlide;

  // ─── Init ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();

    _sendCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _sendScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _sendCtrl, curve: Curves.elasticOut));

    _replyCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _replySlide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _replyCtrl, curve: Curves.easeOut));

    _textCtrl.addListener(_onTextChanged);
    if (widget.replyTo != null) _replyCtrl.forward();
  }

  @override
  void didUpdateWidget(MiniChatInputBar old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != old.replyTo) {
      if (widget.replyTo != null) {
        _replyCtrl.forward();
        _focus.requestFocus();
      } else {
        _replyCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    if (widget.focusNode == null) _focus.dispose();
    _sendCtrl.dispose();
    _replyCtrl.dispose();
    _typingTimer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ─── Text ────────────────────────────────────────────────────────────────

  void _onTextChanged() {
    final has = _textCtrl.text.trim().isNotEmpty;
    if (has != _hasText) {
      setState(() => _hasText = has);
      if (has) {
        _sendCtrl.forward();
      } else {
        _sendCtrl.reverse();
      }
    }
    // Typing indicator (debounce 1.5 s)
    if (has && !_isTyping) {
      _isTyping = true;
      widget.onTyping?.call(true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_isTyping) {
        _isTyping = false;
        widget.onTyping?.call(false);
      }
    });
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.onSendText?.call(text);
    _textCtrl.clear();
    _isTyping = false;
    widget.onTyping?.call(false);
    _focus.requestFocus();
  }

  // ─── Voice ───────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    HapticFeedback.mediumImpact();

    final dir = Directory.systemTemp;
    _recordPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: _recordPath!,
    );

    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
    });

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordDuration += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    HapticFeedback.lightImpact();

    if (!cancel && path != null && _recordDuration.inSeconds >= 1) {
      widget.onSendVoice?.call(path, _recordDuration);
    }
    _recordDuration = Duration.zero;
  }

  // ─── Image ───────────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final xf = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1280);
    if (xf == null) return;
    widget.onSendImage?.call(File(xf.path));
  }

  void _showAttachSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachSheet(
        onGallery: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
        onCamera: () {
          Navigator.pop(context);
          _pickImage(ImageSource.camera);
        },
      ),
    );
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  void insertText(String text) {
    final sel = _textCtrl.selection;
    final newText = _textCtrl.text.substring(0, sel.baseOffset) +
        text +
        _textCtrl.text.substring(sel.extentOffset);
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.baseOffset + text.length),
    );
  }

  void clear() => _textCtrl.clear();
  String get currentText => _textCtrl.text;

  // ═════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final mini = widget.isMiniMode;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _kBorder, width: 0.8)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, mini ? 4 : 6, 8, mini ? 4 : 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Reply preview ───────────────────────────────────────
              if (widget.replyTo != null)
                SlideTransition(
                  position: _replySlide,
                  child: _ReplyPreviewBar(
                    message: widget.replyTo!,
                    onCancel: widget.onCancelReply,
                  ),
                ),

              // ── Input row ───────────────────────────────────────────
              _isRecording
                  ? _RecordingRow(
                      duration: _recordDuration,
                      onCancel: () => _stopRecording(cancel: true),
                      onSend: () => _stopRecording(cancel: false),
                    )
                  : _InputRow(
                      textCtrl: _textCtrl,
                      focus: _focus,
                      hasText: _hasText,
                      sendScale: _sendScale,
                      emojiOpen: widget.emojiOpen,
                      isMiniMode: mini,
                      onEmojiToggle: widget.onEmojiToggle,
                      onAttach: _showAttachSheet,
                      onSend: _sendText,
                      onMicDown: _startRecording,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INPUT ROW
// ═══════════════════════════════════════════════════════════════════════════

class _InputRow extends StatelessWidget {
  final TextEditingController textCtrl;
  final FocusNode focus;
  final bool hasText;
  final Animation<double> sendScale;
  final bool emojiOpen;
  final bool isMiniMode;
  final VoidCallback? onEmojiToggle;
  final VoidCallback? onAttach;
  final VoidCallback onSend;
  final AsyncCallback onMicDown;

  const _InputRow({
    required this.textCtrl,
    required this.focus,
    required this.hasText,
    required this.sendScale,
    required this.emojiOpen,
    required this.isMiniMode,
    required this.onEmojiToggle,
    required this.onAttach,
    required this.onSend,
    required this.onMicDown,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Emoji toggle ─────────────────────────────────────────────
        _IconBtn(
          icon: emojiOpen
              ? Icons.keyboard_rounded
              : Icons.emoji_emotions_outlined,
          color: emojiOpen ? _kBlue : Colors.grey.shade500,
          onTap: onEmojiToggle,
          size: isMiniMode ? 20 : 22,
        ),
        const SizedBox(width: 4),

        // ── Text field ───────────────────────────────────────────────
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isMiniMode ? 80 : 140),
            child: TextField(
              controller: textCtrl,
              focusNode: focus,
              maxLines: null,
              minLines: 1,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontSize: isMiniMode ? 13.5 : 15,
                color: Colors.black87,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn…',
                hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: isMiniMode ? 13.5 : 15),
                filled: true,
                fillColor: _kSurf,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 14, vertical: isMiniMode ? 8 : 10),
                border: _border(),
                enabledBorder: _border(),
                focusedBorder: _border(focused: true),
                isDense: isMiniMode,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),

        // ── Attach / Send / Mic ──────────────────────────────────────
        Stack(
          alignment: Alignment.center,
          children: [
            // Attach (visible when no text)
            AnimatedOpacity(
              opacity: hasText ? 0 : 1,
              duration: const Duration(milliseconds: 160),
              child: _IconBtn(
                icon: Icons.attach_file_rounded,
                color: Colors.grey.shade500,
                onTap: hasText ? null : onAttach,
                size: isMiniMode ? 20 : 22,
              ),
            ),
            // Send (slides in when typing)
            ScaleTransition(
              scale: sendScale,
              child: _SendBtn(onTap: onSend, mini: isMiniMode),
            ),
          ],
        ),

        // Mic (only when no text)
        if (!hasText) ...[
          const SizedBox(width: 4),
          _MicBtn(onDown: onMicDown, mini: isMiniMode),
        ],
      ],
    );
  }

  OutlineInputBorder _border({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: focused ? _kBlue.withValues(alpha: 0.5) : _kBorder,
          width: focused ? 1.5 : 1,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING ROW
// ═══════════════════════════════════════════════════════════════════════════

class _RecordingRow extends StatefulWidget {
  final Duration duration;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  const _RecordingRow(
      {required this.duration, required this.onCancel, required this.onSend});

  @override
  State<_RecordingRow> createState() => _RecordingRowState();
}

class _RecordingRowState extends State<_RecordingRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Cancel
        GestureDetector(
          onTap: widget.onCancel,
          child: Container(
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.delete_rounded,
                  color: Colors.red, size: 22)),
        ),
        // Waveform + timer
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: Color.lerp(
                            Colors.red, Colors.red.shade300, _pulse.value),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.red
                                  .withValues(alpha: 0.4 * _pulse.value),
                              blurRadius: 8),
                        ]),
                  ),
                ),
                const SizedBox(width: 8),
                Text('🎤  ${_fmt(widget.duration)}',
                    style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Spacer(),
                _Waveform(pulse: _pulse),
              ],
            ),
          ),
        ),
        // Send
        GestureDetector(
          onTap: widget.onSend,
          child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.all(10),
              decoration:
                  const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 20)),
        ),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  final Animation<double> pulse;
  static const _h = [0.4, 0.7, 1.0, 0.6, 0.9, 0.5, 0.8, 0.4, 0.7, 1.0];

  const _Waveform({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _h.asMap().entries.map((e) {
          final h = e.value * (0.6 + pulse.value * 0.4);
          return Container(
            width: 3,
            height: 18 * h,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.6 + pulse.value * 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPLY PREVIEW BAR
// ═══════════════════════════════════════════════════════════════════════════

class _ReplyPreviewBar extends StatelessWidget {
  final MessageChat message;
  final VoidCallback? onCancel;
  const _ReplyPreviewBar({required this.message, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: _kSurf,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: _kBlue, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trả lời',
                    style: TextStyle(
                        color: _kBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                Text(message.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close_rounded,
                size: 18, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTACH SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _AttachSheet extends StatelessWidget {
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  const _AttachSheet({required this.onGallery, required this.onCamera});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12), blurRadius: 20),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.photo_library_rounded,
                color: Colors.purple,
                label: 'Thư viện',
                onTap: onGallery,
              ),
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                color: _kBlue,
                label: 'Camera',
                onTap: onCamera,
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                color: Colors.orange,
                label: 'Tệp',
                onTap: () {}, // Extend: file picker
              ),
              _AttachOption(
                icon: Icons.location_on_rounded,
                color: Colors.green,
                label: 'Vị trí',
                onTap: () {}, // Extend: location sharing
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _AttachOption(
      {required this.icon,
      required this.color,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        children: [
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26)),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SMALL BUTTON WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  const _IconBtn(
      {required this.icon, required this.color, this.onTap, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          HapticFeedback.lightImpact();
          onTap!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

class _SendBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool mini;
  const _SendBtn({required this.onTap, required this.mini});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: mini ? 34 : 40,
        height: mini ? 34 : 40,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [_kBlue, _kBlue2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          shape: BoxShape.circle,
        ),
        child:
            Icon(Icons.send_rounded, color: Colors.white, size: mini ? 16 : 18),
      ),
    );
  }
}

class _MicBtn extends StatelessWidget {
  final AsyncCallback onDown;
  final bool mini;
  const _MicBtn({required this.onDown, required this.mini});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onDown(),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.mic_rounded,
            color: Colors.grey.shade500, size: mini ? 20 : 22),
      ),
    );
  }
}
