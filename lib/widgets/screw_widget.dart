import 'dart:math' as math;
import 'package:flutter/material.dart';

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
          colors: [Color(0xFF555555), Color(0xFF222222), Color(0xFF111111)],
          stops: [0, 0.7, 1],
        ),
        boxShadow: [
          BoxShadow(color: Colors.white.withOpacity(0.2), offset: const Offset(0, 0.5), blurRadius: 0.5),
          const BoxShadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 3),
        ],
      ),
      child: CustomPaint(painter: _ScrewPainter(size)),
    );
  }
}

class _ScrewPainter extends CustomPainter {
  final double sz;
  _ScrewPainter(this.sz);

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: sz * 0.6, height: sz * 0.12),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFF111111),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrewPainter old) => old.sz != sz;
}