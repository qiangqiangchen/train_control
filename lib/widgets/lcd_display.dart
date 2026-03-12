/// LCD 显示框组件
///
/// 模拟仪表盘上的 LCD 数字显示屏，深色背景 + 内阴影 + 发光文字。

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/train_theme.dart';

class LcdDisplay extends StatelessWidget {
  final String value;
  final String? unit;
  final Color color;
  final double fontSize;
  final Widget? prefix;

  const LcdDisplay({
    super.key,
    required this.value,
    this.unit,
    this.color = TrainTheme.glowCyan,
    this.fontSize = 16,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: TrainTheme.lcdDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix != null) ...[
            prefix!,
            const SizedBox(width: 6),
          ],
          Text(
            value,
            style: GoogleFonts.orbitron(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color,
              shadows: [
                Shadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 2),
            Text(
              unit!,
              style: GoogleFonts.rajdhani(
                fontSize: fontSize * 0.625,
                fontWeight: FontWeight.w700,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}