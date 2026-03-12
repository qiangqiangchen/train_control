/// 工业仪表盘主题常量
///
/// 定义所有颜色、字体样式、阴影、渐变等视觉参数。
/// 严格对应 HTML 设计稿中的 CSS 变量和样式。

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TrainTheme {
  TrainTheme._();

  // === 基础色板 ===
  static const Color bodyBg = Color(0xFF050505);
  static const Color bgColor = Color(0xFF1A1B1F);
  static const Color panelBg = Color(0xFF222429);
  static const Color metalDark = Color(0xFF111111);
  static const Color metalLight = Color(0xFF444444);
  static const Color textDim = Color(0xFF4A505C);

  // === 发光色 ===
  static const Color glowGreen = Color(0xFF2ECC71);
  static const Color glowRed = Color(0xFFE74C3C);
  static const Color glowBlue = Color(0xFF3498DB);
  static const Color glowOrange = Color(0xFFF39C12);
  static const Color glowCyan = Color(0xFF00BCD4);
  static const Color muGlow = Color(0xFF0FDB8A);

  // === 面板渐变 ===
  static const LinearGradient dashboardGradient = LinearGradient(
    begin: Alignment(-0.7, -0.7),
    end: Alignment(0.7, 0.7),
    colors: [Color(0xFF2A2D34), Color(0xFF15161A)],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF25282E), Color(0xFF1A1C20)],
  );

  static const LinearGradient topBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1C1F24), Color(0xFF0A0B0D)],
  );

  static const LinearGradient metalBtnGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF35383F), Color(0xFF1E2025)],
  );

  // === 螺丝渐变 ===
  static const RadialGradient screwGradient = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0xFF555555), Color(0xFF222222), Color(0xFF111111)],
    stops: [0.0, 0.7, 1.0],
  );

  // === 阴影预设 ===
  static List<BoxShadow> panelShadow = [
    const BoxShadow(
      color: Color(0x0DFFFFFF),
      offset: Offset(0, 2),
      blurRadius: 3,
    ),
    const BoxShadow(
      color: Color(0x80000000),
      offset: Offset(0, -2),
      blurRadius: 5,
    ),
    const BoxShadow(
      color: Color(0x80000000),
      offset: Offset(0, 10),
      blurRadius: 15,
    ),
  ];

  static List<BoxShadow> lcdShadow = [
    const BoxShadow(
      color: Color(0xE6000000),
      offset: Offset(0, 3),
      blurRadius: 8,
    ),
    const BoxShadow(
      color: Color(0x1AFFFFFF),
      offset: Offset(0, 1),
      blurRadius: 0,
    ),
  ];

  static List<BoxShadow> dashboardOuterShadow = [
    const BoxShadow(
      color: Color(0xCC000000),
      offset: Offset(0, 20),
      blurRadius: 50,
    ),
    const BoxShadow(
      color: Color(0x1AFFFFFF),
      offset: Offset(0, 2),
      blurRadius: 2,
    ),
  ];

  // === 字体样式 ===
  static TextStyle get orbitronStyle => GoogleFonts.orbitron(
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );

  static TextStyle get orbitronBold => GoogleFonts.orbitron(
        fontWeight: FontWeight.w900,
        color: Colors.white,
      );

  static TextStyle get rajdhaniStyle => GoogleFonts.rajdhani(
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );

  static TextStyle get rajdhaniBold => GoogleFonts.rajdhani(
        fontWeight: FontWeight.w900,
        color: Colors.white,
      );

  // === 通用装饰 ===
  static BoxDecoration get panelDecoration => BoxDecoration(
        gradient: panelGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: metalDark, width: 2),
        boxShadow: panelShadow,
      );

  static BoxDecoration get lcdDecoration => BoxDecoration(
        color: const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: lcdShadow,
      );

  /// 发光色工具方法
  static Color glowColorForLevel(int level) {
    if (level <= 2) return glowGreen;
    if (level <= 5) return glowOrange;
    return glowRed;
  }

  /// LED 灯色 (0-based index)
  static Color ledColor(int index) {
    if (index <= 2) return glowGreen;
    if (index <= 5) return const Color(0xFFF1C40F);
    return glowRed;
  }

  /// 电池颜色
  static Color batteryColor(int percent) {
    if (percent > 50) return glowGreen;
    if (percent >= 20) return const Color(0xFFF1C40F);
    return glowRed;
  }
}