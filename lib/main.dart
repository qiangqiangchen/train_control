/// BLE 火车遥控器 - 主入口文件
/// 
/// 初始化 Flutter 环境，强制横屏，配置主题和路由。
/// 使用 Riverpod 进行全局状态管理。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/train_theme.dart';
import 'screens/scan_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 强制横屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 隐藏系统状态栏和导航栏，全屏沉浸
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  runApp(const ProviderScope(child: TrainControllerApp()));
}

class TrainControllerApp extends StatelessWidget {
  const TrainControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Train Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TrainTheme.bodyBg,
        textTheme: GoogleFonts.robotoTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: TrainTheme.glowCyan,
          secondary: TrainTheme.glowGreen,
          surface: TrainTheme.panelBg,
          error: TrainTheme.glowRed,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}