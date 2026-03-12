/// 主控制面板页面
///
/// 工业仪表盘风格的主控制界面，包含三个面板：
/// 左面板(方向控制)、中面板(仪表+按钮)、右面板(油门+重联)。
/// 根据火车角色状态(独立/本务机/补机)切换不同UI模式。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';
import '../services/state_parser.dart';
import '../widgets/top_status_bar.dart';
import '../widgets/direction_panel.dart';
import '../widgets/speedometer.dart';
import '../widgets/control_buttons.dart';
import '../widgets/emergency_stop.dart';
import '../widgets/throttle_lever.dart';
import '../widgets/led_bar.dart';
import '../widgets/mu_monitor.dart';
import '../widgets/screw_widget.dart';
import '../widgets/couple_invite_dialog.dart';
import 'scan_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  StreamSubscription? _connectionSub;
  bool _showedInviteDialog = false;
  CoupleStatus _lastCoupleStatus = CoupleStatus.off;

  @override
  void initState() {
    super.initState();
    // 监听连接状态变化
    final bleService = ref.read(bleServiceProvider);
    _connectionSub = bleService.connectionStateStream.listen((state) {
      if (state == BleConnectionState.disconnected && mounted) {
        _handleDisconnect();
      } else if (state == BleConnectionState.reconnecting && mounted) {
        _showReconnectingOverlay();
      }
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    super.dispose();
  }

  void _handleDisconnect() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  void _showReconnectingOverlay() {
    // 显示重连提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '正在重连...',
              style: GoogleFonts.rajdhani(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        backgroundColor: TrainTheme.glowOrange.withOpacity(0.8),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showErrorToast(TrainError error) {
    if (error == TrainError.none) return;
    final message = StateParser.errorMessage(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⚠️ $message',
          style: GoogleFonts.rajdhani(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
        duration: const Duration(seconds: 2),
      ),
    );

    ref.read(trainStateProvider.notifier).clearError();
  }

  void _checkInviteDialog(TrainState trainState) {
    // 收到重联邀请时弹窗
    if (trainState.isInvited && !_showedInviteDialog) {
      _showedInviteDialog = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => CoupleInviteDialog(
              inviterMac: trainState.inviterMac ?? 'Unknown',
              onAcceptA: () {
                ref.read(trainStateProvider.notifier).acceptCoupleA();
                Navigator.pop(context);
              },
              onAcceptB: () {
                ref.read(trainStateProvider.notifier).acceptCoupleB();
                Navigator.pop(context);
              },
              onReject: () {
                Navigator.pop(context);
              },
            ),
          );
        }
      });
    } else if (!trainState.isInvited) {
      _showedInviteDialog = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trainState = ref.watch(trainStateProvider);
    final screenSize = MediaQuery.of(context).size;

    // 检查错误
    if (trainState.error != TrainError.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorToast(trainState.error);
      });
    }

    // 检查重联邀请
    _checkInviteDialog(trainState);

    return Scaffold(
      backgroundColor: TrainTheme.bodyBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [Color(0xFF1A1A24), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 1260,
                height: 880,
                child: Column(
                  children: [
                    // 顶部状态栏
                    const TopStatusBar(),
                    const SizedBox(height: 20),
                    // 主面板
                    _buildDashboard(trainState),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(TrainState trainState) {
    return Container(
      width: 1260,
      height: 800,
      decoration: BoxDecoration(
        gradient: TrainTheme.dashboardGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: TrainTheme.dashboardOuterShadow,
      ),
      child: Stack(
        children: [
          // 四角螺丝
          const Positioned(top: 10, left: 10, child: ScrewWidget()),
          const Positioned(top: 10, right: 10, child: ScrewWidget()),
          const Positioned(bottom: 10, left: 10, child: ScrewWidget()),
          const Positioned(bottom: 10, right: 10, child: ScrewWidget()),

          // 三面板主体
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // 左面板: 方向控制
                Expanded(
                  flex: 10,
                  child: _buildPanel(
                    child: const DirectionPanel(),
                  ),
                ),
                const SizedBox(width: 20),
                // 中面板: 仪表+按钮
                Expanded(
                  flex: 13,
                  child: _buildPanel(
                    child: _buildCenterPanel(),
                  ),
                ),
                const SizedBox(width: 20),
                // 右面板: 油门+重联
                Expanded(
                  flex: 10,
                  child: _buildPanel(
                    child: _buildRightPanel(),
                  ),
                ),
              ],
            ),
          ),

          // 补机只读覆盖层
          if (trainState.isSlave) _buildSlaveOverlay(),
        ],
      ),
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      decoration: TrainTheme.panelDecoration,
      child: Stack(
        children: [
          const Positioned(top: 10, left: 10, child: ScrewWidget(size: 14)),
          const Positioned(top: 10, right: 10, child: ScrewWidget(size: 14)),
          const Positioned(
              bottom: 10, left: 10, child: ScrewWidget(size: 14)),
          const Positioned(
              bottom: 10, right: 10, child: ScrewWidget(size: 14)),
          child,
        ],
      ),
    );
  }

  Widget _buildCenterPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 速度表盘
          const Speedometer(),
          const SizedBox(height: 15),
          // 功能按钮
          const ControlButtons(),
          const SizedBox(height: 15),
          // 紧急停车
          const EmergencyStop(),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 重联监视器
          const MuMonitor(),
          const SizedBox(height: 15),
          // 油门 + LED
          Expanded(
            child: Row(
              children: [
                // 油门拉杆
                const Expanded(
                  flex: 4,
                  child: ThrottleLever(),
                ),
                const SizedBox(width: 15),
                // LED 档位条
                const Expanded(
                  flex: 2,
                  child: LedBar(),
                ),
                const SizedBox(width: 8),
                // 档位标签
                _buildNotchLabels(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotchLabels() {
    return SizedBox(
      width: 55,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(9, (index) {
          final notch = 8 - index;
          final isLabeled = notch == 0 || notch == 4 || notch == 8;
          final color = notch <= 2
              ? TrainTheme.glowGreen
              : notch <= 5
                  ? const Color(0xFFF1C40F)
                  : TrainTheme.glowRed;

          if (!isLabeled) return const SizedBox(height: 40);

          return SizedBox(
            height: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'NOTCH',
                  style: GoogleFonts.rajdhani(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    shadows: [
                      Shadow(color: color.withOpacity(0.5), blurRadius: 5),
                    ],
                  ),
                ),
                Text(
                  '$notch',
                  style: GoogleFonts.rajdhani(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                    shadows: [
                      Shadow(color: color.withOpacity(0.5), blurRadius: 5),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 补机模式覆盖层
  Widget _buildSlaveOverlay() {
    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: TrainTheme.glowCyan.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: TrainTheme.glowCyan.withOpacity(0.1),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚂', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  '重联运行中',
                  style: GoogleFonts.rajdhani(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: TrainTheme.glowCyan,
                    shadows: [
                      Shadow(
                        color: TrainTheme.glowCyan.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '本务机控制中 — 操控权已移交',
                  style: GoogleFonts.rajdhani(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: TrainTheme.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}