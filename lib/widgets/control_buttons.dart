import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';

class ControlButtons extends ConsumerWidget {
  const ControlButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(trainStateProvider);
    final n = ref.read(trainStateProvider.notifier);
    final slave = ts.isSlave;

    return SizedBox(
      height: 55,
      child: Row(
        children: [
          Expanded(
              child: _CtrlBtn(
                  label: '照明',
                  color: TrainTheme.glowOrange,
                  active: ts.headlight,
                  disabled: slave,
                  onTap: () => n.toggleLight())),
          const SizedBox(width: 6),
          Expanded(
              child: _CtrlBtn(
                  label: '音效',
                  color: TrainTheme.glowBlue,
                  active: ts.soundEnabled,
                  disabled: slave,
                  onTap: () => n.toggleSound())),
          const SizedBox(width: 6),
          Expanded(
              child: _CabSwitch(
                  cab: ts.cab,
                  disabled: slave || ts.isRunning,
                  onToggle: () => n.changeCab())),
          const SizedBox(width: 6),
          Expanded(
              child: _CoupleBtn(
            status: ts.coupleStatus,
            disabled: slave,
            onTap: () => n.toggleCouple(),
            onLongPress: () {
              if (ts.isMaster && !ts.isRunning) n.uncouple();
            },
          )),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatefulWidget {
  final String label;
  final Color color;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.label,
    required this.color,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_CtrlBtn> createState() => _CtrlBtnState();
}

class _CtrlBtnState extends State<_CtrlBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.disabled
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: widget.disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
              HapticFeedback.lightImpact();
            },
      onTapCancel: widget.disabled
          ? null
          : () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
        decoration: BoxDecoration(
          gradient: widget.disabled
              ? const LinearGradient(
                  colors: [Color(0xFF252525), Color(0xFF1A1A1A)])
              : TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TrainTheme.metalDark, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_pressed ? 0.9 : 0.6),
              offset: Offset(0, _pressed ? 1 : 4),
              blurRadius: _pressed ? 2 : 7,
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.label,
                style: TrainTheme.rajdhaniStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.disabled
                      ? const Color(0xFF555555)
                      : const Color(0xFFA0AABF),
                  letterSpacing: 1,
                )),
            const SizedBox(height: 5),
            Container(
              width: 22,
              height: 4,
              decoration: BoxDecoration(
                color:
                    widget.active ? widget.color : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(2),
                boxShadow: widget.active
                    ? [BoxShadow(color: widget.color, blurRadius: 8)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CabSwitch extends StatelessWidget {
  final CabEnd cab;
  final bool disabled;
  final VoidCallback onToggle;

  const _CabSwitch(
      {required this.cab, required this.disabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isB = cab == CabEnd.b;
    final color = isB ? TrainTheme.glowOrange : TrainTheme.glowGreen;

    return GestureDetector(
      onTap: disabled
          ? null
          : () {
              onToggle();
              HapticFeedback.mediumImpact();
            },
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: TrainTheme.metalBtnGradient,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TrainTheme.metalDark, width: 1.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  offset: const Offset(0, 4),
                  blurRadius: 7)
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('换端',
                  style: TrainTheme.rajdhaniStyle(
                      fontSize: 10, color: const Color(0xFF888888))),
              const SizedBox(height: 4),
              Container(
                width: 40,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B0D),
                  borderRadius: BorderRadius.circular(9),
                  border:
                      Border.all(color: const Color(0xFF333333), width: 1),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0xCC000000),
                        offset: Offset(0, 1),
                        blurRadius: 3)
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                        left: 4,
                        top: 2,
                        child: Text('A',
                            style: TrainTheme.orbitronStyle(
                                fontSize: 7,
                                color: !isB
                                    ? color.withOpacity(0.8)
                                    : const Color(0xFF444444)))),
                    Positioned(
                        right: 4,
                        top: 2,
                        child: Text('B',
                            style: TrainTheme.orbitronStyle(
                                fontSize: 7,
                                color: isB
                                    ? color.withOpacity(0.8)
                                    : const Color(0xFF444444)))),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      left: isB ? 20 : 2,
                      top: 2,
                      child: Container(
                        width: 14,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 5),
                            BoxShadow(
                                color: Colors.white.withOpacity(0.25),
                                offset: const Offset(0, 1),
                                blurRadius: 1),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoupleBtn extends StatefulWidget {
  final CoupleStatus status;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CoupleBtn({
    required this.status,
    required this.disabled,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_CoupleBtn> createState() => _CoupleBtnState();
}

class _CoupleBtnState extends State<_CoupleBtn>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.status) {
      case CoupleStatus.off:
        return '重联';
      case CoupleStatus.inviting:
        return '邀请中';
      case CoupleStatus.invited:
        return '邀请';
      case CoupleStatus.master:
        return '已连';
      case CoupleStatus.slave:
        return '补机';
    }
  }

  bool get _active => widget.status != CoupleStatus.off;

  bool get _canTap =>
      !widget.disabled &&
      (widget.status == CoupleStatus.off ||
          widget.status == CoupleStatus.inviting);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _canTap
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: _canTap
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
              HapticFeedback.lightImpact();
            }
          : null,
      onTapCancel: _canTap
          ? () => setState(() => _pressed = false)
          : null,
      onLongPress: widget.status == CoupleStatus.master
          ? () {
              widget.onLongPress();
              HapticFeedback.heavyImpact();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
        decoration: BoxDecoration(
          gradient: widget.disabled
              ? const LinearGradient(
                  colors: [Color(0xFF252525), Color(0xFF1A1A1A)])
              : TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TrainTheme.metalDark, width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.6),
                offset: const Offset(0, 4),
                blurRadius: 7)
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.status == CoupleStatus.inviting
                ? AnimatedBuilder(
                    animation: _blink,
                    builder: (_, child) => Opacity(
                        opacity: 0.4 + 0.6 * _blink.value,
                        child: child),
                    child: _labelWidget(),
                  )
                : _labelWidget(),
            const SizedBox(height: 5),
            Container(
              width: 22,
              height: 4,
              decoration: BoxDecoration(
                color: _active ? TrainTheme.glowRed : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(2),
                boxShadow: _active
                    ? [BoxShadow(color: TrainTheme.glowRed, blurRadius: 8)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelWidget() {
    return Text(_label,
        style: TrainTheme.rajdhaniStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: widget.disabled
              ? const Color(0xFF555555)
              : const Color(0xFFA0AABF),
          letterSpacing: 1,
        ));
  }
}