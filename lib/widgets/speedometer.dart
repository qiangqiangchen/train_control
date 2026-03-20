import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../providers/train_provider.dart';

class Speedometer extends ConsumerWidget {
  const Speedometer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(trainStateProvider);
    // 限制在 0-8 档位之间
    final notch = ts.level.clamp(0, 8);

    // 使用 LayoutBuilder 和 FittedBox 保证仪表盘按 380x220 的完美比例等比缩放
    // 无论外部给多少空间，都能保证内部绝对定位不会错乱或溢出
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 380,
            height: 220,
            child: Stack(
              children: [
                // 1. 底层：仪表盘背景、装饰环、刻度和数字
                CustomPaint(
                  size: const Size(380, 220),
                  painter: _GaugeBgPainter(),
                ),

                // 2. 中层：红色动态指针
                Positioned(
                  bottom: 30, // 旋转轴心距离底部 30px
                  left: 190,  // 旋转轴心在正中间 (380 / 2)
                  child: TweenAnimationBuilder<double>(
                    // 将 0-8 档位转换为旋转弧度 (0档=-90度, 4档=0度, 8档=90度)
                    tween: Tween<double>(
                      begin: -math.pi / 2,
                      end: -math.pi / 2 + (notch * 22.5 * math.pi / 180),
                    ),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack, // 加入轻微的回弹效果
                    builder: (context, angle, child) {
                      return Transform.rotate(
                        angle: angle,
                        alignment: Alignment.bottomCenter,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 4,
                      height: 180,
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: 4,
                        height: 170, // 指针长度
                        decoration: BoxDecoration(
                          color: const Color(0xFFe74c3c),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: const [
                            BoxShadow(color: Color(0xFFe74c3c), blurRadius: 8)
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. 表层：NOTCH 文字
                Positioned(
                  bottom: 85,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'NOTCH',
                      style: TrainTheme.rajdhaniStyle(
                        fontSize: 14,
                        color: const Color(0xFFa3d7e6).withOpacity(0.8),
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),

                // 4. 表层：底部数字屏幕屏
                Positioned(
                  bottom: 12,
                  left: 150, // 居中: (380 - 80) / 2
                  child: Container(
                    width: 80,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: const Color(0xFF1a2026), width: 2),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Color(0xCC000000), blurRadius: 15, offset: Offset(0, 5)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$notch',
                          style: TrainTheme.orbitronStyle(
                            fontSize: 26,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.white.withOpacity(0.5), blurRadius: 8)
                            ],
                          ).copyWith(height: 1.0),
                        ),
                        Text(
                          'NOTCH',
                          style: TrainTheme.rajdhaniStyle(
                            fontSize: 10,
                            color: const Color(0xFFa3d7e6),
                            letterSpacing: 2,
                          ).copyWith(height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 纯手工绘制的仪表盘底盘 (还原 HTML 的 CSS 圆角、渐变和刻度)
class _GaugeBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 旋转圆心点 (底部向上 30px)
    const pivot = Offset(190, 190);

    // ==========================================
    // 1. 绘制主体半圆穹顶背景
    // ==========================================
    final bgRect = RRect.fromRectAndCorners(
      const Rect.fromLTWH(0, 0, 380, 220),
      topLeft: const Radius.circular(190),
      topRight: const Radius.circular(190),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );

    // 匹配 HTML 的 radial-gradient
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, 0.72), // 近似 190/220 的位置
        radius: 0.8,
        colors: const [Color(0xFF121c24), Color(0xFF06090c)],
        stops: const [0.35, 0.75],
      ).createShader(const Rect.fromLTWH(0, 0, 380, 220));

    // 添加阴影并绘制背景
    canvas.drawRRect(bgRect, bgPaint);

    // 边框
    final borderPaint = Paint()
      ..color = const Color(0xFF1a2026)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(bgRect, borderPaint);

    // ==========================================
    // 2. 绘制内部装饰线圈 (Ring)
    // ==========================================
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final ringBgPaint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..style = PaintingStyle.fill;

    final ringRect = Rect.fromCenter(center: pivot, width: 200, height: 200);
    canvas.drawArc(ringRect, math.pi, math.pi, true, ringBgPaint);
    canvas.drawArc(ringRect, math.pi, math.pi, false, ringPaint);

    // ==========================================
    // 3. 绘制刻度线与发光数字 (Ticks & Numbers)
    // ==========================================
    // 总共 -90度 到 +90度，划分为 24 小格 (每格 7.5度)
    for (int i = 0; i <= 24; i++) {
      final isMajor = i % 3 == 0;
      final angle = -math.pi / 2 + (i * 7.5 * math.pi / 180);

      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(angle);

      if (isMajor) {
        // 主刻度 (Major Tick)
        final tickPaint = Paint()
          ..color = const Color(0xFFa3d7e6)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round;

        // 绘制霓虹外发光
        canvas.drawLine(
          const Offset(0, -190), // 半径 190 处开始
          const Offset(0, -166), // 长度 24px
          Paint()
            ..color = const Color(0xFFa3d7e6).withOpacity(0.5)
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        // 绘制实心核心
        canvas.drawLine(const Offset(0, -190), const Offset(0, -166), tickPaint);

        // 绘制数字
        final notchVal = i ~/ 3;
        final textSpan = TextSpan(
          text: '$notchVal',
          style: const TextStyle(
            fontFamily: 'Rajdhani', // 确保你的项目中引入了此字体
            fontSize: 26,
            color: Color(0xFFe5e9f0),
            fontWeight: FontWeight.w700,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        textPainter.layout();

        // 移动到半径 135 的位置 (190 - 55 = 135)，并**反向旋转**抵消倾斜，保证数字绝对正立
        canvas.translate(0, -135);
        canvas.rotate(-angle);
        textPainter.paint(
            canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      } else {
        // 副刻度 (Minor Tick)
        final tickPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(0, -190), const Offset(0, -176), tickPaint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}