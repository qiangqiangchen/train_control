/// 重联邀请弹窗
///
/// 当收到 CP:INVITED 状态时弹出。
/// 工业风格对话框：深色 + 绿色发光边框。

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: TrainTheme.muGlow.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: TrainTheme.muGlow.withOpacity(0.15),
              blurRadius: 30,
            ),
            const BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(0, 20),
              blurRadius: 40,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Text(
              '📡 收到重联邀请',
              style: GoogleFonts.orbitron(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: TrainTheme.muGlow,
                shadows: [
                  Shadow(
                    color: TrainTheme.muGlow.withOpacity(0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // MAC 地址
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: TrainTheme.metalDark, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '来自: ',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TrainTheme.textDim,
                    ),
                  ),
                  Text(
                    inviterMac,
                    style: GoogleFonts.orbitron(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TrainTheme.glowCyan,
                      shadows: [
                        Shadow(
                          color: TrainTheme.glowCyan.withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 说明
            Text(
              '选择本车的连接端位：',
              style: GoogleFonts.rajdhani(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: TrainTheme.textDim,
              ),
            ),
            const SizedBox(height: 20),

            // 按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  label: 'A端连接',
                  color: TrainTheme.glowGreen,
                  onTap: onAcceptA,
                ),
                _buildActionButton(
                  label: 'B端连接',
                  color: TrainTheme.glowOrange,
                  onTap: onAcceptB,
                ),
                _buildActionButton(
                  label: '拒绝',
                  color: TrainTheme.glowRed,
                  onTap: onReject,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.rajdhani(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color,
            shadows: [
              Shadow(color: color.withOpacity(0.5), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }
}