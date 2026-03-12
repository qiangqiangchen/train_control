/// LED 档位指示条
///
/// 9个LED灯段，从底部到顶部逐个点亮。
/// 颜色分段：0-2绿色、3-5黄色、6-8红色。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/train_theme.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';

class LedBar extends ConsumerWidget {
  const LedBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainState = ref.watch(trainStateProvider);
    final activeLevel = trainState.level;

    return Container(
      decoration: BoxDecoration(
        color: TrainTheme.metalDark,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF000000),
            offset: Offset(0, 0),
            blurRadius: 10,
          ),
          BoxShadow(
            color: const Color(0xFF2A2D34),
            blurRadius: 0,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: Column(
        children: List.generate(BleConstants.maxNotch + 1, (index) {
          // 反转索引：顶部=8, 底部=0
          final notch = BleConstants.maxNotch - index;
          final isActive = notch <= activeLevel && notch > 0;
          final color = TrainTheme.ledColor(notch - 1);

          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              decoration: BoxDecoration(
                color: isActive ? color : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(5),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: color,
                          blurRadius: 10,
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.5),
                          offset: const Offset(0, 2),
                          blurRadius: 5,
                        ),
                      ]
                    : [
                        const BoxShadow(
                          color: Color(0xFF000000),
                          offset: Offset(0, 2),
                          blurRadius: 5,
                        ),
                      ],
              ),
            ),
          );
        }),
      ),
    );
  }
}