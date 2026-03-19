import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/constants.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
}

class BleService {
  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;

  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _statusChar;

  final _connectionStateCtrl = StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get connectionStateStream => _connectionStateCtrl.stream;

  final _statusDataCtrl = StreamController<String>.broadcast();
  Stream<String> get statusDataStream => _statusDataCtrl.stream;

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get currentState => _state;

  StreamSubscription<BluetoothConnectionState>? _deviceStateSub;
  StreamSubscription<List<int>>? _notifySub;
  DateTime _lastCmdTime = DateTime.now();
  Timer? _throttleTimer;
  String? _pendingCmd;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  bool _disposed = false;

  void _setState(BleConnectionState s) {
    if (_disposed) return;
    _state = s;
    if (!_connectionStateCtrl.isClosed) {
      _connectionStateCtrl.add(s);
    }
  }

  /// 检查蓝牙是否可用
  Future<bool> isBluetoothAvailable() async {
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) return false;

      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('BT check error: $e');
      return false;
    }
  }

  Future<Stream<List<ScanResult>>> startScan() async {
    _setState(BleConnectionState.scanning);
    try {
      // 先检查蓝牙状态
      final available = await isBluetoothAvailable();
      if (!available) {
        debugPrint('BLE: Bluetooth not available');
        _setState(BleConnectionState.disconnected);
        return FlutterBluePlus.scanResults;
      }

      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withNames: [BleConstants.deviceNameFilter],
      );
    } catch (e) {
      debugPrint('Scan error: $e');
      _setState(BleConnectionState.disconnected);
    }
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Stop scan error: $e');
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _setState(BleConnectionState.connecting);
      _device = device;
      _intentionalDisconnect = false;
      _reconnectAttempts = 0;

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // 等待一下确保连接稳定
      await Future.delayed(const Duration(milliseconds: 500));

      List<BluetoothService> services;
      try {
        services = await device.discoverServices();
      } catch (e) {
        debugPrint('Discover services error: $e');
        try { await device.disconnect(); } catch (_) {}
        _setState(BleConnectionState.disconnected);
        return false;
      }

      BluetoothService? svc;
      for (final s in services) {
        if (s.uuid == BleConstants.serviceUuid) {
          svc = s;
          break;
        }
      }
      if (svc == null) {
        debugPrint('BLE: Target service not found');
        try { await device.disconnect(); } catch (_) {}
        _setState(BleConnectionState.disconnected);
        return false;
      }

      _controlChar = null;
      _statusChar = null;
      for (final c in svc.characteristics) {
        if (c.uuid == BleConstants.controlCharUuid) _controlChar = c;
        if (c.uuid == BleConstants.statusCharUuid) _statusChar = c;
      }
      if (_controlChar == null || _statusChar == null) {
        debugPrint('BLE: Required characteristics not found');
        try { await device.disconnect(); } catch (_) {}
        _setState(BleConnectionState.disconnected);
        return false;
      }

      // 订阅通知
      try {
        await _statusChar!.setNotifyValue(true);
      } catch (e) {
        debugPrint('BLE: Set notify error: $e');
      }

      _notifySub?.cancel();
      _notifySub = _statusChar!.onValueReceived.listen(
        (v) {
          if (!_disposed && !_statusDataCtrl.isClosed) {
            try {
              _statusDataCtrl.add(utf8.decode(v));
            } catch (e) {
              debugPrint('Decode status error: $e');
            }
          }
        },
        onError: (e) {
          debugPrint('Notify stream error: $e');
        },
      );

      // 监听断连
      _deviceStateSub?.cancel();
      _deviceStateSub = device.connectionState.listen(
        (s) {
          if (s == BluetoothConnectionState.disconnected) {
            _handleDisconnection();
          }
        },
        onError: (e) {
          debugPrint('Connection state stream error: $e');
        },
      );

      _setState(BleConnectionState.connected);
      debugPrint('BLE: Connected to ${device.platformName}');
      return true;
    } catch (e) {
      debugPrint('BLE connect error: $e');
      _setState(BleConnectionState.disconnected);
      return false;
    }
  }

  Future<void> sendCommand(String cmd, {bool throttle = true}) async {
    if (_controlChar == null || _state != BleConnectionState.connected) return;
    if (throttle) {
      final elapsed = DateTime.now().difference(_lastCmdTime).inMilliseconds;
      if (elapsed < BleConstants.commandThrottleMs) {
        _pendingCmd = cmd;
        _throttleTimer?.cancel();
        _throttleTimer = Timer(
          Duration(milliseconds: BleConstants.commandThrottleMs - elapsed),
          () {
            if (_pendingCmd != null) {
              _doSend(_pendingCmd!);
              _pendingCmd = null;
            }
          },
        );
        return;
      }
    }
    await _doSend(cmd);
  }

  Future<void> sendImmediate(String cmd) => sendCommand(cmd, throttle: false);

  Future<void> _doSend(String cmd) async {
    if (_disposed) return;
    if (_controlChar == null || _state != BleConnectionState.connected) return;
    try {
      await _controlChar!.write(utf8.encode(cmd), withoutResponse: true);
      _lastCmdTime = DateTime.now();
      debugPrint('BLE TX: $cmd');
    } catch (e) {
      debugPrint('BLE send error: $e');
    }
  }

  void _handleDisconnection() {
    if (_disposed) return;
    if (_intentionalDisconnect) {
      _setState(BleConnectionState.disconnected);
      return;
    }
    debugPrint('BLE: Unexpected disconnect, reconnecting...');
    _setState(BleConnectionState.reconnecting);
    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= BleConstants.maxReconnectAttempts) {
      debugPrint('BLE: Max reconnect attempts reached');
      _setState(BleConnectionState.disconnected);
      _reconnectAttempts = 0;
      return;
    }
    _reconnectAttempts++;
    debugPrint('BLE: Reconnect attempt $_reconnectAttempts');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: BleConstants.reconnectIntervalSec),
      () async {
        if (_disposed) return;
        if (_device != null && _state == BleConnectionState.reconnecting) {
          final ok = await connectToDevice(_device!);
          if (!ok && !_disposed) _attemptReconnect();
        }
      },
    );
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _throttleTimer?.cancel();
    _reconnectTimer?.cancel();
    _notifySub?.cancel();
    _notifySub = null;
    _deviceStateSub?.cancel();
    _deviceStateSub = null;

    try {
      await _device?.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
    _device = null;
    _controlChar = null;
    _statusChar = null;
    _setState(BleConnectionState.disconnected);
  }

  void dispose() {
    _disposed = true;
    _intentionalDisconnect = true;
    _throttleTimer?.cancel();
    _reconnectTimer?.cancel();
    _notifySub?.cancel();
    _deviceStateSub?.cancel();

    if (!_connectionStateCtrl.isClosed) {
      _connectionStateCtrl.close();
    }
    if (!_statusDataCtrl.isClosed) {
      _statusDataCtrl.close();
    }
  }
}