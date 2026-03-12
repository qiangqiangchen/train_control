/// 速度表盘 CustomPainter
///
/// 绘制工业风格速度表盘，范围 0~8 档位。
/// 包含：表盘背景、刻度线、数字、指针、中心轴等。
/// 指针由 APWM (0~255) 驱动。

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/train_theme.dart';

class SpeedometerPainter extends CustomPainter {
  /// 指针角度值，0.0~1.0 (0=最左侧,1=最右侧)
  final double needleValue;

  /// 表盘半径
  final double outerRadius;

  SpeedometerPainter({
    required this.needleValue,
    this.outerRadius = 160,
  });

  // 表盘角度范围（与 HTML 设计稿一致）
  static const double _startAngle = -130.0; // 度
  static const double _endAngle = 130.0;
  static const double _totalAngle = _endAngle - _startAngle; // 260度

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bgRadius = outerRadius * 0.875; // speedo-bg 280/320

    // 1. 外框
    _drawOuterFrame(canvas, center, outerRadius);

    // 2. 表盘背景
    _drawBackground(canvas, center, bgRadius);

    // 3. 刻度和数字
    _drawTicks(canvas, center, bgRadius);

    // 4. 指针
    _drawNeedle(canvas, center, bgRadius);

    // 5. 中心轴
    _drawCenter(canvas, center);
  }

  void _drawOuterFrame(Canvas canvas, Offset center, double radius) {
    // 黑色外框
    final framePaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, framePaint);

    // 内阴影效果
    final innerShadow = Paint()
      ..color = Colors.black
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 15);
    canvas.drawCircle(center, radius, innerShadow);

    // 外层金属环
    final metalRing = Paint()
      ..color = const Color(0xFF2A2D34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius + 5, metalRing);

    // 外层黑边
    final outerBorder = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius + 10, outerBorder);

    // 外阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center + const Offset(0, 5), radius, shadowPaint);
  }

  void _drawBackground(Canvas canvas, Offset center, double radius) {
    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          const Color(0xFF1A2A3A),
          const Color(0xFF0A1118),
          const Color(0xFF05080C),
        ],
        stops: const [0.0, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    const maxNotch = 8;

    // 主刻度 (0~8) 和次刻度
    for (int i = 0; i <= maxNotch * 2; i++) {
      final value = i / (maxNotch * 2);
      final angle = (_startAngle + value * _totalAngle) * math.pi / 180;

      final isMajor = i % 2 == 0;
      final tickOuter = radius * 0.96;
      final tickInner = isMajor ? radius * 0.83 : radius * 0.88;

      final outerPoint = Offset(
        center.dx + tickOuter * math.cos(angle - math.pi / 2),
        center.dy + tickOuter * math.sin(angle - math.pi / 2),
      );
      final innerPoint = Offset(
        center.dx + tickInner * math.cos(angle - math.pi / 2),
        center.dy + tickInner * math.sin(angle - math.pi / 2),
      );

      final tickPaint = Paint()
        ..color = isMajor ? const Color(0xFF88C0D0) : Colors.white
        ..strokeWidth = isMajor ? 3 : 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(innerPoint, outerPoint, tickPaint);

      // 主刻度数字
      if (isMajor) {
        final numRadius = radius * 0.7;
        final numPos = Offset(
          center.dx + numRadius * math.cos(angle - math.pi / 2),
          center.dy + numRadius * math.sin(angle - math.pi / 2),
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i ~/ 2}',
            style: const TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE5E9F0),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          numPos - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius) {
    final angle =
        (_startAngle + needleValue * _totalAngle) * math.pi / 180 -
            math.pi / 2;

    final needleLength = radius * 0.86;

    // 指针发光
    final glowPaint = Paint()
      ..color = TrainTheme.glowRed.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final needleEnd = Offset(
      center.dx + needleLength * math.cos(angle),
      center.dy + needleLength * math.sin(angle),
    );

    canvas.drawLine(center, needleEnd, glowPaint);

    // 指针本体（渐变）
    final needlePaint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          TrainTheme.glowRed.withOpacity(0.3),
          TrainTheme.glowRed,
          const Color(0xFFFF7675),
        ],
        stops: const [0.0, 0.2, 0.6, 1.0],
      ).createShader(
        Rect.fromPoints(center, needleEnd),
      );

    canvas.drawLine(center, needleEnd, needlePaint);

    // 指针红色尖端
    final tipPaint = Paint()
      ..color = TrainTheme.glowRed
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final tipStart = Offset(
      center.dx + (needleLength * 0.5) * math.cos(angle),
      center.dy + (needleLength * 0.5) * math.sin(angle),
    );

    canvas.drawLine(tipStart, needleEnd, tipPaint);
  }

  void _drawCenter(Canvas canvas, Offset center) {
    // 中心轴外环
    final centerRadius = 17.5;

    final centerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [const Color(0xFF555555), const Color(0xFF111111)],
      ).createShader(Rect.fromCircle(center: center, radius: centerRadius));
    canvas.drawCircle(center, centerRadius, centerPaint);

    // 高光
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: centerRadius));
    canvas.drawCircle(center, centerRadius, highlightPaint);

    // 阴影
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(0, 3), centerRadius, shadowPaint);
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) =>
      oldDelegate.needleValue != needleValue;
}