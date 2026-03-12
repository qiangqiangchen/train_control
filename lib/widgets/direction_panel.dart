/// 左面板：方向控制
///
/// 包含方向状态显示板和旋转拨盘。
/// 三种状态：前进(F)/停车(S)/后退(R)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import 'direction_dial_painter.dart';

class DirectionPanel extends ConsumerWidget {
  const DirectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainState = ref.watch(trainStateProvider);
    final notifier = ref.read(trainStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 方向状态显示板
          _DirectionDisplayBoard(
            direction: trainState.direction,
            isRunning: trainState.isRunning,
            isSlave: trainState.isSlave,
            onTapForward: () => notifier.setForward(),
            onTapStop: () => notifier.setStop(),
            onTapReverse: () => notifier.setReverse(),
          ),

          // 方向拨盘
          _DirectionDial(
            direction: trainState.direction,
            isRunning: trainState.isRunning,
            isSlave: trainState.isSlave,
            onChangeDirection: (dir) {
              switch (dir) {
                case TrainDirection.forward:
                  notifier.setForward();
                case TrainDirection.stop:
                  notifier.setStop();
                case TrainDirection.reverse:
                  notifier.setReverse();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 方向状态显示板
class _DirectionDisplayBoard extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final VoidCallback onTapForward;
  final VoidCallback onTapStop;
  final VoidCallback onTapReverse;

  const _DirectionDisplayBoard({
    required this.direction,
    required this.isRunning,
    required this.isSlave,
    required this.onTapForward,
    required this.onTapStop,
    required this.onTapReverse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0B0D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TrainTheme.metalDark, width: 2),
        boxShadow: [
          const BoxShadow(
            color: Color(0xE6000000),
            offset: Offset(0, 5),
            blurRadius: 15,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            offset: const Offset(0, 2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildDirectionRow(
            badge: 'F',
            label: '前进',
            engLabel: 'FORWARD',
            isActive: direction == TrainDirection.forward,
            activeColor: TrainTheme.glowBlue,
            canTap: !isSlave &&
                (!isRunning || direction == TrainDirection.forward || direction == TrainDirection.stop),
            onTap: onTapForward,
          ),
          const SizedBox(height: 12),
          _buildDirectionRow(
            badge: 'S',
            label: '停车',
            engLabel: 'STOP',
            isActive: direction == TrainDirection.stop,
            activeColor: TrainTheme.glowGreen,
            canTap: !isSlave,
            onTap: onTapStop,
          ),
          const SizedBox(height: 12),
          _buildDirectionRow(
            badge: 'R',
            label: '后退',
            engLabel: 'REVERSE',
            isActive: direction == TrainDirection.reverse,
            activeColor: TrainTheme.glowRed,
            canTap: !isSlave &&
                (!isRunning || direction == TrainDirection.reverse || direction == TrainDirection.stop),
            onTap: onTapReverse,
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionRow({
    required String badge,
    required String label,
    required String engLabel,
    required bool isActive,
    required Color activeColor,
    required bool canTap,
    required VoidCallback onTap,
  }) {
    final bgColor = isActive
        ? activeColor.withOpacity(0.1)
        : const Color(0xFF111111);
    final borderColor =
        isActive ? activeColor.withOpacity(0.3) : Colors.transparent;
    final textColor = isActive ? Colors.white : TrainTheme.textDim;
    final dimmed = !canTap && !isActive;

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Opacity(
        opacity: dimmed ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              // Badge
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isActive ? activeColor : const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive ? Colors.transparent : Colors.black,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withOpacity(0.5),
                            blurRadius: 10,
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                          const BoxShadow(
                            color: Color(0x80000000),
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    badge,
                    style: GoogleFonts.orbitron(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isActive ? Colors.black : const Color(0xFF555555),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              // 文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.rajdhani(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    Text(
                      engLabel,
                      style: GoogleFonts.rajdhani(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // 指示灯
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? activeColor : const Color(0xFF222222),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor,
                            blurRadius: 12,
                          ),
                        ]
                      : [
                          const BoxShadow(
                            color: Color(0xFF000000),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 方向旋转拨盘
class _DirectionDial extends StatelessWidget {
  final TrainDirection direction;
  final bool isRunning;
  final bool isSlave;
  final ValueChanged<TrainDirection> onChangeDirection;

  const _DirectionDial({
    required this.direction,
    required this.isRunning,
    required this.isSlave,
    required this.onChangeDirection,
  });

  /// 获取可切换的下一个方向
  TrainDirection? _getNextDirection() {
    if (isSlave) return null;

    // 循环切换逻辑，考虑安全限制
    switch (direction) {
      case TrainDirection.stop:
        return TrainDirection.forward;
      case TrainDirection.forward:
        // 运行中只能切到 S
        return TrainDirection.stop;
      case TrainDirection.reverse:
        return TrainDirection.stop;
    }
  }

  void _onTap() {
    if (isSlave) return;

    switch (direction) {
      case TrainDirection.stop:
        onChangeDirection(TrainDirection.forward);
      case TrainDirection.forward:
        if (isRunning) {
          // 运行中从 F 只能切到 S
          onChangeDirection(TrainDirection.stop);
        } else {
          // 停车状态可以切到 R
          onChangeDirection(TrainDirection.reverse);
        }
      case TrainDirection.reverse:
        if (isRunning) {
          onChangeDirection(TrainDirection.stop);
        } else {
          onChangeDirection(TrainDirection.forward);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: _onTap,
          child: SizedBox(
            width: 220,
            height: 220,
            child: CustomPaint(
              painter: DirectionDialPainter(
                direction: direction,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'DIRECTION CONTROL',
          style: GoogleFonts.orbitron(
            fontSize: 13,
            color: TrainTheme.textDim,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}