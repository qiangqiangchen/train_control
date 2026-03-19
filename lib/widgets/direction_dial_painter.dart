import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/train_state.dart';
import '../theme/train_theme.dart';

class DirectionDialPainter extends CustomPainter {
  final TrainDirection direction;
  DirectionDialPainter({required this.direction});

  double get _angle {
    switch (direction) {
      case TrainDirection.forward: return -math.pi / 4;
      case TrainDirection.stop: return 0;
      case TrainDirection.reverse: return math.pi / 4;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // 外环
    canvas.drawCircle(c, r, Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.5, -0.5),
        end: Alignment(0.5, 0.5),
        colors: [Color(0xFF2A2D34), Color(0xFF1A1C20)],
      ).createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r - 1, Paint()..color = Colors.black.withOpacity(0.7)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(c, r, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // 内环
    final ir = r * 0.8;
    canvas.drawCircle(c, ir, Paint()..shader = RadialGradient(
      colors: [const Color(0xFF222222), const Color(0xFF111111)],
    ).createShader(Rect.fromCircle(center: c, radius: ir)));
    canvas.drawCircle(c, ir, Paint()..color = const Color(0xFF333333)..style = PaintingStyle.stroke..strokeWidth = 0.5);

    // 刻度标记
    final marks = <_Mark>[
      _Mark('F', -math.pi / 4, direction == TrainDirection.forward, TrainTheme.glowBlue),
      _Mark('S', 0, direction == TrainDirection.stop, TrainTheme.glowGreen),
      _Mark('R', math.pi / 4, direction == TrainDirection.reverse, TrainTheme.glowRed),
    ];

    for (final m in marks) {
      final a = m.angle - math.pi / 2;
      final ts = r * 0.58;
      final te = r * 0.70;
      final p1 = Offset(c.dx + ts * math.cos(a), c.dy + ts * math.sin(a));
      final p2 = Offset(c.dx + te * math.cos(a), c.dy + te * math.sin(a));
      canvas.drawLine(p1, p2, Paint()
        ..color = m.active ? m.color : const Color(0xFF333333)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round);
      if (m.active) {
        canvas.drawLine(p1, p2, Paint()
          ..color = m.color.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }

      final tr = r * 0.82;
      final tp = Offset(c.dx + tr * math.cos(a), c.dy + tr * math.sin(a));
      final painter = TextPainter(
        text: TextSpan(
          text: m.label,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: r * 0.14,
            fontWeight: FontWeight.w900,
            color: m.active ? m.color : const Color(0xFF555555),
            shadows: m.active ? [Shadow(color: m.color, blurRadius: 8)] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      painter.paint(canvas, tp - Offset(painter.width / 2, painter.height / 2));
    }

    // 手柄
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_angle);
    final hw = r * 0.10;
    final hl = r * 0.32;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(0, -hl / 2 - 4), width: hw, height: hl),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF555555), Color(0xFF888888), Color(0xFF333333)],
      ).createShader(Rect.fromCenter(center: Offset(0, -hl / 2), width: hw, height: hl)),
    );
    canvas.restore();

    // 旋钮
    final kr = r * 0.42;
    canvas.drawCircle(c + const Offset(0, 3), kr, Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawCircle(c, kr, Paint()..shader = const LinearGradient(
      begin: Alignment(-0.7, -0.7),
      end: Alignment(0.7, 0.7),
      colors: [Color(0xFF444444), Color(0xFF222222)],
    ).createShader(Rect.fromCircle(center: c, radius: kr)));
    canvas.drawCircle(c, kr, Paint()..color = const Color(0xFF111111)..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(c, kr, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white.withOpacity(0.15), Colors.transparent],
    ).createShader(Rect.fromCircle(center: c, radius: kr)));

    final ikr = kr * 0.55;
    canvas.drawCircle(c, ikr, Paint()..shader = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      colors: [const Color(0xFF555555), const Color(0xFF222222)],
    ).createShader(Rect.fromCircle(center: c, radius: ikr)));

    // 指针线
    final pa = _angle - math.pi / 2;
    final ls = r * 0.44;
    final le = r * 0.62;
    canvas.drawLine(
      Offset(c.dx + ls * math.cos(pa), c.dy + ls * math.sin(pa)),
      Offset(c.dx + le * math.cos(pa), c.dy + le * math.sin(pa)),
      Paint()..color = TrainTheme.glowRed..strokeWidth = 3..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant DirectionDialPainter old) => old.direction != direction;
}

class _Mark {
  final String label;
  final double angle;
  final bool active;
  final Color color;
  _Mark(this.label, this.angle, this.active, this.color);
}