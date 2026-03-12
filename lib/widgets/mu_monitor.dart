/// 重联监视器组件
///
/// CRT 屏幕风格的重联状态监视面板。
/// 显示补机连接状态、电量、速度、系数调节等。
/// 包含 CRT 扫描线效果和通信异常警告。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';

class MuMonitor extends ConsumerStatefulWidget {
  const MuMonitor({super.key});

  @override
  ConsumerState<MuMonitor> createState() => _MuMonitorState();
}

class _MuMonitorState extends ConsumerState<MuMonitor>
    with SingleTickerProviderStateMixin {
  late AnimationController _warnController;

  @override
  void initState() {
    super.initState();
    _warnController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _warnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainState = ref.watch(trainStateProvider);
    final notifier = ref.read(trainStateProvider.notifier);
    final isMaster = trainState.isMaster;
    final isSlave = trainState.isSlave;
    final isOff = !isMaster && !isSlave;

    return Opacity(
      opacity: isOff ? 0.4 : 1.0,
      child: ColorFiltered(
        colorFilter: isOff
            ? const ColorFilter.mode(
                Colors.grey, BlendMode.saturation)
            : const ColorFilter.mode(
                Colors.transparent, BlendMode.multiply),
        child: Container(
          width: double.infinity,
          height: 150,
          decoration: BoxDecoration(
            color: const Color(0xFF070E14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: TrainTheme.metalDark, width: 2),
            boxShadow: [
              const BoxShadow(
                color: Color(0xE6000000),
                offset: Offset(0, 3),
                blurRadius: 15,
              ),
              const BoxShadow(
                color: Color(0x80000000),
                offset: Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Stack(
            children: [
              // CRT 扫描线效果
              Positioned.fill(
                child: CustomPaint(
                  painter: _CrtScanlinePainter(),
                ),
              ),

              // 内容
              Padding(
                padding: const EdgeInsets.all(12),
                child: isSlave
                    ? _buildSlaveView(trainState)
                    : _buildMasterView(trainState, notifier),
              ),

              // 通信异常警告
              if (trainState.slaveWarning && isMaster)
                _buildWarningOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMasterView(
      TrainState trainState, TrainStateNotifier notifier) {
    final isMaster = trainState.isMaster;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 第一行：连接状态 + 电量
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '🔗 补机: ${isMaster ? "已连接 (${trainState.slaveCab == CabEnd.a ? 'A端' : 'B端'})" : "未连接"}',
              style: _muTextStyle(14),
            ),
            if (isMaster)
              Text(
                '🔋 ${trainState.slaveBattery ?? 0}% ${trainState.slaveBatteryVoltage?.toStringAsFixed(2) ?? "0.00"}V',
                style: _muTextStyle(13),
              ),
          ],
        ),

        // 第二行：速度条
        Row(
          children: [
            Text('速度:', style: _muTextStyle(13)),
            const SizedBox(width: 8),
            Expanded(
              child: _SpeedBar(
                value: isMaster
                    ? (trainState.slaveActualPwm ?? 0) / 255.0
                    : 0,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isMaster
                  ? '${trainState.slaveActualPwm ?? 0}/${trainState.targetPwm}'
                  : '0/0',
              style: _muTextStyle(14),
            ),
          ],
        ),

        // 第三行：系数调节
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '系数: ${(trainState.speedCoefficient ?? 1.0).toStringAsFixed(2)}',
                  style: _muTextStyle(13),
                ),
                Row(
                  children: [
                    _MuCtrlButton(
                      label: '◀',
                      onTap: isMaster
                          ? () {
                              final current =
                                  trainState.speedCoefficient ?? 1.0;
                              notifier.setSpeedCoefficient(
                                  current - BleConstants.coefficientStep);
                              HapticFeedback.selectionClick();
                            }
                          : null,
                    ),
                    const SizedBox(width: 5),
                    _MuCtrlButton(
                      label: '▶',
                      onTap: isMaster
                          ? () {
                              final current =
                                  trainState.speedCoefficient ?? 1.0;
                              notifier.setSpeedCoefficient(
                                  current + BleConstants.coefficientStep);
                              HapticFeedback.selectionClick();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 滑块
            Row(
              children: [
                Text('0.90', style: _muTextStyle(11)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      activeTrackColor: TrainTheme.muGlow,
                      inactiveTrackColor: TrainTheme.metalDark,
                      thumbColor: TrainTheme.muGlow,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                      overlayColor:
                          TrainTheme.muGlow.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: (trainState.speedCoefficient ?? 1.0)
                          .clamp(BleConstants.minCoefficient,
                              BleConstants.maxCoefficient),
                      min: BleConstants.minCoefficient,
                      max: BleConstants.maxCoefficient,
                      divisions: 20,
                      onChanged: isMaster
                          ? (val) {
                              notifier.setSpeedCoefficient(val);
                            }
                          : null,
                    ),
                  ),
                ),
                Text('1.10', style: _muTextStyle(11)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSlaveView(TrainState trainState) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🔗 补机模式',
            style: _muTextStyle(16),
          ),
          const SizedBox(height: 8),
          Text(
            '操控权已移交本务机',
            style: _muTextStyle(12).copyWith(
              color: TrainTheme.muGlow.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'LV:${trainState.level} PWM:${trainState.actualPwm} HL:${trainState.headlight ? "ON" : "OFF"} SE:${trainState.soundEnabled ? "ON" : "OFF"}',
            style: _muTextStyle(11).copyWith(
              color: TrainTheme.muGlow.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningOverlay() {
    return AnimatedBuilder(
      animation: _warnController,
      builder: (context, child) {
        return Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(
                const Color(0xE6320000),
                const Color(0xD9140000),
                _warnController.value,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFF3333), width: 2),
            ),
            child: Center(
              child: Opacity(
                opacity: 0.6 + 0.4 * _warnController.value,
                child: Text(
                  '⚠️ 补机通信异常',
                  style: GoogleFonts.orbitron(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF3333),
                    letterSpacing: 2,
                    shadows: [
                      const Shadow(
                        color: Color(0xFFFF3333),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _muTextStyle(double size) {
    return GoogleFonts.orbitron(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: TrainTheme.muGlow,
      shadows: [
        Shadow(
          color: TrainTheme.muGlow.withOpacity(0.6),
          blurRadius: 6,
        ),
      ],
    );
  }
}

/// CRT 扫描线效果
class _CrtScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.15);

    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 补机速度条
class _SpeedBar extends StatelessWidget {
  final double value; // 0~1

  const _SpeedBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: TrainTheme.metalDark, width: 1),
        boxShadow: [
          const BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(
                color: TrainTheme.muGlow.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _StripedBarPainter(),
          ),
        ),
      ),
    );
  }
}

/// 斜条纹填充
class _StripedBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = TrainTheme.muGlow;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 斜条纹
    final stripePaint = Paint()..color = const Color(0xFF0A8A56);
    const stripeWidth = 5.0;

    for (double x = -size.height; x < size.width + size.height;
        x += stripeWidth * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripeWidth, size.height)
        ..lineTo(x + stripeWidth + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, stripePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 重联控制小按钮
class _MuCtrlButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const _MuCtrlButton({required this.label, this.onTap});

  @override
  State<_MuCtrlButton> createState() => _MuCtrlButtonState();
}

class _MuCtrlButtonState extends State<_MuCtrlButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _pressed = false)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _pressed ? TrainTheme.muGlow : Colors.black,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: TrainTheme.muGlow, width: 1),
          boxShadow: [
            BoxShadow(
              color: TrainTheme.muGlow.withOpacity(0.2),
              offset: Offset.zero,
              blurRadius: 5,
            ),
          ],
        ),
        child: Text(
          widget.label,
          style: GoogleFonts.orbitron(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _pressed ? Colors.black : TrainTheme.muGlow,
          ),
        ),
      ),
    );
  }
}