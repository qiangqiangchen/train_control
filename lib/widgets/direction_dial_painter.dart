/// 方向拨盘 CustomPainter
///
/// 使用 CustomPainter 绘制金属质感旋转拨盘。
/// 三个位置：F(-45°) / S(0°) / R(45°)
/// 包含：外环阴影、内环、刻度标记、旋钮、指针线等。

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/train_state.dart';
import '../theme/train_theme.dart';

class DirectionDialPainter extends CustomPainter {
  final TrainDirection direction;

  DirectionDialPainter({required this.direction});

  /// 方向对应的旋钮角度（弧度）
  double get _knobAngle {
    switch (direction) {
      case TrainDirection.forward:
        return -math.pi / 4; // -45°
      case TrainDirection.stop:
        return 0; // 0°
      case TrainDirection.reverse:
        return math.pi / 4; // 45°
    }
  }

  Color get _activeColor {
    switch (direction) {
      case TrainDirection.forward:
        return TrainTheme.glowBlue;
      case TrainDirection.stop:
        return TrainTheme.glowGreen;
      case TrainDirection.reverse:
        return TrainTheme.glowRed;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. 外环（深色背景环）
    _drawOuterRing(canvas, center, radius);

    // 2. 内环背景
    _drawInnerRing(canvas, center, radius * 0.82);

    // 3. 刻度标记（F/S/R）
    _drawMarks(canvas, center, radius);

    // 4. 旋钮手柄
    _drawKnobHandle(canvas, center, radius);

    // 5. 旋钮主体
    _drawKnob(canvas, center, radius * 0.455);

    // 6. 指针线
    _drawPointerLine(canvas, center, radius);
  }

  void _drawOuterRing(Canvas canvas, Offset center, double radius) {
    // 外环渐变
    final outerPaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.5, -0.5),
        end: const Alignment(0.5, 0.5),
        colors: [const Color(0xFF2A2D34), const Color(0xFF1A1C20)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, outerPaint);

    // 外环阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, radius - 2, shadowPaint);

    // 外环边框
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
  }

  void _drawInnerRing(Canvas canvas, Offset center, double radius) {
    final innerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [const Color(0xFF222222), const Color(0xFF111111)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, innerPaint);

    // 内阴影
    final innerShadowPaint = Paint()
      ..color = Colors.black
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 8);
    canvas.drawCircle(center, radius, innerShadowPaint);

    // 内边框
    final borderPaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, borderPaint);
  }

  void _drawMarks(Canvas canvas, Offset center, double radius) {
    // 三个标记位置: F(-45°), S(0°), R(45°)
    final marks = [
      _DialMark(
        'F',
        -math.pi / 4,
        direction == TrainDirection.forward,
        TrainTheme.glowBlue,
      ),
      _DialMark(
        'S',
        0,
        direction == TrainDirection.stop,
        TrainTheme.glowGreen,
      ),
      _DialMark(
        'R',
        math.pi / 4,
        direction == TrainDirection.reverse,
        TrainTheme.glowRed,
      ),
    ];

    for (final mark in marks) {
      // 刻度线位置（从顶部偏移）
      final tickAngle = mark.angle - math.pi / 2;
      final tickStart = radius * 0.62;
      final tickEnd = radius * 0.72;

      final startPoint = Offset(
        center.dx + tickStart * math.cos(tickAngle),
        center.dy + tickStart * math.sin(tickAngle),
      );
      final endPoint = Offset(
        center.dx + tickEnd * math.cos(tickAngle),
        center.dy + tickEnd * math.sin(tickAngle),
      );

      // 刻度线
      final tickPaint = Paint()
        ..color = mark.isActive ? mark.color : const Color(0xFF333333)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(startPoint, endPoint, tickPaint);

      // 发光效果
      if (mark.isActive) {
        final glowPaint = Paint()
          ..color = mark.color.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawLine(startPoint, endPoint, glowPaint);
      }

      // 文字
      final textRadius = radius * 0.82;
      final textPos = Offset(
        center.dx + textRadius * math.cos(tickAngle),
        center.dy + textRadius * math.sin(tickAngle),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: mark.label,
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: mark.isActive ? mark.color : const Color(0xFF555555),
            shadows: mark.isActive
                ? [Shadow(color: mark.color, blurRadius: 10)]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        textPos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _drawKnobHandle(Canvas canvas, Offset center, double radius) {
    final angle = _knobAngle - math.pi / 2;
    final handleLength = radius * 0.34;
    final handleWidth = 24.0;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_knobAngle);

    // 手柄（从旋钮中心向上延伸）
    final handleRect = Rect.fromCenter(
      center: Offset(0, -handleLength / 2 - 5),
      width: handleWidth,
      height: handleLength,
    );

    final handlePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF555555),
          const Color(0xFF888888),
          const Color(0xFF333333),
        ],
      ).createShader(handleRect);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        handleRect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ),
      handlePaint,
    );

    // 手柄阴影
    final handleShadow = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(4)),
      handleShadow,
    );

    canvas.restore();
  }

  void _drawKnob(Canvas canvas, Offset center, double radius) {
    // 外层旋钮
    final knobPaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.7, -0.7),
        end: const Alignment(0.7, 0.7),
        colors: [const Color(0xFF444444), const Color(0xFF222222)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, knobPaint);

    // 旋钮阴影
    final knobShadow = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(center + const Offset(0, 5), radius, knobShadow);

    // 旋钮边框
    final knobBorder = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, knobBorder);

    // 高光
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.2),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius - 2, highlightPaint);

    // 内层旋钮
    final innerRadius = radius * 0.6;
    final innerPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.0,
        colors: [const Color(0xFF555555), const Color(0xFF222222)],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawCircle(center, innerRadius, innerPaint);

    // 内层阴影
    final innerShadow = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center + const Offset(0, 3), innerRadius, innerShadow);

    final innerHighlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.2),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawCircle(center, innerRadius, innerHighlight);
  }

  void _drawPointerLine(Canvas canvas, Offset center, double radius) {
    final angle = _knobAngle - math.pi / 2;
    final lineStart = radius * 0.48;
    final lineEnd = radius * 0.66;

    final start = Offset(
      center.dx + lineStart * math.cos(angle),
      center.dy + lineStart * math.sin(angle),
    );
    final end = Offset(
      center.dx + lineEnd * math.cos(angle),
      center.dy + lineEnd * math.sin(angle),
    );

    // 红色指针线
    final pointerPaint = Paint()
      ..color = TrainTheme.glowRed
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, pointerPaint);

    // 内阴影效果
    final innerShadow = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 2);
    canvas.drawLine(start, end, innerShadow);
  }

  @override
  bool shouldRepaint(covariant DirectionDialPainter oldDelegate) =>
      oldDelegate.direction != direction;
}

class _DialMark {
  final String label;
  final double angle;
  final bool isActive;
  final Color color;

  _DialMark(this.label, this.angle, this.isActive, this.color);
}