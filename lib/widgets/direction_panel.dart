import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import 'direction_dial_painter.dart';
import 'emergency_stop.dart';

class DirectionPanel extends ConsumerWidget {
  const DirectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts = ref.watch(trainStateProvider);
    final n = ref.read(trainStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          _DirBoard(
            direction: ts.direction,
            isRunning: ts.isRunning,
            isSlave: ts.isSlave,
            onFwd: () => n.setForward(),
            onStop: () => n.setStop(),
            onRev: () => n.setReverse(),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _DirDial(
              direction: ts.direction,
              isRunning: ts.isRunning,
              isSlave: ts.isSlave,
              onChange: (d) {
                switch (d) {
                  case TrainDirection.forward: n.setForward();
                  case TrainDirection.stop: n.setStop();
                  case TrainDirection.reverse: n.setReverse();
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: EmergencyStop(),
          ),
        ],
      ),
    );
  }
}

class _DirBoard extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final VoidCallback onFwd;
  final VoidCallback onStop;
  final VoidCallback onRev;

  const _DirBoard({
    required this.direction,
    required this.isRunning,
    required this.isSlave,
    required this.onFwd,
    required this.onStop,
    required this.onRev,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0B0D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TrainTheme.metalDark, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0xE6000000), offset: Offset(0, 3), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _DirBtn(
            badge: 'F', label: '前进', eng: 'FWD',
            isActive: direction == TrainDirection.forward,
            color: TrainTheme.glowBlue,
            canTap: !isSlave && (!isRunning || direction != TrainDirection.reverse),
            onTap: onFwd,
          )),
          const SizedBox(width: 5),
          Expanded(child: _DirBtn(
            badge: 'S', label: '停车', eng: 'STOP',
            isActive: direction == TrainDirection.stop,
            color: TrainTheme.glowGreen,
            canTap: !isSlave,
            onTap: onStop,
          )),
          const SizedBox(width: 5),
          Expanded(child: _DirBtn(
            badge: 'R', label: '后退', eng: 'REV',
            isActive: direction == TrainDirection.reverse,
            color: TrainTheme.glowRed,
            canTap: !isSlave && (!isRunning || direction != TrainDirection.forward),
            onTap: onRev,
          )),
        ],
      ),
    );
  }
}

class _DirBtn extends StatelessWidget {
  final String badge;
  final String label;
  final String eng;
  final bool isActive;
  final Color color;
  final bool canTap;
  final VoidCallback onTap;

  const _DirBtn({
    required this.badge, required this.label, required this.eng,
    required this.isActive, required this.color, required this.canTap, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !canTap && !isActive;
    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Opacity(
        opacity: dimmed ? 0.35 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.12) : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isActive ? color.withOpacity(0.3) : Colors.transparent),
          ),
          child: Column(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isActive ? color : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: isActive ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6)] : null,
                ),
                child: Center(
                  child: Text(badge, style: TrainTheme.orbitronStyle(
                    fontSize: 12, fontWeight: FontWeight.w900,
                    color: isActive ? Colors.black : const Color(0xFF555555),
                  )),
                ),
              ),
              const SizedBox(height: 3),
              Text(label, style: TrainTheme.rajdhaniStyle(
                fontSize: 11, color: isActive ? Colors.white : TrainTheme.textDim,
              )),
              Text(eng, style: TrainTheme.rajdhaniStyle(
                fontSize: 8, color: (isActive ? Colors.white : TrainTheme.textDim).withOpacity(0.6),
              )),
              const SizedBox(height: 3),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color : const Color(0xFF222222),
                  boxShadow: isActive ? [BoxShadow(color: color, blurRadius: 8)] : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirDial extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final ValueChanged<TrainDirection> onChange;

  const _DirDial({
    required this.direction, required this.isRunning, required this.isSlave, required this.onChange,
  });

  void _onTap() {
    if (isSlave) return;
    switch (direction) {
      case TrainDirection.stop: onChange(TrainDirection.forward);
      case TrainDirection.forward: onChange(isRunning ? TrainDirection.stop : TrainDirection.reverse);
      case TrainDirection.reverse: onChange(isRunning ? TrainDirection.stop : TrainDirection.forward);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      // 【彻底修复越界 17 px 的核心代码】
      // 预留出底部 'DIRECTION' 文字及边距的高度 (约 24.0)
      // 这样表盘在拉伸时，就不会把底部的文字挤出 Expanded 导致越界
      final availableHeight = box.maxHeight - 24.0;
      final sz = (box.maxWidth < availableHeight ? box.maxWidth : availableHeight)
          .clamp(10.0, 180.0);

      void handlePan(Offset localPosition) {
        if (isSlave) return;
        final center = Offset(sz / 2, sz / 2);
        final delta = localPosition - center;
        
        double angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
        if (angle > math.pi) angle -= 2 * math.pi;

        if (angle < -math.pi / 8) {
          if (direction != TrainDirection.forward) onChange(TrainDirection.forward);
        } else if (angle > math.pi / 8) {
          if (direction != TrainDirection.reverse) {
            if (isRunning && direction == TrainDirection.forward) {
               onChange(TrainDirection.stop);
            } else {
               onChange(TrainDirection.reverse);
            }
          }
        } else {
          if (direction != TrainDirection.stop) onChange(TrainDirection.stop);
        }
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _onTap,
            onPanStart: (d) => handlePan(d.localPosition),
            onPanUpdate: (d) => handlePan(d.localPosition),
            child: SizedBox(
              width: sz,
              height: sz,
              child: CustomPaint(painter: DirectionDialPainter(direction: direction)),
            ),
          ),
          const SizedBox(height: 6),
          Text('DIRECTION', style: TrainTheme.orbitronStyle(
            fontSize: 9, color: TrainTheme.textDim, letterSpacing: 3,
          )),
        ],
      );
    });
  }
}