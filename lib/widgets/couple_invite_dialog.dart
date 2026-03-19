import 'package:flutter/material.dart';
import '../theme/train_theme.dart';

class CoupleInviteDialog extends StatelessWidget {
  final String inviterMac;
  final VoidCallback onAcceptA;
  final VoidCallback onAcceptB;
  final VoidCallback onReject;

  const CoupleInviteDialog({
    super.key,
    required this.inviterMac,
    required this.onAcceptA,
    required this.onAcceptB,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: TrainTheme.muGlow.withOpacity(0.4), width: 2),
          boxShadow: [
            BoxShadow(color: TrainTheme.muGlow.withOpacity(0.1), blurRadius: 20),
            const BoxShadow(color: Color(0xCC000000), offset: Offset(0, 12), blurRadius: 25),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '📡 收到重联邀请',
              style: TrainTheme.orbitronStyle(
                fontSize: 15,
                color: TrainTheme.muGlow,
                shadows: [Shadow(color: TrainTheme.muGlow.withOpacity(0.4), blurRadius: 7)],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: TrainTheme.metalDark),
              ),
              child: Text(
                '来自: $inviterMac',
                style: TrainTheme.orbitronStyle(fontSize: 10, color: TrainTheme.glowCyan),
              ),
            ),
            const SizedBox(height: 6),
            Text('选择本车的连接端位：', style: TrainTheme.rajdhaniStyle(fontSize: 12, color: TrainTheme.textDim)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _btn('A端连接', TrainTheme.glowGreen, onAcceptA),
                _btn('B端连接', TrainTheme.glowOrange, onAcceptB),
                _btn('拒绝', TrainTheme.glowRed, onReject),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TrainTheme.rajdhaniStyle(
          fontSize: 12, fontWeight: FontWeight.w900, color: color,
        )),
      ),
    );
  }
}