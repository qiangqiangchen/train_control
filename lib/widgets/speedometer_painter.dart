import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/train_theme.dart';

class SpeedometerPainter extends CustomPainter {
  final double needleValue;
  final double outerRadius;

  SpeedometerPainter({required this.needleValue, this.outerRadius = 140});

  static const double _sa = -130;
  static const double _ea = 130;
  static const double _ta = 260;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final br = outerRadius * 0.88;

    // 外框
    canvas.drawCircle(c, outerRadius, Paint()..color = const Color(0xFF111111));
    canvas.drawCircle(c, outerRadius - 2, Paint()
      ..color = Colors.black
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 12));
    canvas.drawCircle(c, outerRadius + 4, Paint()
      ..color = const Color(0xFF2A2D34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8);
    canvas.drawCircle(c, outerRadius + 8, Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawCircle(c + const Offset(0, 4), outerRadius, Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // 背景
    canvas.drawCircle(c, br, Paint()..shader = RadialGradient(
      colors: [const Color(0xFF1A2A3A), const Color(0xFF0A1118), const Color(0xFF05080C)],
      stops: const [0, 0.8, 1],
    ).createShader(Rect.fromCircle(center: c, radius: br)));

    // 刻度
    for (int i = 0; i <= 16; i++) {
      final v = i / 16.0;
      final a = (_sa + v * _ta) * math.pi / 180 - math.pi / 2;
      final major = i % 2 == 0;
      final to = br * 0.96;
      final ti = major ? br * 0.83 : br * 0.88;
      canvas.drawLine(
        Offset(c.dx + ti * math.cos(a), c.dy + ti * math.sin(a)),
        Offset(c.dx + to * math.cos(a), c.dy + to * math.sin(a)),
        Paint()
          ..color = major ? const Color(0xFF88C0D0) : Colors.white
          ..strokeWidth = major ? 2.5 : 1.5
          ..strokeCap = StrokeCap.round,
      );
      if (major) {
        final nr = br * 0.70;
        final np = Offset(c.dx + nr * math.cos(a), c.dy + nr * math.sin(a));
        final tp = TextPainter(
          text: TextSpan(
            text: '${i ~/ 2}',
            style: TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: br * 0.12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE5E9F0),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, np - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // 指针
    final na = (_sa + needleValue * _ta) * math.pi / 180 - math.pi / 2;
    final nl = br * 0.85;
    final ne = Offset(c.dx + nl * math.cos(na), c.dy + nl * math.sin(na));
    canvas.drawLine(c, ne, Paint()
      ..color = TrainTheme.glowRed.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    final tipStart = Offset(c.dx + nl * 0.4 * math.cos(na), c.dy + nl * 0.4 * math.sin(na));
    canvas.drawLine(tipStart, ne, Paint()
      ..color = TrainTheme.glowRed
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(c, tipStart, Paint()
      ..color = TrainTheme.glowRed.withOpacity(0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);

    // 中心
    final cr = outerRadius * 0.1;
    canvas.drawCircle(c + const Offset(0, 2), cr, Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(c, cr, Paint()..shader = RadialGradient(
      colors: [const Color(0xFF555555), const Color(0xFF111111)],
    ).createShader(Rect.fromCircle(center: c, radius: cr)));
    canvas.drawCircle(c, cr, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white.withOpacity(0.25), Colors.transparent],
    ).createShader(Rect.fromCircle(center: c, radius: cr)));
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter old) => old.needleValue != needleValue;
}