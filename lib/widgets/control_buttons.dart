/// 中面板：功能按钮组
///
/// 四个功能按钮：照明、音效、换端、重联。
/// 金属按钮质感 + 底部指示灯 + 按压动效。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';

class ControlButtons extends ConsumerWidget {
  const ControlButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainState = ref.watch(trainStateProvider);
    final notifier = ref.read(trainStateProvider.notifier);
    final isSlave = trainState.isSlave;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 照明
        Expanded(
          child: _ControlButton(
            label: '照明',
            color: TrainTheme.glowOrange,
            isActive: trainState.headlight,
            isDisabled: isSlave,
            onTap: () => notifier.toggleLight(),
          ),
        ),
        const SizedBox(width: 15),
        // 音效
        Expanded(
          child: _ControlButton(
            label: '音效',
            color: TrainTheme.glowBlue,
            isActive: trainState.soundEnabled,
            isDisabled: isSlave,
            onTap: () => notifier.toggleSound(),
          ),
        ),
        const SizedBox(width: 15),
        // 换端
        Expanded(
          child: _ControlButton(
            label: '换端',
            color: TrainTheme.glowGreen,
            isActive: false,
            isDisabled: isSlave || trainState.isRunning,
            onTap: () => notifier.changeCab(),
          ),
        ),
        const SizedBox(width: 15),
        // 重联
        Expanded(
          child: _CoupleButton(
            coupleStatus: trainState.coupleStatus,
            isDisabled: isSlave,
            onTap: () => notifier.toggleCouple(),
            onLongPress: () {
              // 长按解除重联
              if (trainState.isMaster && !trainState.isRunning) {
                notifier.uncouple();
              }
            },
          ),
        ),
      ],
    );
  }
}

/// 通用金属按钮
class _ControlButton extends StatefulWidget {
  final String label;
  final Color color;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  const _ControlButton({
    required this.label,
    required this.color,
    required this.isActive,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isDisabled
          ? null
          : (_) => setState(() => _isPressed = true),
      onTapUp: widget.isDisabled
          ? null
          : (_) {
              setState(() => _isPressed = false);
              widget.onTap();
              HapticFeedback.lightImpact();
            },
      onTapCancel: widget.isDisabled
          ? null
          : () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 75,
        transform: Matrix4.translationValues(
            0, _isPressed ? 3 : 0, 0),
        decoration: BoxDecoration(
          gradient: widget.isDisabled
              ? const LinearGradient(
                  colors: [Color(0xFF252525), Color(0xFF1A1A1A)],
                )
              : TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TrainTheme.metalDark, width: 2),
          boxShadow: _isPressed
              ? [
                  const BoxShadow(
                    color: Color(0xCC000000),
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                  const BoxShadow(
                    color: Color(0x80000000),
                    offset: Offset(0, 2),
                    blurRadius: 5,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 6),
                    blurRadius: 10,
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    offset: const Offset(0, 2),
                    blurRadius: 2,
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 8),
            // 标签
            Text(
              widget.label,
              style: GoogleFonts.roboto(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: widget.isDisabled
                    ? const Color(0xFF555555)
                    : const Color(0xFFA0AABF),
                letterSpacing: 2,
                shadows: [
                  const Shadow(
                    color: Colors.black,
                    offset: Offset(0, -1),
                    blurRadius: 1,
                  ),
                ],
              ),
            ),
            // 指示灯条
            Container(
              width: 28,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? widget.color
                    : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(2),
                boxShadow: widget.isActive
                    ? [
                        BoxShadow(
                          color: widget.color,
                          blurRadius: 10,
                        ),
                      ]
                    : [
                        const BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 重联按钮（带状态文字变化）
class _CoupleButton extends StatefulWidget {
  final CoupleStatus coupleStatus;
  final bool isDisabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CoupleButton({
    required this.coupleStatus,
    required this.isDisabled,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_CoupleButton> createState() => _CoupleButtonState();
}

class _CoupleButtonState extends State<_CoupleButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.coupleStatus) {
      case CoupleStatus.off:
        return '重联';
      case CoupleStatus.inviting:
        return '邀请中';
      case CoupleStatus.invited:
        return '收到邀请';
      case CoupleStatus.master:
        return '已连接';
      case CoupleStatus.slave:
        return '补机';
    }
  }

  bool get _isActive =>
      widget.coupleStatus != CoupleStatus.off;

  bool get _canTap =>
      !widget.isDisabled &&
      (widget.coupleStatus == CoupleStatus.off ||
          widget.coupleStatus == CoupleStatus.inviting);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _canTap
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: _canTap
          ? (_) {
              setState(() => _isPressed = false);
              widget.onTap();
              HapticFeedback.lightImpact();
            }
          : null,
      onTapCancel: _canTap
          ? () => setState(() => _isPressed = false)
          : null,
      onLongPress: widget.coupleStatus == CoupleStatus.master
          ? () {
              widget.onLongPress();
              HapticFeedback.heavyImpact();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 75,
        transform: Matrix4.translationValues(
            0, _isPressed ? 3 : 0, 0),
        decoration: BoxDecoration(
          gradient: widget.isDisabled
              ? const LinearGradient(
                  colors: [Color(0xFF252525), Color(0xFF1A1A1A)],
                )
              : TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TrainTheme.metalDark, width: 2),
          boxShadow: _isPressed
              ? [
                  const BoxShadow(
                    color: Color(0xCC000000),
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x99000000),
                    offset: Offset(0, 6),
                    blurRadius: 10,
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    offset: const Offset(0, 2),
                    blurRadius: 2,
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 8),
            // 标签（邀请中时闪烁）
            widget.coupleStatus == CoupleStatus.inviting
                ? AnimatedBuilder(
                    animation: _blinkController,
                    builder: (context, child) {
                      return Opacity(
                        opacity:
                            0.4 + 0.6 * _blinkController.value,
                        child: child,
                      );
                    },
                    child: _buildLabel(),
                  )
                : _buildLabel(),
            // 指示灯
            Container(
              width: 28,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _isActive
                    ? TrainTheme.glowRed
                    : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(2),
                boxShadow: _isActive
                    ? [
                        BoxShadow(
                          color: TrainTheme.glowRed,
                          blurRadius: 10,
                        ),
                      ]
                    : [
                        const BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel() {
    return Text(
      _label,
      style: GoogleFonts.roboto(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: widget.isDisabled
            ? const Color(0xFF555555)
            : const Color(0xFFA0AABF),
        letterSpacing: 2,
        shadows: [
          const Shadow(
            color: Colors.black,
            offset: Offset(0, -1),
            blurRadius: 1,
          ),
        ],
      ),
    );
  }
}