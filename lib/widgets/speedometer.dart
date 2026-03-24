import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';

class Speedometer extends ConsumerWidget {
  const Speedometer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(trainStateProvider);
    final speed = ts.speed.toDouble(); // 直接使用 ESP32 上报的速度
    final isBraking = ts.isBraking;

    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 380,
            height: 220,
            child: Stack(
              children: [
                // 1. 仪表盘背景、刻度、数字
                CustomPaint(
                  size: const Size(380, 220),
                  painter: _SpeedGaugeBgPainter(),
                ),

                // 2. 制动闪烁光晕
                if (isBraking) _BrakingGlow(),

                // 3. 指针
                Positioned(
                  bottom: 30,
                  left: 190,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: -math.pi / 2,
                      end: -math.pi / 2 + (speed.clamp(0, 160) / 160.0) * math.pi,
                    ),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
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
                        height: 170,
                        decoration: BoxDecoration(
                          color: const Color(0xFFe74c3c),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: const [
                            BoxShadow(color: Color(0xFFe74c3c), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. km/h 标签
                Positioned(
                  bottom: 85,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'km/h',
                      style: TrainTheme.rajdhaniStyle(
                        fontSize: 14,
                        color: const Color(0xFFa3d7e6).withOpacity(0.8),
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),

                // 5. 数字屏
                Positioned(
                  bottom: 12,
                  left: 120,
                  child: _SpeedDisplay(
                    speed: speed,
                    isBraking: isBraking,
                  ),
                ),

                // 6. 制动指示灯
                if (isBraking)
                  const Positioned(top: 18, left: 30, child: _BrakingIndicator()),
                if (isBraking)
                  const Positioned(top: 18, right: 30, child: _BrakingIndicator()),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 速度数字屏 — 带制动闪烁
// ==========================================

class _SpeedDisplay extends StatefulWidget {
  final double speed;
  final bool isBraking;
  const _SpeedDisplay({required this.speed, required this.isBraking});

  @override
  State<_SpeedDisplay> createState() => _SpeedDisplayState();
}

class _SpeedDisplayState extends State<_SpeedDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didUpdateWidget(_SpeedDisplay old) {
    super.didUpdateWidget(old);
    if (widget.isBraking && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!widget.isBraking && _blink.isAnimating) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (_, __) {
        final b = widget.isBraking ? _blink.value : 0.0;
        final borderColor = widget.isBraking
            ? Color.lerp(const Color(0xFF1a2026), TrainTheme.glowOrange, b)!
            : const Color(0xFF1a2026);

        return Container(
          width: 140,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              const BoxShadow(color: Color(0xCC000000), blurRadius: 15, offset: Offset(0, 5)),
              if (widget.isBraking)
                BoxShadow(color: TrainTheme.glowOrange.withOpacity(b * 0.3), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.isBraking)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, right: 4),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: TrainTheme.glowOrange.withOpacity(0.5 + b * 0.5),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.speed.round().toString(),
                    style: TrainTheme.orbitronStyle(
                      fontSize: 24,
                      color: widget.isBraking
                          ? Color.lerp(Colors.white, TrainTheme.glowOrange, b * 0.6)!
                          : Colors.white,
                      shadows: [
                        Shadow(
                          color: (widget.isBraking ? TrainTheme.glowOrange : Colors.white)
                              .withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ).copyWith(height: 1.0),
                  ),
                  Text(
                    widget.isBraking ? 'BRAKING' : 'km/h',
                    style: TrainTheme.rajdhaniStyle(
                      fontSize: 10,
                      color: widget.isBraking
                          ? TrainTheme.glowOrange.withOpacity(0.5 + b * 0.5)
                          : const Color(0xFFa3d7e6),
                      letterSpacing: 2,
                    ).copyWith(height: 1.2),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 制动光晕
// ==========================================

class _BrakingGlow extends StatefulWidget {
  @override
  State<_BrakingGlow> createState() => _BrakingGlowState();
}

class _BrakingGlowState extends State<_BrakingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(380, 220),
          painter: _BrakingGlowPainter(_ctrl.value),
        );
      },
    );
  }
}

class _BrakingGlowPainter extends CustomPainter {
  final double intensity;
  _BrakingGlowPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = TrainTheme.glowOrange.withOpacity(intensity * 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + intensity * 8);

    final bgRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      topLeft: const Radius.circular(188),
      topRight: const Radius.circular(188),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas.drawRRect(bgRect, paint);
  }

  @override
  bool shouldRepaint(_BrakingGlowPainter old) => old.intensity != intensity;
}

// ==========================================
// 制动指示灯
// ==========================================

class _BrakingIndicator extends StatefulWidget {
  const _BrakingIndicator();

  @override
  State<_BrakingIndicator> createState() => _BrakingIndicatorState();
}

class _BrakingIndicatorState extends State<_BrakingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final glow = 0.3 + _ctrl.value * 0.7;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TrainTheme.glowOrange.withOpacity(glow),
                boxShadow: [
                  BoxShadow(
                    color: TrainTheme.glowOrange.withOpacity(glow * 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'BRK',
              style: TrainTheme.orbitronStyle(
                fontSize: 8,
                color: TrainTheme.glowOrange.withOpacity(glow),
                letterSpacing: 1,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================
// 仪表盘背景 — 0~160 km/h
// ==========================================

class _SpeedGaugeBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const pivot = Offset(190, 190);

    // 1. 半圆背景
    final bgRect = RRect.fromRectAndCorners(
      const Rect.fromLTWH(0, 0, 380, 220),
      topLeft: const Radius.circular(190),
      topRight: const Radius.circular(190),
      bottomLeft: const Radius.circular(8),
      bottomRight: const Radius.circular(8),
    );

    final bgPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, 0.72),
        radius: 0.8,
        colors: const [Color(0xFF121c24), Color(0xFF06090c)],
        stops: const [0.35, 0.75],
      ).createShader(const Rect.fromLTWH(0, 0, 380, 220));

    canvas.drawRRect(bgRect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF1a2026)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(bgRect, borderPaint);

    // 2. 装饰环
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

    // 3. 刻度: 0-160 km/h
    //    主刻度每 20 km/h → 9 个 (0,20,...,160)
    //    每主刻度间 4 小格 → 共 32 小格, 每格 5 km/h
    const int totalTicks = 32;
    const double degPerTick = 180.0 / totalTicks;

    for (int i = 0; i <= totalTicks; i++) {
      final isMajor = i % 4 == 0;
      final angle = -math.pi / 2 + (i * degPerTick * math.pi / 180);

      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(angle);

      if (isMajor) {
        final speedVal = (i ~/ 4) * 20;

        // 分色：低速青、中速黄、高速红
        Color tickColor;
        if (speedVal > 120) {
          tickColor = const Color(0xFFe74c3c);
        } else if (speedVal > 60) {
          tickColor = const Color(0xFFf39c12);
        } else {
          tickColor = const Color(0xFFa3d7e6);
        }

        // 霓虹发光
        canvas.drawLine(
          const Offset(0, -190),
          const Offset(0, -166),
          Paint()
            ..color = tickColor.withOpacity(0.5)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawLine(
          const Offset(0, -190),
          const Offset(0, -166),
          Paint()
            ..color = tickColor
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round,
        );

        // 数字
        final textSpan = TextSpan(
          text: '$speedVal',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: speedVal >= 100 ? 20 : 24,
            color: const Color(0xFFe5e9f0),
            fontWeight: FontWeight.w700,
          ),
        );
        final tp = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tp.layout();

        canvas.translate(0, -135);
        canvas.rotate(-angle);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      } else {
        canvas.drawLine(
          const Offset(0, -190),
          const Offset(0, -178),
          Paint()
            ..color = Colors.white.withOpacity(0.6)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}