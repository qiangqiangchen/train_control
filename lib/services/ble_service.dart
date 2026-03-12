/// BLE 蓝牙通信服务
///
/// 封装 flutter_blue_plus 的扫描、连接、特征读写、通知订阅等操作。
/// 提供指令发送节流、自动重连、断连检测等功能。

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/constants.dart';

/// BLE 连接状态
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
}

/// BLE 服务类
class BleService {
  BleService();

  // 当前连接的设备
  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;

  // 特征引用
  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _versionChar;

  // 状态流
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  final _statusDataController = StreamController<String>.broadcast();
  Stream<String> get statusDataStream => _statusDataController.stream;

  // 内部状态
  BleConnectionState _currentState = BleConnectionState.disconnected;
  BleConnectionState get currentState => _currentState;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription? _notifySubscription;

  // 指令节流
  DateTime _lastCommandTime = DateTime.now();
  Timer? _throttleTimer;
  String? _pendingCommand;

  // 重连
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;

  /// 更新连接状态
  void _setState(BleConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  /// 开始扫描 BLE 设备
  Future<Stream<List<ScanResult>>> startScan() async {
    _setState(BleConnectionState.scanning);

    // 停止之前的扫描
    await FlutterBluePlus.stopScan();

    // 开始扫描，过滤设备名
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      withNames: [BleConstants.deviceNameFilter],
    );

    return FlutterBluePlus.scanResults;
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
  }

  /// 连接到设备
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _setState(BleConnectionState.connecting);
      _device = device;
      _intentionalDisconnect = false;
      _reconnectAttempts = 0;

      // 连接设备
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // 发现服务
      final services = await device.discoverServices();

      // 找到目标服务
      BluetoothService? targetService;
      for (final service in services) {
        if (service.uuid == BleConstants.serviceUuid) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        debugPrint('BLE: 未找到目标服务');
        await device.disconnect();
        _setState(BleConnectionState.disconnected);
        return false;
      }

      // 找到特征
      for (final char in targetService.characteristics) {
        if (char.uuid == BleConstants.controlCharUuid) {
          _controlChar = char;
        } else if (char.uuid == BleConstants.statusCharUuid) {
          _statusChar = char;
        } else if (char.uuid == BleConstants.versionCharUuid) {
          _versionChar = char;
        }
      }

      if (_controlChar == null || _statusChar == null) {
        debugPrint('BLE: 未找到必要特征');
        await device.disconnect();
        _setState(BleConnectionState.disconnected);
        return false;
      }

      // 订阅状态通知
      await _subscribeToStatus();

      // 监听设备断连
      _deviceStateSubscription?.cancel();
      _deviceStateSubscription =
          device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      _setState(BleConnectionState.connected);
      debugPrint('BLE: 已连接 ${device.platformName}');
      return true;
    } catch (e) {
      debugPrint('BLE 连接错误: $e');
      _setState(BleConnectionState.disconnected);
      return false;
    }
  }

  /// 订阅状态通知
  Future<void> _subscribeToStatus() async {
    if (_statusChar == null) return;

    try {
      await _statusChar!.setNotifyValue(true);
      _notifySubscription?.cancel();
      _notifySubscription = _statusChar!.onValueReceived.listen((value) {
        final data = utf8.decode(value);
        _statusDataController.add(data);
      });
    } catch (e) {
      debugPrint('BLE 订阅状态通知失败: $e');
    }
  }

  /// 发送指令（带节流）
  Future<void> sendCommand(String command, {bool throttle = true}) async {
    if (_controlChar == null || _currentState != BleConnectionState.connected) {
      debugPrint('BLE: 无法发送指令，未连接');
      return;
    }

    if (throttle) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastCommandTime).inMilliseconds;

      if (elapsed < BleConstants.commandThrottleMs) {
        // 节流：保存待发指令，延迟发送
        _pendingCommand = command;
        _throttleTimer?.cancel();
        _throttleTimer = Timer(
          Duration(
              milliseconds: BleConstants.commandThrottleMs - elapsed),
          () {
            if (_pendingCommand != null) {
              _doSendCommand(_pendingCommand!);
              _pendingCommand = null;
            }
          },
        );
        return;
      }
    }

    await _doSendCommand(command);
  }

  /// 立即发送指令（不节流）
  Future<void> sendCommandImmediate(String command) async {
    await sendCommand(command, throttle: false);
  }

  /// 实际发送指令
  Future<void> _doSendCommand(String command) async {
    if (_controlChar == null || _currentState != BleConnectionState.connected) {
      return;
    }

    try {
      final bytes = utf8.encode(command);
      await _controlChar!.write(bytes, withoutResponse: true);
      _lastCommandTime = DateTime.now();
      debugPrint('BLE TX: $command');
    } catch (e) {
      debugPrint('BLE 发送失败: $e');
    }
  }

  /// 读取固件版本
  Future<String?> readFirmwareVersion() async {
    if (_versionChar == null) return null;
    try {
      final value = await _versionChar!.read();
      return utf8.decode(value);
    } catch (e) {
      debugPrint('BLE 读取版本失败: $e');
      return null;
    }
  }

  /// 处理断连
  void _handleDisconnection() {
    if (_intentionalDisconnect) {
      _setState(BleConnectionState.disconnected);
      return;
    }

    debugPrint('BLE: 意外断连，尝试重连...');
    _setState(BleConnectionState.reconnecting);
    _attemptReconnect();
  }

  /// 尝试重连
  void _attemptReconnect() {
    if (_reconnectAttempts >= BleConstants.maxReconnectAttempts) {
      debugPrint('BLE: 重连失败，已达最大次数');
      _setState(BleConnectionState.disconnected);
      _reconnectAttempts = 0;
      return;
    }

    _reconnectAttempts++;
    debugPrint('BLE: 重连尝试 $_reconnectAttempts/${BleConstants.maxReconnectAttempts}');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: BleConstants.reconnectIntervalSec),
      () async {
        if (_device != null &&
            _currentState == BleConnectionState.reconnecting) {
          final success = await connectToDevice(_device!);
          if (!success) {
            _attemptReconnect();
          }
        }
      },
    );
  }

  /// 主动断开连接
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _throttleTimer?.cancel();
    _reconnectTimer?.cancel();
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();

    try {
      await _device?.disconnect();
    } catch (e) {
      debugPrint('BLE 断连错误: $e');
    }

    _device = null;
    _controlChar = null;
    _statusChar = null;
    _versionChar = null;
    _setState(BleConnectionState.disconnected);
  }

  /// 释放资源
  void dispose() {
    _intentionalDisconnect = true;
    _throttleTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _connectionStateController.close();
    _statusDataController.close();
  }
}