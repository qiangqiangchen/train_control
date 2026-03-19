import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/train_theme.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';
import 'speedometer_painter.dart';

class Speedometer extends ConsumerStatefulWidget {
  const Speedometer({super.key});

  @override
  ConsumerState<Speedometer> createState() => _SpeedometerState();
}

class _SpeedometerState extends ConsumerState<Speedometer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _cur = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _anim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _update(double target) {
    if ((_cur - target).abs() < 0.002) return;
    _anim = Tween<double>(begin: _cur, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward(from: 0);
    _cur = target;
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(trainStateProvider);
    final target = (ts.actualPwm / BleConstants.maxPwm).clamp(0.0, 1.0);
    _update(target);

    return LayoutBuilder(builder: (ctx, box) {
      final sz =
          (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight);
      return SizedBox(
        width: sz,
        height: sz,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => CustomPaint(
                size: Size(sz, sz),
                painter: SpeedometerPainter(
                  needleValue: _anim.value,
                  outerRadius: sz / 2 - 8,
                ),
              ),
            ),
            Positioned(
              bottom: sz * 0.12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF222222)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${ts.level}',
                      style: TrainTheme.orbitronStyle(
                        fontSize: sz * 0.12,
                        color: Colors.white,
                        height: 1,
                        shadows: [
                          Shadow(
                              color: Colors.white.withOpacity(0.5),
                              blurRadius: 8)
                        ],
                      ),
                    ),
                    Text(
                      'NOTCH',
                      style: TrainTheme.rajdhaniStyle(
                        fontSize: sz * 0.04,
                        color: const Color(0xFF88C0D0),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}