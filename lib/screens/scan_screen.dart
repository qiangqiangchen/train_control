/// BLE 扫描连接页面
///
/// 工业仪表盘风格的设备扫描界面。
/// 显示附近的 BLE_Train 设备列表，支持点击连接。

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/train_theme.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';
import 'dashboard_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isConnecting = false;
  String _connectingDeviceName = '';
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _requestPermissions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// 请求蓝牙和定位权限
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final allGranted = statuses.values.every(
        (s) => s.isGranted || s.isLimited,
      );

      setState(() => _permissionsGranted = allGranted);

      if (allGranted) {
        _startScan();
      }
    } else {
      // iOS 权限由系统自动提示
      setState(() => _permissionsGranted = true);
      _startScan();
    }
  }

  /// 开始扫描
  Future<void> _startScan() async {
    final bleService = ref.read(bleServiceProvider);
    try {
      await bleService.startScan();
    } catch (e) {
      debugPrint('扫描错误: $e');
    }
  }

  /// 停止扫描
  Future<void> _stopScan() async {
    final bleService = ref.read(bleServiceProvider);
    await bleService.stopScan();
  }

  /// 连接设备
  Future<void> _connectDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _connectingDeviceName = device.platformName;
    });

    await _stopScan();

    final bleService = ref.read(bleServiceProvider);
    final success = await bleService.connectToDevice(device);

    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      setState(() => _isConnecting = false);
      if (mounted) {
        _showErrorSnackBar('连接失败，请重试');
        _startScan();
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// RSSI 信号强度图标
  Widget _buildRssiIcon(int rssi) {
    final bars = rssi > -60
        ? 4
        : rssi > -70
            ? 3
            : rssi > -80
                ? 2
                : 1;
    final color = rssi > -60
        ? TrainTheme.glowGreen
        : rssi > -80
            ? TrainTheme.glowOrange
            : TrainTheme.glowRed;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final height = 6.0 + (i * 4);
        final isActive = i < bars;
        return Container(
          width: 4,
          height: height,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive ? color : const Color(0xFF333333),
            borderRadius: BorderRadius.circular(1),
            boxShadow: isActive
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                : null,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanResults = ref.watch(scanResultsProvider);
    final isScanning = ref.watch(isScanningProvider);

    return Scaffold(
      backgroundColor: TrainTheme.bodyBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            colors: [Color(0xFF1A1A24), Color(0xFF000000)],
          ),
        ),
        child: Center(
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              gradient: TrainTheme.dashboardGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TrainTheme.metalDark, width: 2),
              boxShadow: TrainTheme.dashboardOuterShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏
                _buildTitleBar(isScanning),
                // 内容区域
                Expanded(
                  child: _isConnecting
                      ? _buildConnectingView()
                      : !_permissionsGranted
                          ? _buildPermissionView()
                          : _buildDeviceList(scanResults),
                ),
                // 底部按钮
                _buildBottomBar(isScanning),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(AsyncValue<bool> isScanning) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: TrainTheme.topBarGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(
          bottom: BorderSide(color: TrainTheme.metalDark, width: 2),
        ),
      ),
      child: Row(
        children: [
          Text(
            '🚂',
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Text(
            'BLE TRAIN CONTROLLER',
            style: GoogleFonts.orbitron(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: TrainTheme.glowCyan,
              shadows: [
                Shadow(
                  color: TrainTheme.glowCyan.withOpacity(0.5),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          const Spacer(),
          // 扫描状态指示
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scanning = isScanning.valueOrNull ?? false;
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scanning
                          ? TrainTheme.glowCyan.withOpacity(
                              0.5 + 0.5 * _pulseController.value)
                          : TrainTheme.textDim,
                      boxShadow: scanning
                          ? [
                              BoxShadow(
                                color: TrainTheme.glowCyan
                                    .withOpacity(0.5 * _pulseController.value),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    scanning ? 'SCANNING...' : 'IDLE',
                    style: GoogleFonts.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          scanning ? TrainTheme.glowCyan : TrainTheme.textDim,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(AsyncValue<List<ScanResult>> scanResults) {
    return scanResults.when(
      data: (results) {
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bluetooth_searching,
                    size: 48, color: TrainTheme.textDim),
                const SizedBox(height: 16),
                Text(
                  '正在搜索 BLE_Train 设备...',
                  style: GoogleFonts.rajdhani(
                    fontSize: 16,
                    color: TrainTheme.textDim,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            return _buildDeviceItem(result);
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: TrainTheme.glowCyan),
      ),
      error: (e, _) => Center(
        child: Text('扫描错误: $e',
            style: const TextStyle(color: TrainTheme.glowRed)),
      ),
    );
  }

  Widget _buildDeviceItem(ScanResult result) {
    final device = result.device;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : 'Unknown Device';
    final rssi = result.rssi;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF222222)),
        boxShadow: [
          const BoxShadow(
            color: Color(0xE6000000),
            offset: Offset(0, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _connectDevice(device),
          splashColor: TrainTheme.glowCyan.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 蓝牙图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TrainTheme.glowCyan.withOpacity(0.1),
                    border: Border.all(
                        color: TrainTheme.glowCyan.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.train,
                    color: TrainTheme.glowCyan,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                // 设备名称
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.orbitron(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: TrainTheme.glowCyan,
                          shadows: [
                            Shadow(
                              color: TrainTheme.glowCyan.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.remoteId.str,
                        style: GoogleFonts.rajdhani(
                          fontSize: 12,
                          color: TrainTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                // RSSI
                Column(
                  children: [
                    _buildRssiIcon(rssi),
                    const SizedBox(height: 4),
                    Text(
                      '${rssi}dBm',
                      style: GoogleFonts.rajdhani(
                        fontSize: 11,
                        color: TrainTheme.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // 连接箭头
                const Icon(Icons.chevron_right,
                    color: TrainTheme.textDim, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: TrainTheme.glowCyan,
              backgroundColor: TrainTheme.glowCyan.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '正在连接...',
            style: GoogleFonts.rajdhani(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: TrainTheme.glowCyan,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _connectingDeviceName,
            style: GoogleFonts.orbitron(
              fontSize: 14,
              color: TrainTheme.glowCyan.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bluetooth_disabled,
              size: 48, color: TrainTheme.glowRed),
          const SizedBox(height: 16),
          Text(
            '需要蓝牙和定位权限',
            style: GoogleFonts.rajdhani(
              fontSize: 16,
              color: TrainTheme.glowRed,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _requestPermissions,
            style: ElevatedButton.styleFrom(
              backgroundColor: TrainTheme.glowCyan.withOpacity(0.2),
              foregroundColor: TrainTheme.glowCyan,
            ),
            child: const Text('授权'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AsyncValue<bool> isScanning) {
    final scanning = isScanning.valueOrNull ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: TrainTheme.metalDark, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildScanButton(scanning),
        ],
      ),
    );
  }

  Widget _buildScanButton(bool scanning) {
    return GestureDetector(
      onTap: () {
        if (scanning) {
          _stopScan();
        } else {
          _startScan();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          gradient: TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TrainTheme.metalDark, width: 2),
          boxShadow: [
            const BoxShadow(
              color: Color(0x99000000),
              offset: Offset(0, 6),
              blurRadius: 10,
            ),
            const BoxShadow(
              color: Color(0x1AFFFFFF),
              offset: Offset(0, 2),
              blurRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              scanning ? Icons.stop : Icons.bluetooth_searching,
              color: scanning ? TrainTheme.glowRed : TrainTheme.glowCyan,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              scanning ? 'STOP' : 'SCAN',
              style: GoogleFonts.orbitron(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scanning ? TrainTheme.glowRed : TrainTheme.glowCyan,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}