import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart'; // 恢复引入主题，供上方指示板使用
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import 'emergency_stop.dart';

class DirectionPanel extends ConsumerWidget {
  const DirectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(trainStateProvider);
    final n = ref.read(trainStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          // 1. 恢复：顶部原有的状态指示板（点击也可以换向）
          _DirBoard(
            direction: ts.direction,
            isRunning: ts.isRunning,
            isSlave: ts.isSlave,
            onFwd: () => n.setForward(),
            onStop: () => n.setStop(),
            onRev: () => n.setReverse(),
          ),
          const SizedBox(height: 8),
          
          // 2. 替换：中间全新的极简赛博朋克滑动拉杆
          Expanded(
            child: _DirectionLever(
              direction: ts.direction,
              isRunning: ts.isRunning,
              isSlave: ts.isSlave,
              onChange: (d) {
                switch (d) {
                  case TrainDirection.forward: n.setForward(); break;
                  case TrainDirection.stop: n.setStop(); break;
                  case TrainDirection.reverse: n.setReverse(); break;
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          
          // 3. 底部：防误触长按急停按钮
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: EmergencyStop(),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 以下为恢复的原有上方指示板组件 (_DirBoard & _DirBtn)
// ==========================================

class _DirBoard extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final VoidCallback onFwd;
  final VoidCallback onStop;
  final VoidCallback onRev;

  const _DirBoard({
    required this.direction,
    required this.isRunning,
    required this.isSlave,
    required this.onFwd,
    required this.onStop,
    required this.onRev,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0B0D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TrainTheme.metalDark, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xE6000000), offset: Offset(0, 3), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _DirBtn(
            badge: 'F', label: '前进', eng: 'FWD',
            isActive: direction == TrainDirection.forward,
            color: TrainTheme.glowBlue,
            canTap: !isSlave && (!isRunning || direction != TrainDirection.reverse),
            onTap: onFwd,
          )),
          const SizedBox(width: 5),
          Expanded(child: _DirBtn(
            badge: 'S', label: '停车', eng: 'STOP',
            isActive: direction == TrainDirection.stop,
            color: TrainTheme.glowGreen,
            canTap: !isSlave,
            onTap: onStop,
          )),
          const SizedBox(width: 5),
          Expanded(child: _DirBtn(
            badge: 'R', label: '后退', eng: 'REV',
            isActive: direction == TrainDirection.reverse,
            color: TrainTheme.glowRed,
            canTap: !isSlave && (!isRunning || direction != TrainDirection.forward),
            onTap: onRev,
          )),
        ],
      ),
    );
  }
}

class _DirBtn extends StatelessWidget {
  final String badge;
  final String label;
  final String eng;
  final bool isActive;
  final Color color;
  final bool canTap;
  final VoidCallback onTap;

  const _DirBtn({
    required this.badge, required this.label, required this.eng,
    required this.isActive, required this.color, required this.canTap, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !canTap && !isActive;
    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.12) : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isActive ? color.withOpacity(0.3) : Colors.transparent),
          ),
          child: Column(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isActive ? color : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: isActive ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)] : null,
                ),
                child: Center(
                  child: Text(badge, style: TrainTheme.orbitronStyle(
                    fontSize: 12, fontWeight: FontWeight.w900,
                    color: isActive ? Colors.black : const Color(0xFF555555),
                  )),
                ),
              ),
              const SizedBox(height: 3),
              Text(label, style: TrainTheme.rajdhaniStyle(
                fontSize: 11, color: isActive ? Colors.white : TrainTheme.textDim,
              )),
              Text(eng, style: TrainTheme.rajdhaniStyle(
                fontSize: 8, color: (isActive ? Colors.white : TrainTheme.textDim).withOpacity(0.6),
              )),
              const SizedBox(height: 3),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color : const Color(0xFF222222),
                  boxShadow: isActive ? [BoxShadow(color: color, blurRadius: 8)] : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ==========================================
// 以下为全新的滑动拉杆组件及其相关画笔
// ==========================================

