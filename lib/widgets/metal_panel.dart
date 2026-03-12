/// 通用金属面板容器
///
/// 可复用的金属质感面板，支持自定义内容、圆角、边框等。

import 'package:flutter/material.dart';
import '../theme/train_theme.dart';

class MetalPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const MetalPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0B0D),
        borderRadius: BorderRadius.circular(borderRadius),
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
      child: child,
    );
  }
}