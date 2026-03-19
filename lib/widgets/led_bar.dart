import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/train_theme.dart';
import '../providers/train_provider.dart';
import '../utils/constants.dart';

class LedBar extends ConsumerWidget {
  const LedBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lv = ref.watch(trainStateProvider).level;

    return Container(
      decoration: BoxDecoration(
        color: TrainTheme.metalDark,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 6)],
      ),
      padding: const EdgeInsets.all(3),
      child: Column(
        children: List.generate(BleConstants.maxNotch + 1, (i) {
          final notch = BleConstants.maxNotch - i;
          final active = notch <= lv && notch > 0;
          final color = TrainTheme.ledColor(notch - 1);
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: active ? color : TrainTheme.metalDark,
                borderRadius: BorderRadius.circular(3),
                boxShadow: active
                    ? [
                        BoxShadow(color: color, blurRadius: 6),
                        BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            offset: const Offset(0, 1),
                            blurRadius: 2),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }
}