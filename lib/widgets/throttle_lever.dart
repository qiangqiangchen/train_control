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
  int _notch = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final ts = ref.watch(trainStateProvider);
    final slave = ts.isSlave;
    final stopped = ts.direction == TrainDirection.stop && !ts.isRunning;
    if (!_dragging) _notch = ts.level;

    return LayoutBuilder(builder: (_, box) {
      final h = box.maxHeight;
      final slotH = h - 30;
      final step = slotH / BleConstants.maxNotch;
      final handleY = slotH - (_notch * step);

      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E2126),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TrainTheme.metalDark, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 12)],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0, right: 0, top: 15, bottom: 15,
              child: Center(
                child: Container(
                  width: 30,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      const BoxShadow(color: Colors.black, blurRadius: 8),
                      BoxShadow(
                          color: const Color(0xFF333333), spreadRadius: 1.5),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 3, top: 15, bottom: 15,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    9,
                    (_) => Container(
                          width: 10,
                          height: 5,
                          decoration: BoxDecoration(
                            color: TrainTheme.metalDark,
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(2)),
                          ),
                        )).reversed.toList(),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragStart: (slave || stopped)
                    ? null
                    : (_) => _dragging = true,
                onVerticalDragUpdate: (slave || stopped)
                    ? null
                    : (d) => _onDrag(d, h),
                onVerticalDragEnd: (slave || stopped)
                    ? null
                    : (_) {
                        _dragging = false;
                        ref
                            .read(trainStateProvider.notifier)
                            .setNotchFinal(_notch);
                      },
                onTapUp: (slave || stopped)
                    ? null
                    : (d) => _onTap(d.localPosition.dy, h),
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              left: -18,
              right: -18,
              top: 15 + handleY - 16,
              child: IgnorePointer(child: _buildHandle()),
            ),
          ],
        ),
      );
    });
  }

  void _onDrag(DragUpdateDetails d, double h) {
    final slotH = h - 30;
    final ry = d.localPosition.dy - 15;
    final n = ((1 - ry / slotH) * BleConstants.maxNotch)
        .round()
        .clamp(0, BleConstants.maxNotch);
    if (n != _notch) {
      setState(() => _notch = n);
      ref.read(trainStateProvider.notifier).setNotch(n);
      HapticFeedback.selectionClick();
    }
  }

  void _onTap(double y, double h) {
    final slotH = h - 30;
    final ry = y - 15;
    final n = ((1 - ry / slotH) * BleConstants.maxNotch)
        .round()
        .clamp(0, BleConstants.maxNotch);
    setState(() => _notch = n);
    ref.read(trainStateProvider.notifier).setNotchFinal(n);
    HapticFeedback.mediumImpact();
  }

  Widget _buildHandle() {
    return Column(
      children: [
        Container(
          width: 14,
          height: 16,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF444444),
                Color(0xFF777777),
                Color(0xFF333333)
              ],
            ),
          ),
        ),
        Container(
          height: 30,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF6C7A89),
                Color(0xFF34495E),
                Color(0xFF111111)
              ],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.9),
                  offset: const Offset(0, 8),
                  blurRadius: 14),
              BoxShadow(
                  color: Colors.white.withOpacity(0.25),
                  offset: const Offset(0, 2),
                  blurRadius: 4),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 3),
              Container(
                width: 10,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF888888),
                      Color(0xFFCCCCCC),
                      Color(0xFF555555)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const Spacer(),
              Container(
                width: 10,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF888888),
                      Color(0xFFCCCCCC),
                      Color(0xFF555555)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ],
    );
  }
}