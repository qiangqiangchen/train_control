/// 紧急停车按钮
///
/// 大红色圆形按钮 + 金属保护框。
/// 按压动效：缩放 + 阴影变化 + 红色外发光。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../providers/train_provider.dart';

class EmergencyStop extends ConsumerStatefulWidget {
  const EmergencyStop({super.key});

  @override
  ConsumerState<EmergencyStop> createState() => _EmergencyStopState();
}

class _EmergencyStopState extends ConsumerState<EmergencyStop>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  void _onPress() {
    setState(() => _isPressed = true);
  }

  void _onRelease() {
    setState(() => _isPressed = false);
    ref.read(trainStateProvider.notifier).emergencyStop();

    // 闪光动效
    _flashController.forward().then((_) {
      _flashController.reverse();
    });

    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 金属保护框
          Container(
            width: 140,
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFAAB1BD),
                width: 8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.2),
                  offset: const Offset(0, 5),
                  blurRadius: 5,
                ),
                const BoxShadow(
                  color: Color(0x80000000),
                  offset: Offset(0, -5),
                  blurRadius: 5,
                ),
                const BoxShadow(
                  color: Color(0xCC000000),
                  offset: Offset(0, 10),
                  blurRadius: 15,
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // 按钮本体
          AnimatedBuilder(
            animation: _flashController,
            builder: (context, child) {
              return GestureDetector(
                onTapDown: (_) => _onPress(),
                onTapUp: (_) => _onRelease(),
                onTapCancel: () => setState(() => _isPressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 100,
                  height: 100,
                  transform: Matrix4.identity()
                    ..scale(_isPressed ? 0.95 : 1.0)
                    ..translate(0.0, _isPressed ? 5.0 : 0.0),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        Color(0xFFFF4757),
                        Color(0xFFC0392B),
                        Color(0xFF8B0000),
                      ],
                      stops: [0.0, 0.6, 1.0],
                    ),
                    boxShadow: [
                      if (!_isPressed)
                        const BoxShadow(
                          color: Color(0xCC000000),
                          offset: Offset(0, 10),
                          blurRadius: 20,
                        ),
                      if (!_isPressed)
                        BoxShadow(
                          color:
                              const Color(0xFFFF6464).withOpacity(0.5),
                          offset: const Offset(0, 5),
                          blurRadius: 10,
                        ),
                      if (_isPressed)
                        const BoxShadow(
                          color: Color(0xCC000000),
                          offset: Offset(0, 2),
                          blurRadius: 5,
                        ),
                      if (_isPressed)
                        const BoxShadow(
                          color: Color(0x80000000),
                          offset: Offset(0, 5),
                          blurRadius: 15,
                        ),
                      if (_isPressed)
                        BoxShadow(
                          color: TrainTheme.glowRed.withOpacity(0.6),
                          blurRadius: 30,
                        ),
                      // 闪光效果
                      if (_flashController.value > 0)
                        BoxShadow(
                          color: TrainTheme.glowRed
                              .withOpacity(0.8 * _flashController.value),
                          blurRadius: 40,
                        ),
                      const BoxShadow(
                        color: Color(0xFF111111),
                        blurRadius: 0,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'EMERGENCY',
                        style: GoogleFonts.roboto(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withOpacity(0.8),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'STOP',
                        style: GoogleFonts.orbitron(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [
                            const Shadow(
                              color: Color(0xCC000000),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}