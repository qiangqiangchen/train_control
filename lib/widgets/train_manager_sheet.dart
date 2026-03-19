import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/train_theme.dart';
import '../models/saved_train.dart';
import '../providers/train_provider.dart';
import '../services/ble_service.dart';

class TrainManagerSheet extends ConsumerStatefulWidget {
  const TrainManagerSheet({super.key});

  @override
  ConsumerState<TrainManagerSheet> createState() => _TrainManagerSheetState();
}

class _TrainManagerSheetState extends ConsumerState<TrainManagerSheet> {
  bool _scanning = false;
  List<ScanResult> _results = [];
  bool _connecting = false;
  String _connectingId = '';
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanSub = null;
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _requestAndScan() async {
    try {
      if (Platform.isAndroid) {
        final results = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        debugPrint('Permission results: $results');
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
    await _startScan();
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _results = [];
    });
    try {
      await FlutterBluePlus.stopScan();
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen(
        (r) {
          if (mounted) setState(() => _results = r);
        },
        onError: (e) {
          debugPrint('Scan results stream error: $e');
        },
      );
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withNames: ['BLE_Train'],
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('扫描失败: $e',
                style: TrainTheme.rajdhaniStyle(fontSize: 12)),
            backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
          ),
        );
      }
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connectAndAdd(ScanResult result) async {
    if (_connecting) return;
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connectingId = result.device.remoteId.str;
    });

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    final ble = ref.read(bleServiceProvider);
    await ble.disconnect();

    final ok = await ble.connectToDevice(result.device);
    if (ok && mounted) {
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : 'BLE_Train';
      final train = SavedTrain(
        id: result.device.remoteId.str,
        name: name,
        deviceName: name,
        lastConnected: DateTime.now(),
      );
      ref.read(trainManagerProvider.notifier).addTrain(train);
      ref.read(trainManagerProvider.notifier).updateLastConnected(train.id);
      ref.read(selectedTrainIdProvider.notifier).state = train.id;
      if (mounted) Navigator.pop(context);
    } else {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败',
                style: TrainTheme.rajdhaniStyle(fontSize: 14)),
            backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
          ),
        );
      }
    }
  }

  Future<void> _reconnect(SavedTrain train) async {
    if (_connecting) return;
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connectingId = train.id;
    });

    final ble = ref.read(bleServiceProvider);
    await ble.disconnect();

    try {
      final device = BluetoothDevice.fromId(train.id);
      final ok = await ble.connectToDevice(device);
      if (ok && mounted) {
        ref.read(trainManagerProvider.notifier).updateLastConnected(train.id);
        ref.read(selectedTrainIdProvider.notifier).state = train.id;
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      debugPrint('Reconnect error: $e');
    }

    if (mounted) {
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败，请重新扫描',
              style: TrainTheme.rajdhaniStyle(fontSize: 14)),
          backgroundColor: TrainTheme.glowOrange.withOpacity(0.8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trains = ref.watch(trainManagerProvider);
    final selectedId = ref.watch(selectedTrainIdProvider);
    final conn = ref.watch(bleConnectionStateProvider);
    final isConn =
        (conn.valueOrNull ?? BleConnectionState.disconnected) ==
            BleConnectionState.connected;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        gradient: TrainTheme.dashboardGradient,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border.all(color: TrainTheme.metalDark, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0xCC000000),
            offset: Offset(0, -8),
            blurRadius: 25,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: TrainTheme.metalLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  '🚂 火车管理',
                  style: TrainTheme.orbitronStyle(
                    fontSize: 14,
                    color: TrainTheme.glowCyan,
                    shadows: [
                      Shadow(
                        color: TrainTheme.glowCyan.withOpacity(0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _actionBtn(
                  label: _scanning ? '扫描中...' : '扫描添加',
                  icon: _scanning
                      ? Icons.hourglass_top
                      : Icons.bluetooth_searching,
                  color: TrainTheme.glowCyan,
                  onTap: _scanning ? null : _requestAndScan,
                ),
                if (isConn) ...[
                  const SizedBox(width: 8),
                  _actionBtn(
                    label: '断开',
                    icon: Icons.link_off,
                    color: TrainTheme.glowRed,
                    onTap: () async {
                      await ref.read(bleServiceProvider).disconnect();
                      ref.read(selectedTrainIdProvider.notifier).state = null;
                    },
                  ),
                ],
              ],
            ),
          ),
          Container(
            height: 1,
            color: TrainTheme.metalDark,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Expanded(
            child: _connecting
                ? _buildConnecting()
                : _buildContent(trains, selectedId, isConn),
          ),
        ],
      ),
    );
  }

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: TrainTheme.glowCyan,
              backgroundColor: TrainTheme.glowCyan.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 16),
          Text('正在连接...',
              style: TrainTheme.rajdhaniStyle(
                  fontSize: 14, color: TrainTheme.glowCyan)),
          const SizedBox(height: 4),
          Text(_connectingId,
              style: TrainTheme.orbitronStyle(
                  fontSize: 10, color: TrainTheme.textDim)),
        ],
      ),
    );
  }

  Widget _buildContent(
      List<SavedTrain> trains, String? selectedId, bool isConn) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (trains.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('已保存',
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 12,
                    color: TrainTheme.textDim,
                    letterSpacing: 2)),
          ),
          ...trains.map((t) => _savedTile(
              t, t.id == selectedId, t.id == selectedId && isConn)),
          const SizedBox(height: 12),
        ],
        if (_results.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('发现设备',
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 12,
                    color: TrainTheme.textDim,
                    letterSpacing: 2)),
          ),
          ..._results.map((r) {
            final saved =
                trains.any((t) => t.id == r.device.remoteId.str);
            return _scanTile(r, saved);
          }),
        ],
        if (trains.isEmpty && _results.isEmpty && !_scanning)
          Padding(
            padding: const EdgeInsets.only(top: 50),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.train, size: 40, color: TrainTheme.textDim),
                  const SizedBox(height: 10),
                  Text('点击"扫描添加"搜索火车',
                      style: TrainTheme.rajdhaniStyle(
                          fontSize: 13, color: TrainTheme.textDim)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: TrainTheme.metalBtnGradient,
          borderRadius: BorderRadius.circular(4),
          border:
              Border.all(color: TrainTheme.metalDark, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              offset: Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _savedTile(
      SavedTrain train, bool selected, bool connected) {
    final borderColor = connected
        ? TrainTheme.glowGreen
        : selected
            ? TrainTheme.glowCyan.withOpacity(0.3)
            : const Color(0xFF222222);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
            color: borderColor, width: connected ? 1.5 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => _reconnect(train),
          splashColor: TrainTheme.glowCyan.withOpacity(0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (connected
                            ? TrainTheme.glowGreen
                            : TrainTheme.glowCyan)
                        .withOpacity(0.1),
                    border: Border.all(
                        color: (connected
                                ? TrainTheme.glowGreen
                                : TrainTheme.glowCyan)
                            .withOpacity(0.3)),
                  ),
                  child: Icon(Icons.train,
                      color: connected
                          ? TrainTheme.glowGreen
                          : TrainTheme.glowCyan,
                      size: 14),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            train.name,
                            overflow: TextOverflow.ellipsis,
                            style: TrainTheme.orbitronStyle(
                                fontSize: 11,
                                color: TrainTheme.glowCyan),
                          ),
                        ),
                        if (connected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: TrainTheme.glowGreen
                                  .withOpacity(0.2),
                              borderRadius:
                                  BorderRadius.circular(2),
                            ),
                            child: Text('已连接',
                                style: TrainTheme.rajdhaniStyle(
                                    fontSize: 9,
                                    color:
                                        TrainTheme.glowGreen)),
                          ),
                        ],
                      ]),
                      Text(train.id,
                          style: TrainTheme.rajdhaniStyle(
                              fontSize: 9,
                              color: TrainTheme.textDim)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _renameDialog(train),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit,
                        size: 14, color: TrainTheme.textDim),
                  ),
                ),
                GestureDetector(
                  onTap: () => ref
                      .read(trainManagerProvider.notifier)
                      .removeTrain(train.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        size: 14,
                        color:
                            TrainTheme.glowRed.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scanTile(ScanResult result, bool alreadySaved) {
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : 'Unknown';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: alreadySaved
              ? null
              : () => _connectAndAdd(result),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.bluetooth,
                    size: 16, color: TrainTheme.glowCyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TrainTheme.orbitronStyle(
                              fontSize: 11,
                              color: TrainTheme.glowCyan)),
                      Text(
                        '${result.device.remoteId.str}  ${result.rssi}dBm',
                        style: TrainTheme.rajdhaniStyle(
                            fontSize: 9,
                            color: TrainTheme.textDim),
                      ),
                    ],
                  ),
                ),
                if (alreadySaved)
                  Text('已添加',
                      style: TrainTheme.rajdhaniStyle(
                          fontSize: 10,
                          color: TrainTheme.textDim))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: TrainTheme.glowCyan
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                          color: TrainTheme.glowCyan
                              .withOpacity(0.3)),
                    ),
                    child: Text('添加',
                        style: TrainTheme.rajdhaniStyle(
                            fontSize: 10,
                            color: TrainTheme.glowCyan)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _renameDialog(SavedTrain train) {
    final ctrl = TextEditingController(text: train.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C20),
        title: Text('重命名',
            style: TrainTheme.rajdhaniStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          style: TrainTheme.orbitronStyle(
              fontSize: 13, color: TrainTheme.glowCyan),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0A0E14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide:
                  const BorderSide(color: Color(0xFF333333)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 14,
                    color: TrainTheme.textDim)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(trainManagerProvider.notifier)
                    .renameTrain(train.id, name);
              }
              Navigator.pop(ctx);
            },
            child: Text('确定',
                style: TrainTheme.rajdhaniStyle(
                    fontSize: 14,
                    color: TrainTheme.glowCyan)),
          ),
        ],
      ),
    );
  }
}