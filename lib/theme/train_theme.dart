/// 工业仪表盘主题常量
/// 去掉 google_fonts 依赖，用系统字体兜底，避免网络加载卡住

import 'package:flutter/material.dart';

class TrainTheme {
  TrainTheme._();

  static const Color bodyBg = Color(0xFF050505);
  static const Color bgColor = Color(0xFF1A1B1F);
  static const Color panelBg = Color(0xFF222429);
  static const Color metalDark = Color(0xFF111111);
  static const Color metalLight = Color(0xFF444444);
  static const Color textDim = Color(0xFF4A505C);
  static const Color textLight = Color(0xFF7A8291);

  static const Color glowGreen = Color(0xFF2ECC71);
  static const Color glowRed = Color(0xFFE74C3C);
  static const Color glowBlue = Color(0xFF3498DB);
  static const Color glowOrange = Color(0xFFF39C12);
  static const Color glowCyan = Color(0xFF00BCD4);
  static const Color muGlow = Color(0xFF0FDB8A);
  static const Color glowYellow = Color(0xFFF1C40F);

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

  static BoxDecoration get panelDecoration => BoxDecoration(
        gradient: panelGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: metalDark, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x0DFFFFFF), offset: Offset(0, 2), blurRadius: 3),
          BoxShadow(color: Color(0x80000000), offset: Offset(0, -2), blurRadius: 5),
          BoxShadow(color: Color(0x80000000), offset: Offset(0, 10), blurRadius: 15),
        ],
      );

  static BoxDecoration get lcdDecoration => BoxDecoration(
        color: const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0xE6000000), offset: Offset(0, 3), blurRadius: 8),
          BoxShadow(color: Color(0x1AFFFFFF), offset: Offset(0, 1), blurRadius: 0),
        ],
      );

  /// 安全的字体样式 — 不依赖网络加载
  static TextStyle orbitronStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
    List<Shadow>? shadows,
    double letterSpacing = 0,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: 'RobotoMono', // 模拟器兜底用等宽字体
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      shadows: shadows,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle rajdhaniStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
    List<Shadow>? shadows,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: 'RobotoCondensed',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      shadows: shadows,
      letterSpacing: letterSpacing,
    );
  }

  static Color batteryColor(int percent) {
    if (percent > 50) return glowGreen;
    if (percent >= 20) return glowYellow;
    return glowRed;
  }

  static Color ledColor(int index) {
    if (index <= 2) return glowGreen;
    if (index <= 5) return glowYellow;
    return glowRed;
  }
}