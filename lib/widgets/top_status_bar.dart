/// 顶部状态栏
///
/// 显示：设备连接状态、电压、电量、端位、编组等信息。
/// 金属质感面板，LCD 风格数字显示。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';
import 'lcd_display.dart';

class TopStatusBar extends ConsumerStatefulWidget {
  const TopStatusBar({super.key});

  @override
  ConsumerState<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends ConsumerState<TopStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainState = ref.watch(trainStateProvider);
    final connectionState = ref.watch(bleConnectionStateProvider);

    return Container(
      width: 1260,
      height: 60,
      decoration: BoxDecoration(
        gradient: TrainTheme.topBarGradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TrainTheme.metalDark, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            offset: const Offset(0, 2),
            blurRadius: 3,
          ),
          const BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(0, 10),
            blurRadius: 20,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        children: [
          // 车辆 & 连接状态
          _buildConnectionStatus(connectionState),
          const Spacer(),
          // 电压
          _buildStatusItem('电压', _buildVoltageDisplay(trainState)),
          const SizedBox(width: 20),
          // 电量
          _buildStatusItem('电量', _buildBatteryDisplay(trainState)),
          const SizedBox(width: 20),
          // 端位
          _buildStatusItem('端位', _buildCabDisplay(trainState)),
          const SizedBox(width: 20),
          // 编组
          _buildStatusItem('编组', _buildCoupleDisplay(trainState)),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, Widget value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.roboto(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF7A8291),
          ),
        ),
        const SizedBox(width: 10),
        value,
      ],
    );
  }

  Widget _buildConnectionStatus(AsyncValue<BleConnectionState> connState) {
    final state = connState.valueOrNull ?? BleConnectionState.disconnected;
    final isConnected = state == BleConnectionState.connected;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '车辆',
          style: GoogleFonts.roboto(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF7A8291),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: TrainTheme.lcdDecoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 连接状态指示灯
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? TrainTheme.glowGreen : TrainTheme.glowRed,
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected
                              ? TrainTheme.glowGreen
                              : TrainTheme.glowRed)
                          .withOpacity(0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'BLE_Train',
                style: GoogleFonts.orbitron(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF58A6FF),
                  shadows: [
                    Shadow(
                      color: const Color(0xFF58A6FF).withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoltageDisplay(TrainState state) {
    return LcdDisplay(
      value: state.batteryVoltage.toStringAsFixed(2),
      unit: 'V',
      color: TrainTheme.glowCyan,
    );
  }

  Widget _buildBatteryDisplay(TrainState state) {
    final color = TrainTheme.batteryColor(state.battery);
    final showBlink = state.batteryLow;

    return LcdDisplay(
      value: '${state.battery}',
      unit: '%',
      color: TrainTheme.glowGreen,
      prefix: AnimatedBuilder(
        animation: _blinkController,
        builder: (context, child) {
          final visible =
              !showBlink || _blinkController.value > 0.5;
          return Opacity(
            opacity: visible ? 1.0 : 0.3,
            child: _BatteryIcon(
              percent: state.battery,
              color: color,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCabDisplay(TrainState state) {
    final isA = state.cab == CabEnd.a;
    final color = isA ? TrainTheme.glowGreen : TrainTheme.glowOrange;
    final text = isA ? 'A端 CAB-A' : 'B端 CAB-B';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minWidth: 90),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          bottom: BorderSide(color: color, width: 2),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.rajdhani(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          shadows: [
            Shadow(color: color.withOpacity(0.8), blurRadius: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCoupleDisplay(TrainState state) {
    String text;
    Color color;
    bool blink = false;

    switch (state.coupleStatus) {
      case CoupleStatus.off:
        text = '独立 INDEP';
        color = const Color(0xFFAAAAAA);
      case CoupleStatus.inviting:
        text = '邀请中...';
        color = TrainTheme.glowOrange;
        blink = true;
      case CoupleStatus.invited:
        text = '收到邀请';
        color = TrainTheme.glowCyan;
        blink = true;
      case CoupleStatus.master:
        text = '本务 MASTER';
        color = TrainTheme.glowRed;
      case CoupleStatus.slave:
        text = '补机 SLAVE';
        color = TrainTheme.glowRed;
    }

    final bgColor = state.coupleStatus == CoupleStatus.off
        ? TrainTheme.metalDark
        : color.withOpacity(0.15);

    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(minWidth: 90),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          bottom: BorderSide(
            color: state.coupleStatus == CoupleStatus.off
                ? TrainTheme.metalLight
                : color,
            width: 2,
          ),
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.rajdhani(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: state.coupleStatus == CoupleStatus.off
              ? const Color(0xFFAAAAAA)
              : Colors.white,
          shadows: state.coupleStatus == CoupleStatus.off
              ? null
              : [Shadow(color: color.withOpacity(0.8), blurRadius: 8)],
        ),
      ),
    );

    if (blink) {
      content = AnimatedBuilder(
        animation: _blinkController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.5 + 0.5 * _blinkController.value,
            child: child,
          );
        },
        child: content,
      );
    }

    return content;
  }
}

/// 电池图标
class _BatteryIcon extends StatelessWidget {
  final int percent;
  final Color color;

  const _BatteryIcon({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 12,
      child: CustomPaint(
        painter: _BatteryIconPainter(
          percent: percent,
          color: color,
        ),
      ),
    );
  }
}

class _BatteryIconPainter extends CustomPainter {
  final int percent;
  final Color color;

  _BatteryIconPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 电池主体
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - 4, size.height),
      const Radius.circular(2),
    );
    canvas.drawRRect(bodyRect, borderPaint);

    // 电池头部
    final tipPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            size.width - 4, size.height * 0.25, 3, size.height * 0.5),
        const Radius.circular(1),
      ),
      tipPaint,
    );

    // 填充
    final fillWidth = (size.width - 8) * (percent / 100.0);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(2, 2, fillWidth.clamp(0, size.width - 8), size.height - 4),
      fillPaint,
    );

    // 发光
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(
      Rect.fromLTWH(2, 2, fillWidth.clamp(0, size.width - 8), size.height - 4),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BatteryIconPainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.color != color;
}