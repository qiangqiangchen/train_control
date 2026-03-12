/// 油门拉杆组件
///
/// 垂直拖动操作，9个档位 (0~8)。
/// 金属拉杆手柄 + 凹槽 + 触觉反馈。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../models/train_state.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';

class ThrottleLever extends ConsumerStatefulWidget {
  const ThrottleLever({super.key});

  @override
  ConsumerState<ThrottleLever> createState() => _ThrottleLeverState();
}

class _ThrottleLeverState extends ConsumerState<ThrottleLever> {
  int _currentNotch = 0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final trainState = ref.watch(trainStateProvider);
    final isSlave = trainState.isSlave;
    final isStopDirection = trainState.direction == TrainDirection.stop;

    // 同步 BLE 回报的档位
    if (!_isDragging) {
      _currentNotch = trainState.level;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final slotHeight = totalHeight - 40; // padding
        final stepHeight = slotHeight / BleConstants.maxNotch;
        final handleY =
            (totalHeight - 40) - (_currentNotch * stepHeight) - 0;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E2126),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: TrainTheme.metalDark, width: 2),
            boxShadow: [
              const BoxShadow(
                color: Color(0xFF000000),
                offset: Offset(0, 0),
                blurRadius: 20,
              ),
              const BoxShadow(
                color: Color(0x80000000),
                offset: Offset(0, 10),
                blurRadius: 20,
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 轨道凹槽
              Positioned(
                left: 0,
                right: 0,
                top: 20,
                bottom: 20,
                child: Center(
                  child: Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        const BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(0, 5),
                          blurRadius: 15,
                        ),
                        BoxShadow(
                          color: const Color(0xFF333333),
                          blurRadius: 0,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 左侧凹痕标记
              Positioned(
                left: 5,
                top: 20,
                bottom: 20,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    BleConstants.maxNotch + 1,
                    (i) => Container(
                      width: 15,
                      height: 8,
                      decoration: BoxDecoration(
                        color: TrainTheme.metalDark,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                          const BoxShadow(
                            color: Color(0xFF000000),
                            offset: Offset(0, 2),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ).reversed.toList(),
                ),
              ),

              // 手柄拖动区域
              Positioned.fill(
                child: GestureDetector(
                  onVerticalDragStart: (isSlave || isStopDirection)
                      ? null
                      : (details) {
                          _isDragging = true;
                        },
                  onVerticalDragUpdate: (isSlave || isStopDirection)
                      ? null
                      : (details) {
                          _updateNotchFromDrag(details, totalHeight);
                        },
                  onVerticalDragEnd: (isSlave || isStopDirection)
                      ? null
                      : (details) {
                          _isDragging = false;
                          ref
                              .read(trainStateProvider.notifier)
                              .setNotchFinal(_currentNotch);
                        },
                  onTapUp: (isSlave || isStopDirection)
                      ? null
                      : (details) {
                          _updateNotchFromTap(
                              details.localPosition.dy, totalHeight);
                        },
                  behavior: HitTestBehavior.opaque,
                ),
              ),

              // 手柄
              Positioned(
                left: -30,
                right: -30,
                top: 20 + handleY,
                child: IgnorePointer(
                  child: _LeverHandle(
                    isDragging: _isDragging,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateNotchFromDrag(DragUpdateDetails details, double totalHeight) {
    final slotHeight = totalHeight - 40;
    final relativeY = details.localPosition.dy - 20;
    final fraction = 1.0 - (relativeY / slotHeight);
    final newNotch =
        (fraction * BleConstants.maxNotch).round().clamp(0, BleConstants.maxNotch);

    if (newNotch != _currentNotch) {
      setState(() => _currentNotch = newNotch);
      ref.read(trainStateProvider.notifier).setNotch(newNotch);
      HapticFeedback.selectionClick();
    }
  }

  void _updateNotchFromTap(double tapY, double totalHeight) {
    final slotHeight = totalHeight - 40;
    final relativeY = tapY - 20;
    final fraction = 1.0 - (relativeY / slotHeight);
    final newNotch =
        (fraction * BleConstants.maxNotch).round().clamp(0, BleConstants.maxNotch);

    setState(() => _currentNotch = newNotch);
    ref.read(trainStateProvider.notifier).setNotchFinal(newNotch);
    HapticFeedback.mediumImpact();
  }
}

/// 拉杆手柄外观
class _LeverHandle extends StatelessWidget {
  final bool isDragging;

  const _LeverHandle({required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 手柄杆
        Container(
          width: 20,
          height: 25,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF444444), Color(0xFF777777), Color(0xFF333333)],
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0xFF000000),
                offset: Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        // 手柄主体
        Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF6C7A89),
                Color(0xFF34495E),
                Color(0xFF111111),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.9),
                offset: const Offset(0, 15),
                blurRadius: 25,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.4),
                offset: const Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 5),
              // 左侧把手帽
              Container(
                width: 15,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF888888),
                      Color(0xFFCCCCCC),
                      Color(0xFF555555),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0xFF000000),
                      offset: Offset(0, 0),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 右侧把手帽
              Container(
                width: 15,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF888888),
                      Color(0xFFCCCCCC),
                      Color(0xFF555555),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    const BoxShadow(
                      color: Color(0xFF000000),
                      offset: Offset(0, 0),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
            ],
          ),
        ),
      ],
    );
  }
}