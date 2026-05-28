import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class PINInputDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Function(String pin) onComplete;
  final String? errorMessage;
  final int? remainingAttempts;
  final bool showBiometric;
  final VoidCallback? onBiometric;

  const PINInputDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.onComplete,
    this.errorMessage,
    this.remainingAttempts,
    this.showBiometric = false,
    this.onBiometric,
  });

  @override
  State<PINInputDialog> createState() => _PINInputDialogState();
}

class _PINInputDialogState extends State<PINInputDialog>
    with TickerProviderStateMixin {
  String _pin = '';
  static const int _pinLength = 4;
  bool _isLoading = false;
  bool _hasError = false;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _dotPulseCtrl;
  late Animation<double> _dotPulseAnim;

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _dotPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _dotPulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _dotPulseCtrl, curve: Curves.easeOut),
    );

    if (widget.errorMessage != null) {
      _hasError = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _triggerShake());
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _dotPulseCtrl.dispose();
    super.dispose();
  }

  void _triggerShake() {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
  }

  void _onNumberPressed(String number) {
    if (_pin.length >= _pinLength || _isLoading) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += number;
      _hasError = false;
    });
    _dotPulseCtrl.forward(from: 0).then((_) => _dotPulseCtrl.reverse());
  }

  void _onDeletePressed() {
    if (_pin.isEmpty || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  void _onConfirmPressed() {
    if (_pin.length == _pinLength && !_isLoading) {
      HapticFeedback.mediumImpact();
      setState(() => _isLoading = true);
      widget.onComplete(_pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 60,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Lock icon ──────────────────────────────────────────────────
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _hasError
                      ? [Colors.red.shade400, Colors.red.shade700]
                      : [
                          ColorConstants.primaryColor,
                          ColorConstants.primaryColor.withOpacity(0.75),
                        ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_hasError ? Colors.red : ColorConstants.primaryColor)
                            .withOpacity(0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _hasError ? Icons.lock_reset_rounded : Icons.lock_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Title ──────────────────────────────────────────────────────
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),

          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
              ),
              textAlign: TextAlign.center,
            ),
          ],

          // ── Error message ──────────────────────────────────────────────
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.red.withOpacity(0.2), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Remaining attempts ─────────────────────────────────────────
          if (widget.remainingAttempts != null) ...[
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.remainingAttempts! <= 2
                    ? Colors.red
                    : ColorConstants.greyColor,
              ),
              child: Text(
                'Còn ${widget.remainingAttempts} lần thử',
              ),
            ),
          ],

          const SizedBox(height: 30),

          // ── PIN dots ───────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0), child: child),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _pin.length;
                final isLast = filled && i == _pin.length - 1;
                return AnimatedBuilder(
                  animation: _dotPulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: isLast ? _dotPulseAnim.value : 1.0,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: filled ? 18 : 16,
                    height: filled ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? (_hasError
                              ? Colors.red
                              : ColorConstants.primaryColor)
                          : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? (_hasError
                                ? Colors.red
                                : ColorConstants.primaryColor)
                            : const Color(0xFFD1D5DB),
                        width: 2,
                      ),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: (_hasError
                                        ? Colors.red
                                        : ColorConstants.primaryColor)
                                    .withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ]
                          : [],
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 30),

          // ── Numpad ─────────────────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: 12,
            itemBuilder: (_, i) {
              if (i == 9) {
                return widget.showBiometric
                    ? _buildBiometricButton()
                    : const SizedBox.shrink();
              } else if (i == 10) {
                return _buildKeyButton('0');
              } else if (i == 11) {
                return _buildDeleteButton();
              } else {
                return _buildKeyButton('${i + 1}');
              }
            },
          ),

          const SizedBox(height: 24),

          // ── Confirm button ─────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _pin.length == _pinLength && !_isLoading
                  ? LinearGradient(
                      colors: [
                        ColorConstants.primaryColor,
                        ColorConstants.primaryColor.withOpacity(0.8),
                      ],
                    )
                  : null,
              color: _pin.length == _pinLength && !_isLoading
                  ? null
                  : const Color(0xFFE8EBF0),
              boxShadow: _pin.length == _pinLength && !_isLoading
                  ? [
                      BoxShadow(
                        color: ColorConstants.primaryColor.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _pin.length == _pinLength && !_isLoading
                    ? _onConfirmPressed
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          'Xác nhận',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _pin.length == _pinLength
                                ? Colors.white
                                : const Color(0xFFBEC3CC),
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Cancel ─────────────────────────────────────────────────────
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text(
              'Huỷ',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyButton(String number) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF7F8FA),
            border: Border.all(color: const Color(0xFFE8EBF0), width: 1.5),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: _isLoading
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF1A1A2E),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onDeletePressed,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF7F8FA),
            border: Border.all(color: const Color(0xFFE8EBF0), width: 1.5),
          ),
          child: Center(
            child: Icon(
              Icons.backspace_rounded,
              size: 22,
              color: _pin.isEmpty
                  ? const Color(0xFFD1D5DB)
                  : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onBiometric,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ColorConstants.primaryColor.withOpacity(0.08),
            border: Border.all(
              color: ColorConstants.primaryColor.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.fingerprint_rounded,
              size: 26,
              color: ColorConstants.primaryColor,
            ),
          ),
        ),
      ),
    );
  }
}
