/// 螺丝装饰组件
///
/// 模拟工业面板四角的螺丝，使用 RadialGradient 实现金属质感。

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/train_theme.dart';

class ScrewWidget extends StatelessWidget {
  final double size;

  const ScrewWidget({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [Color(0xFF555555), Color(0xFF222222), Color(0xFF111111)],
          stops: [0.0, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.3),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
          const BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ScrewSlotPainter(size),
      ),
    );
  }
}

class _ScrewSlotPainter extends CustomPainter {
  final double size;
  _ScrewSlotPainter(this.size);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final slotWidth = size * 0.625;
    final slotHeight = size * 0.125;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi / 4);

    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset.zero, width: slotWidth, height: slotHeight),
        const Radius.circular(1),
      ),
      paint,
    );

    // 高光线
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: const Offset(0, 1),
            width: slotWidth,
            height: slotHeight * 0.5),
        const Radius.circular(0.5),
      ),
      highlightPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrewSlotPainter oldDelegate) =>
      oldDelegate.size != size;
}