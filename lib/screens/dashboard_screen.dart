import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';
import '../services/state_parser.dart';
import '../widgets/top_status_bar.dart';
import '../widgets/direction_panel.dart';
import '../widgets/speedometer.dart';
import '../widgets/control_buttons.dart';
import '../widgets/throttle_lever.dart';
import '../widgets/led_bar.dart';
import '../widgets/mu_monitor.dart';
import '../widgets/screw_widget.dart';
import '../widgets/couple_invite_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  StreamSubscription<BleConnectionState>? _connSub;
  bool _showedInvite = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = ref.read(bleServiceProvider);
      _connSub = ble.connectionStateStream.listen((s) {
        if (s == BleConnectionState.reconnecting && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('正在重连...', style: TrainTheme.rajdhaniStyle(fontSize: 14)),
              ]),
              backgroundColor: TrainTheme.glowOrange.withOpacity(0.8),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  void _checkInvite(TrainState ts) {
    if (ts.isInvited && !_showedInvite) {
      _showedInvite = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => CoupleInviteDialog(
            inviterMac: ts.inviterMac ?? 'Unknown',
            onAcceptA: () { ref.read(trainStateProvider.notifier).acceptCoupleA(); Navigator.pop(context); },
            onAcceptB: () { ref.read(trainStateProvider.notifier).acceptCoupleB(); Navigator.pop(context); },
            onReject: () => Navigator.pop(context),
          ),
        );
      });
    } else if (!ts.isInvited) {
      _showedInvite = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(trainStateProvider);

    if (ts.error != TrainError.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${StateParser.errorMessage(ts.error)}',
              style: TrainTheme.rajdhaniStyle(fontSize: 14)),
            backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
            duration: const Duration(seconds: 2),
          ),
        );
        ref.read(trainStateProvider.notifier).clearError();
      });
    }
    _checkInvite(ts);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF1A1A24), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                const TopStatusBar(),
                const SizedBox(height: 5),
                Expanded(child: _buildDashboard(ts)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(TrainState ts) {
    return Container(
      decoration: BoxDecoration(
        gradient: TrainTheme.dashboardGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), offset: Offset(0, 12), blurRadius: 30),
          BoxShadow(color: Color(0x1AFFFFFF), offset: Offset(0, 1), blurRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(top: 7, left: 7, child: ScrewWidget(size: 14)),
          const Positioned(top: 7, right: 7, child: ScrewWidget(size: 14)),
          const Positioned(bottom: 7, left: 7, child: ScrewWidget(size: 14)),
          const Positioned(bottom: 7, right: 7, child: ScrewWidget(size: 14)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(flex: 10, child: _panel(child: const DirectionPanel())),
                const SizedBox(width: 8),
                Expanded(flex: 13, child: _panel(child: _centerPanel())),
                const SizedBox(width: 8),
                Expanded(flex: 8, child: _panel(child: _rightPanel())),
              ],
            ),
          ),
          if (ts.isSlave) _slaveOverlay(),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      decoration: TrainTheme.panelDecoration,
      child: Stack(
        children: [
          const Positioned(top: 5, left: 5, child: ScrewWidget(size: 10)),
          const Positioned(top: 5, right: 5, child: ScrewWidget(size: 10)),
          const Positioned(bottom: 5, left: 5, child: ScrewWidget(size: 10)),
          const Positioned(bottom: 5, right: 5, child: ScrewWidget(size: 10)),
          child,
        ],
      ),
    );
  }

  Widget _centerPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          const Expanded(flex: 5, child: Speedometer()),
          const SizedBox(height: 8),
          const ControlButtons(),
          const SizedBox(height: 8),
          const Expanded(flex: 3, child: MuMonitor()),
        ],
      ),
    );
  }

  Widget _rightPanel() {
    return Padding(
      // 【修改点】增加了 bottom 的数值 (从 12 改为 42)，将整个推杆模块向上顶起，避开全面屏手势区
      padding: const EdgeInsets.only(left: 8, right: 8, top: 12, bottom: 42),
      child: Row(
        children: [
          const Expanded(flex: 5, child: ThrottleLever()),
          const SizedBox(width: 6),
          const SizedBox(width: 26, child: LedBar()),
          const SizedBox(width: 3),
          SizedBox(width: 36, child: _notchLabels()),
        ],
      ),
    );
  }
  
 Widget _notchLabels() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(9, (i) {
        final notch = 8 - i;
        final show = notch == 0 || notch == 4 || notch == 8;
        final color = notch <= 2
            ? TrainTheme.glowGreen
            : notch <= 5
                ? TrainTheme.glowYellow
                : TrainTheme.glowRed;
        if (!show) return const Expanded(child: SizedBox());
        return Expanded(
          child: FittedBox( // 【新增】FittedBox 防止刻度文本微小越界
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('N', style: TrainTheme.rajdhaniStyle(fontSize: 7, color: color)),
                Text('$notch', style: TrainTheme.rajdhaniStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: color,
                  shadows: [Shadow(color: color.withOpacity(0.5), blurRadius: 4)],
                )),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _slaveOverlay() {
    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TrainTheme.glowCyan.withOpacity(0.3), width: 2),
              boxShadow: [BoxShadow(color: TrainTheme.glowCyan.withOpacity(0.1), blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚂', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 8),
                Text('重联运行中', style: TrainTheme.rajdhaniStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: TrainTheme.glowCyan,
                )),
                const SizedBox(height: 4),
                Text('本务机控制中 — 操控权已移交', style: TrainTheme.rajdhaniStyle(
                  fontSize: 12, color: TrainTheme.textDim,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}