import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/train_theme.dart';
import '../providers/train_provider.dart';

class EmergencyStop extends ConsumerStatefulWidget {
  const EmergencyStop({super.key});

  @override
  ConsumerState<EmergencyStop> createState() => _EmergencyStopState();
}

class _EmergencyStopState extends ConsumerState<EmergencyStop>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late AnimationController _flash;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: const Color(0xFFAAB1BD), width: 5),
              boxShadow: [
                BoxShadow(
                    color: Colors.white.withOpacity(0.12),
                    offset: const Offset(0, 2),
                    blurRadius: 2),
                const BoxShadow(
                    color: Color(0xCC000000),
                    offset: Offset(0, 5),
                    blurRadius: 8),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _flash,
            builder: (_, __) => GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) {
                setState(() => _pressed = false);
                ref.read(trainStateProvider.notifier).emergencyStop();
                _flash.forward().then((_) => _flash.reverse());
                HapticFeedback.heavyImpact();
              },
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 64,
                height: 64,
                transform: Matrix4.identity()
                  ..scale(_pressed ? 0.92 : 1.0)
                  ..translate(0.0, _pressed ? 2.0 : 0.0),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    radius: 0.8,
                    colors: [
                      Color(0xFFFF4757),
                      Color(0xFFC0392B),
                      Color(0xFF8B0000)
                    ],
                    stops: [0, 0.6, 1],
                  ),
                  boxShadow: [
                    if (!_pressed)
                      const BoxShadow(
                          color: Color(0xCC000000),
                          offset: Offset(0, 6),
                          blurRadius: 12),
                    if (_pressed)
                      BoxShadow(
                          color: TrainTheme.glowRed.withOpacity(0.6),
                          blurRadius: 20),
                    if (_flash.value > 0)
                      BoxShadow(
                          color: TrainTheme.glowRed
                              .withOpacity(0.8 * _flash.value),
                          blurRadius: 25),
                    const BoxShadow(
                        color: Color(0xFF111111), spreadRadius: 3),
                  ],
                ),
                child: Center(
                  child: Text('E-STOP',
                      style: TrainTheme.orbitronStyle(
                        fontSize: 10,
                        color: Colors.white,
                        shadows: [
                          const Shadow(
                              color: Color(0xCC000000),
                              offset: Offset(0, 1),
                              blurRadius: 2)
                        ],
                      )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}