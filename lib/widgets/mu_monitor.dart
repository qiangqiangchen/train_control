import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';

class MuMonitor extends ConsumerStatefulWidget {
  const MuMonitor({super.key});

  @override
  ConsumerState<MuMonitor> createState() => _MuMonitorState();
}

class _MuMonitorState extends ConsumerState<MuMonitor>
    with SingleTickerProviderStateMixin {
  late AnimationController _warn;

  @override
  void initState() {
    super.initState();
    _warn = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _warn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(trainStateProvider);
    final n = ref.read(trainStateProvider.notifier);
    final master = ts.isMaster;
    final slave = ts.isSlave;
    final off = !master && !slave;

    return Opacity(
      opacity: off ? 0.35 : 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF070E14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TrainTheme.metalDark, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0xE6000000), offset: Offset(0, 2), blurRadius: 8)
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CrtPainter())),
            Padding(
              padding: const EdgeInsets.all(8),
              child: slave ? _slaveView(ts) : _masterView(ts, n, master),
            ),
            if (ts.slaveWarning && master) _warnOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _masterView(TrainState ts, TrainStateNotifier n, bool active) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '🔗 补机: ${active ? "连接(${ts.slaveCab == CabEnd.a ? 'A' : 'B'}端)" : "未连接"}',
              style: _ms(11),
            ),
            if (active)
              Text(
                '🔋 ${ts.slaveBattery ?? 0}% ${ts.slaveBatteryVoltage?.toStringAsFixed(2) ?? "0.00"}V',
                style: _ms(10),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text('PWM:', style: _ms(10)),
            const SizedBox(width: 4),
            Expanded(
                child: _SpeedBar(
                    value: active
                        ? (ts.slaveActualPwm ?? 0) / 255.0
                        : 0)),
            const SizedBox(width: 4),
            Text(
              active ? '${ts.slaveActualPwm ?? 0}/${ts.targetPwm}' : '0/0',
              style: _ms(11),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text('系数: ${(ts.speedCoefficient ?? 1.0).toStringAsFixed(2)}',
                style: _ms(10)),
            const Spacer(),
            _MuBtn(
                label: '◀',
                onTap: active
                    ? () {
                        n.setSpeedCoefficient(
                            (ts.speedCoefficient ?? 1.0) -
                                BleConstants.coefficientStep);
                        HapticFeedback.selectionClick();
                      }
                    : null),
            const SizedBox(width: 3),
            _MuBtn(
                label: '▶',
                onTap: active
                    ? () {
                        n.setSpeedCoefficient(
                            (ts.speedCoefficient ?? 1.0) +
                                BleConstants.coefficientStep);
                        HapticFeedback.selectionClick();
                      }
                    : null),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 20,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: TrainTheme.muGlow,
                    inactiveTrackColor: TrainTheme.metalDark,
                    thumbColor: TrainTheme.muGlow,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayColor: TrainTheme.muGlow.withOpacity(0.2),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: (ts.speedCoefficient ?? 1.0).clamp(
                        BleConstants.minCoefficient,
                        BleConstants.maxCoefficient),
                    min: BleConstants.minCoefficient,
                    max: BleConstants.maxCoefficient,
                    divisions: 20,
                    onChanged:
                        active ? (v) => n.setSpeedCoefficient(v) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _slaveView(TrainState ts) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🔗 补机模式', style: _ms(13)),
          const SizedBox(height: 3),
          Text(
            'LV:${ts.level} PWM:${ts.actualPwm} HL:${ts.headlight ? "ON" : "OFF"}',
            style: _ms(9).copyWith(color: TrainTheme.muGlow.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  Widget _warnOverlay() {
    return AnimatedBuilder(
      animation: _warn,
      builder: (_, __) => Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            color: Color.lerp(
                const Color(0xE6320000), const Color(0xD9140000), _warn.value),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFFF3333), width: 1.5),
          ),
          child: Center(
            child: Opacity(
              opacity: 0.6 + 0.4 * _warn.value,
              child: Text(
                '⚠ 补机通信异常',
                style: TrainTheme.orbitronStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFF3333),
                  letterSpacing: 1,
                  shadows: [
                    const Shadow(color: Color(0xFFFF3333), blurRadius: 10)
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _ms(double sz) => TrainTheme.orbitronStyle(
        fontSize: sz,
        color: TrainTheme.muGlow,
        shadows: [
          Shadow(color: TrainTheme.muGlow.withOpacity(0.5), blurRadius: 4)
        ],
      );
}

class _CrtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withOpacity(0.12);
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpeedBar extends StatelessWidget {
  final double value;
  const _SpeedBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: TrainTheme.metalDark),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                  color: TrainTheme.muGlow.withOpacity(0.5), blurRadius: 5)
            ],
          ),
          child: CustomPaint(painter: _StripePainter()),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(
        Rect.fromLTWH(0, 0, s.width, s.height), Paint()..color = TrainTheme.muGlow);
    final sp = Paint()..color = const Color(0xFF0A8A56);
    for (double x = -s.height; x < s.width + s.height; x += 10) {
      canvas.drawPath(
        Path()
          ..moveTo(x, s.height)
          ..lineTo(x + 5, s.height)
          ..lineTo(x + 5 + s.height, 0)
          ..lineTo(x + s.height, 0)
          ..close(),
        sp,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MuBtn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _MuBtn({required this.label, this.onTap});

  @override
  State<_MuBtn> createState() => _MuBtnState();
}

class _MuBtnState extends State<_MuBtn> {
  bool _p = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _p = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _p = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _p = false)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: _p ? TrainTheme.muGlow : Colors.black,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: TrainTheme.muGlow, width: 0.8),
        ),
        child: Text(
          widget.label,
          style: TrainTheme.orbitronStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: _p ? Colors.black : TrainTheme.muGlow,
          ),
        ),
      ),
    );
  }
}