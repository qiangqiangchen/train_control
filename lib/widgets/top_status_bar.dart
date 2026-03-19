import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';
import 'train_manager_sheet.dart';

class TopStatusBar extends ConsumerStatefulWidget {
  const TopStatusBar({super.key});

  @override
  ConsumerState<TopStatusBar> createState() => _TopStatusBarState();
}

class _TopStatusBarState extends ConsumerState<TopStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(trainStateProvider);
    final conn = ref.watch(bleConnectionStateProvider);
    final connState = conn.valueOrNull ?? BleConnectionState.disconnected;
    final isConn = connState == BleConnectionState.connected;
    final trains = ref.watch(trainManagerProvider);
    final selectedId = ref.watch(selectedTrainIdProvider);

    String trainLabel = '未连接';
    if (selectedId != null) {
      for (final t in trains) {
        if (t.id == selectedId) {
          trainLabel = t.name;
          break;
        }
      }
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        gradient: TrainTheme.topBarGradient,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TrainTheme.metalDark, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.white.withOpacity(0.03),
              offset: const Offset(0, 1),
              blurRadius: 1),
          const BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(0, 5),
              blurRadius: 12),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showTrainManager(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConn
                          ? TrainTheme.glowGreen
                          : TrainTheme.glowRed,
                      boxShadow: [
                        BoxShadow(
                          color: (isConn
                                  ? TrainTheme.glowGreen
                                  : TrainTheme.glowRed)
                              .withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('🚂', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      trainLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TrainTheme.orbitronStyle(
                        fontSize: 11,
                        color: const Color(0xFF58A6FF),
                        shadows: [
                          Shadow(
                              color: const Color(0xFF58A6FF)
                                  .withOpacity(0.4),
                              blurRadius: 5)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more,
                      size: 14,
                      color: const Color(0xFF58A6FF).withOpacity(0.5)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
              width: 1, height: 20, color: const Color(0xFF333333)),
          const SizedBox(width: 8),
          _chip(
              '电压',
              _lcdVal(ts.batteryVoltage.toStringAsFixed(2), 'V',
                  TrainTheme.glowCyan)),
          const SizedBox(width: 8),
          _chip('电量', _battDisplay(ts)),
          const SizedBox(width: 8),
          _chip('端位', _cabBadge(ts.cab)),
          const SizedBox(width: 8),
          _chip('编组', _coupleBadge(ts.coupleStatus)),
          const Spacer(),
          if (ts.firmwareVersion.isNotEmpty)
            Text('FW ${ts.firmwareVersion}',
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 10, color: TrainTheme.textDim)),
        ],
      ),
    );
  }

  void _showTrainManager(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TrainManagerSheet(),
    );
  }

  Widget _chip(String label, Widget child) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TrainTheme.rajdhaniStyle(
                fontSize: 11, color: TrainTheme.textLight)),
        const SizedBox(width: 4),
        child,
      ],
    );
  }

  Widget _lcdVal(String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: TrainTheme.lcdDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TrainTheme.orbitronStyle(
                fontSize: 12,
                color: color,
                shadows: [
                  Shadow(
                      color: color.withOpacity(0.5), blurRadius: 5)
                ],
              )),
          const SizedBox(width: 2),
          Text(unit,
              style: TrainTheme.rajdhaniStyle(
                  fontSize: 9,
                  color: color.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _battDisplay(TrainState ts) {
    final color = TrainTheme.batteryColor(ts.battery);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: TrainTheme.lcdDecoration,
      child: AnimatedBuilder(
        animation: _blink,
        builder: (_, __) {
          final visible = !ts.batteryLow || _blink.value > 0.5;
          return Opacity(
            opacity: visible ? 1.0 : 0.3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 18,
                    height: 9,
                    child:
                        CustomPaint(painter: _BattPainter(ts.battery, color))),
                const SizedBox(width: 3),
                Text('${ts.battery}',
                    style: TrainTheme.orbitronStyle(
                      fontSize: 12,
                      color: TrainTheme.glowGreen,
                      shadows: [
                        Shadow(
                            color: TrainTheme.glowGreen.withOpacity(0.5),
                            blurRadius: 5)
                      ],
                    )),
                const SizedBox(width: 1),
                Text('%',
                    style: TrainTheme.rajdhaniStyle(
                        fontSize: 9,
                        color: TrainTheme.glowGreen.withOpacity(0.7))),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cabBadge(CabEnd cab) {
    final isA = cab == CabEnd.a;
    final color = isA ? TrainTheme.glowGreen : TrainTheme.glowOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border(bottom: BorderSide(color: color, width: 2)),
      ),
      child: Text(isA ? 'A端' : 'B端',
          style: TrainTheme.rajdhaniStyle(
            fontSize: 12,
            color: Colors.white,
            shadows: [
              Shadow(color: color.withOpacity(0.8), blurRadius: 5)
            ],
          )),
    );
  }

  Widget _coupleBadge(CoupleStatus status) {
    String text;
    Color color;
    bool blink = false;

    switch (status) {
      case CoupleStatus.off:
        text = '独立';
        color = const Color(0xFFAAAAAA);
      case CoupleStatus.inviting:
        text = '邀请中';
        color = TrainTheme.glowOrange;
        blink = true;
      case CoupleStatus.invited:
        text = '收到邀请';
        color = TrainTheme.glowCyan;
        blink = true;
      case CoupleStatus.master:
        text = '本务';
        color = TrainTheme.glowRed;
      case CoupleStatus.slave:
        text = '补机';
        color = TrainTheme.glowRed;
    }

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status == CoupleStatus.off
            ? TrainTheme.metalDark
            : color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border(
            bottom: BorderSide(
          color: status == CoupleStatus.off
              ? TrainTheme.metalLight
              : color,
          width: 2,
        )),
      ),
      child: Text(
        text,
        style: TrainTheme.rajdhaniStyle(
          fontSize: 12,
          color: status == CoupleStatus.off
              ? const Color(0xFFAAAAAA)
              : Colors.white,
          shadows: status == CoupleStatus.off
              ? null
              : [Shadow(color: color.withOpacity(0.8), blurRadius: 5)],
        ),
      ),
    );

    if (blink) {
      badge = AnimatedBuilder(
        animation: _blink,
        builder: (_, child) =>
            Opacity(opacity: 0.5 + 0.5 * _blink.value, child: child),
        child: badge,
      );
    }
    return badge;
  }
}

class _BattPainter extends CustomPainter {
  final int pct;
  final Color c;
  _BattPainter(this.pct, this.c);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, s.width - 3, s.height),
          const Radius.circular(1.5)),
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(
              s.width - 3, s.height * 0.25, 2.5, s.height * 0.5),
          const Radius.circular(0.8)),
      Paint()..color = c,
    );
    final fw = (s.width - 5) * (pct / 100.0);
    canvas.drawRect(
        Rect.fromLTWH(1, 1, fw.clamp(0, s.width - 5), s.height - 2),
        Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _BattPainter old) =>
      old.pct != pct || old.c != c;
}