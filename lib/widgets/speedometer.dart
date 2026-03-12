/// 速度表盘组件
///
/// 使用 SpeedometerPainter 绘制表盘，AnimationController 驱动指针平滑动画。
/// 中央数字显示当前档位 (LV)，单位 NOTCH。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
  late AnimationController _needleController;
  late Animation<double> _needleAnimation;
  double _currentNeedleValue = 0;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _needleAnimation =
        Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _needleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _needleController.dispose();
    super.dispose();
  }

  void _updateNeedle(double targetValue) {
    if ((_currentNeedleValue - targetValue).abs() < 0.001) return;

    _needleAnimation = Tween<double>(
      begin: _currentNeedleValue,
      end: targetValue,
    ).animate(
      CurvedAnimation(parent: _needleController, curve: Curves.easeOut),
    );

    _needleController.forward(from: 0);
    _currentNeedleValue = targetValue;
  }

  @override
  Widget build(BuildContext context) {
    final trainState = ref.watch(trainStateProvider);

    // APWM (0~255) → 表盘值 (0~1)
    final targetNeedleValue =
        trainState.actualPwm / BleConstants.maxPwm.toDouble();
    _updateNeedle(targetNeedleValue.clamp(0.0, 1.0));

    return SizedBox(
      width: 320,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 表盘
          AnimatedBuilder(
            animation: _needleAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(320, 320),
                painter: SpeedometerPainter(
                  needleValue: _needleAnimation.value,
                  outerRadius: 145,
                ),
              );
            },
          ),

          // 中央数字显示
          Positioned(
            bottom: 50,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: const Color(0xFF222222), width: 1),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x80000000),
                    offset: Offset(0, 2),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${trainState.level}',
                    style: GoogleFonts.orbitron(
                      fontSize: 45,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1,
                      shadows: [
                        Shadow(
                          color: Colors.white.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'NOTCH',
                    style: GoogleFonts.rajdhani(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
  }
}