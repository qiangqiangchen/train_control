// 覆盖: lib/widgets/emergency_stop.dart
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
    with TickerProviderStateMixin {
  bool _pressed = false;
  bool _triggered = false;
  late AnimationController _flash;
  late AnimationController _holdController; // 【新增】充能控制器

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
        
    // 【新增】2秒长按计时器
    _holdController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));

    // 监听进度，达到 1.0 (2秒) 时触发急停
    _holdController.addListener(() {
      if (_holdController.status == AnimationStatus.completed && !_triggered) {
        _triggered = true;
        ref.read(trainStateProvider.notifier).emergencyStop();
        _flash.forward().then((_) => _flash.reverse());
        HapticFeedback.heavyImpact();
      }
    });
  }

  @override
  void dispose() {
    _flash.dispose();
    _holdController.dispose();
    super.dispose();
  }

  // 提前松手的处理逻辑
  void _cancelHold() {
    setState(() => _pressed = false);
    
    // 如果动画还在进行中（且未触发），说明用户没按够2秒
    if (_holdController.isAnimating && !_triggered) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 请长按 2 秒触发急停',
              style: TrainTheme.rajdhaniStyle(fontSize: 14)),
          backgroundColor: TrainTheme.glowOrange.withOpacity(0.9),
          duration: const Duration(seconds: 1),
        ),
      );
    }
    // 进度回退
    _holdController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 80, // 【加高】为外层进度环留出空间
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底座金属框
          Container(
            width: 100,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFAAB1BD), width: 5),
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
          
          // 【新增】充能进度环 UI
          AnimatedBuilder(
            animation: _holdController,
            builder: (_, __) {
              if (_holdController.value == 0) return const SizedBox();
              return SizedBox(
                width: 76,
                height: 76,
                child: CircularProgressIndicator(
                  value: _holdController.value,
                  color: TrainTheme.glowRed,
                  strokeWidth: 4,
                  backgroundColor: Colors.black.withOpacity(0.5),
                ),
              );
            },
          ),

          // E-STOP 按钮本体
          AnimatedBuilder(
            animation: Listenable.merge([_flash, _holdController]),
            builder: (_, __) => GestureDetector(
              // 按下时开始充能
              onTapDown: (_) {
                _triggered = false;
                setState(() => _pressed = true);
                _holdController.forward(from: 0.0);
                HapticFeedback.lightImpact();
              },
              // 抬起或移开时取消充能
              onTapUp: (_) => _cancelHold(),
              onTapCancel: () => _cancelHold(),
              
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
                    colors: [Color(0xFFFF4757), Color(0xFFC0392B), Color(0xFF8B0000)],
                    stops: [0, 0.6, 1],
                  ),
                  boxShadow: [
                    if (!_pressed)
                      const BoxShadow(color: Color(0xCC000000), offset: Offset(0, 6), blurRadius: 12),
                    if (_pressed)
                      BoxShadow(color: TrainTheme.glowRed.withOpacity(0.6), blurRadius: 20),
                    if (_flash.value > 0 || _triggered)
                      BoxShadow(color: TrainTheme.glowRed.withOpacity(0.9), blurRadius: 30),
                    const BoxShadow(color: Color(0xFF111111), spreadRadius: 3),
                  ],
                ),
                child: Center(
                  // 如果充能中，文字动态提示
                  child: Text(
                    _pressed && !_triggered ? 'HOLD...' : 'E-STOP',
                    style: TrainTheme.orbitronStyle(
                      fontSize: 10,
                      color: Colors.white,
                      shadows: [
                        const Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2)
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}