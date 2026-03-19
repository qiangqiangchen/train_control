import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/train_theme.dart';
import 'screens/dashboard_screen.dart';

void main() {
  // 用 runZonedGuarded 捕获所有异步异常
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    runApp(const ProviderScope(child: TrainControllerApp()));
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack: $stack');
  });
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
        colorScheme: const ColorScheme.dark(
          primary: TrainTheme.glowCyan,
          secondary: TrainTheme.glowGreen,
          surface: TrainTheme.panelBg,
          error: TrainTheme.glowRed,
        ),
      ),
      builder: (context, child) {
        // 全局错误UI兜底
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Material(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error: ${details.exceptionAsString()}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        };
        return child ?? const SizedBox();
      },
      home: const AppEntry(),
    );
  }
}

/// 入口页：先做权限和蓝牙检查，再进控制台
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // 延迟一帧确保 MaterialApp 已渲染
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (e) {
      debugPrint('Init error: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('启动失败', style: TrainTheme.rajdhaniStyle(fontSize: 18, color: Colors.red)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () { setState(() { _error = null; _ready = false; }); _init(); },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return Scaffold(
        backgroundColor: TrainTheme.bodyBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🚂', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              SizedBox(
                width: 30, height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: TrainTheme.glowCyan,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const DashboardScreen();
  }
}