class _DirectionLever extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final ValueChanged<TrainDirection> onChange;

  const _DirectionLever({
    required this.direction,
    required this.isRunning,
    required this.isSlave,
    required this.onChange,
  });

  void _handleInteraction(double localX, double totalWidth) {
    if (isSlave) return;

    const double handleW = 34.0; // 把手宽度减小
    final double usableW = totalWidth - handleW;
    
    double ratio = (localX - handleW / 2) / usableW;
    ratio = ratio.clamp(0.0, 1.0);

    TrainDirection target;
    if (ratio < 0.33) {
      target = TrainDirection.forward;
    } else if (ratio > 0.66) {
      target = TrainDirection.reverse;
    } else {
      target = TrainDirection.stop;
    }

    if (target != direction) {
      if (isRunning && target != TrainDirection.stop && direction != TrainDirection.stop) {
        onChange(TrainDirection.stop);
      } else {
        onChange(target);
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isSlave ? 0.6 : 1.0,
      child: Container(
        // 【缩小内边距】
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2a2d34), Color(0xFF1a1c20)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.8), 
              offset: const Offset(0, 6), 
              blurRadius: 15
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部字母
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlowText('F', isActive: direction == TrainDirection.forward, color: const Color(0xFF3498db)),
                _GlowText('S', isActive: direction == TrainDirection.stop, color: const Color(0xFF2ecc71)),
                _GlowText('R', isActive: direction == TrainDirection.reverse, color: const Color(0xFFe74c3c)),
              ],
            ),
            
            // 【核心修复】将拉杆包裹在 Expanded 中，让它自适应剩余空间，消除所有溢出
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    const handleWidth = 34.0; // 缩小把手宽度 (原40)
                    final usableWidth = trackWidth - handleWidth;

                    double leftPos = 0;
                    if (direction == TrainDirection.stop) leftPos = usableWidth / 2;
                    if (direction == TrainDirection.reverse) leftPos = usableWidth;

                    // 动态计算把手高度：不能超过剩余可用高度，且最大不超过 46
                    final handleHeight = constraints.maxHeight.clamp(20.0, 46.0);
                    // 轨道高度按比例缩小
                    final trackHeight = 24.0;

                    return Center(
                      child: SizedBox(
                        height: handleHeight,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // 轨道
                            Container(
                              height: trackHeight,
                              width: trackWidth,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(trackHeight / 2),
                                border: Border(
                                  bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
                                ),
                                boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10)],
                              ),
                            ),
                            // 滑块
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              left: leftPos,
                              child: Container(
                                width: handleWidth,
                                height: handleHeight,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF5c6a7a), Color(0xFF34495e), Color(0xFF111111)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 8, offset: Offset(4, 4))],
                                ),
                                child: CustomPaint(painter: _GripPainter()),
                              ),
                            ),
                            // 事件捕获层
                            Positioned.fill(
                              child: GestureDetector(
                                onTapDown: (d) => _handleInteraction(d.localPosition.dx, trackWidth),
                                onPanUpdate: (d) => _handleInteraction(d.localPosition.dx, trackWidth),
                                behavior: HitTestBehavior.opaque,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ),
            ),

            // 底部文字
            const Text('DIRECTION', style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 9, // 稍微缩小字号
              fontWeight: FontWeight.bold,
              color: Color(0xFF555555),
              letterSpacing: 4,
            )),
          ],
        ),
      ),
    );
  }
}

class _GlowText extends StatelessWidget {
  final String text;
  final bool isActive;
  final Color color;

  const _GlowText(this.text, {required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 18, // 【缩小字号】从 24 缩小到 18
        fontWeight: FontWeight.w900,
        color: isActive ? color : const Color(0xFF333333),
        shadows: isActive 
          ? [Shadow(color: color, blurRadius: 10)] 
          : [const Shadow(color: Colors.black, offset: Offset(0, -1), blurRadius: 1)],
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..strokeWidth = 2;
    // 动态适配变小后的把手高度，增加横线密度
    for (double y = 8; y < size.height - 6; y += 5) {
      canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}