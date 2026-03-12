/// Riverpod 状态管理
///
/// 提供 BLE 服务、火车状态、连接状态等的全局状态管理。
/// 使用 StateNotifier 模式，UI 通过 Consumer 监听状态变化。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/train_state.dart';
import '../services/ble_service.dart';
import '../services/state_parser.dart';
import '../utils/constants.dart';

// === BLE 服务 Provider ===
final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() => service.dispose());
  return service;
});

// === BLE 连接状态 Provider ===
final bleConnectionStateProvider =
    StreamProvider<BleConnectionState>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.connectionStateStream;
});

// === 火车状态 Notifier ===
class TrainStateNotifier extends StateNotifier<TrainState> {
  final BleService _bleService;
  StreamSubscription? _statusSubscription;

  // 本地控制状态（用于UI交互，在BLE回复前先行显示）
  TrainDirection _localDirection = TrainDirection.stop;
  int _localNotch = 0;
  TrainDirection _lastNonStopDirection = TrainDirection.forward;

  TrainDirection get localDirection => _localDirection;
  int get localNotch => _localNotch;
  TrainDirection get lastNonStopDirection => _lastNonStopDirection;

  TrainStateNotifier(this._bleService) : super(const TrainState()) {
    _statusSubscription = _bleService.statusDataStream.listen(_onStatusData);
  }

  /// 接收到 BLE 状态数据
  void _onStatusData(String data) {
    final newState = StateParser.parse(data);

    // 处理错误消息
    if (newState.error != TrainError.none) {
      debugPrint('火车错误: ${StateParser.errorMessage(newState.error)}');
      // 暂时保留旧状态，只更新错误字段
      state = state.copyWith(error: newState.error, rawData: data);
      return;
    }

    // 同步本地状态与 BLE 回报
    _localDirection = newState.direction;
    _localNotch = newState.level;
    if (newState.direction != TrainDirection.stop) {
      _lastNonStopDirection = newState.direction;
    }

    // 清除之前的错误
    state = newState.copyWith(error: TrainError.none);
  }

  // === 方向控制 ===

  /// 切换到前进
  void setForward() {
    if (state.isSlave) return;

    // 安全检查：运行中不能从 R 直接切到 F
    if (state.isRunning && state.direction == TrainDirection.reverse) {
      return;
    }

    _localDirection = TrainDirection.forward;
    _lastNonStopDirection = TrainDirection.forward;

    // 如果档位为0，自动提到1档
    final notch = _localNotch > 0 ? _localNotch : 1;
    _localNotch = notch;

    _bleService.sendCommandImmediate(BleCommands.forward(notch));
  }

  /// 切换到后退
  void setReverse() {
    if (state.isSlave) return;

    // 安全检查：运行中不能从 F 直接切到 R
    if (state.isRunning && state.direction == TrainDirection.forward) {
      return;
    }

    _localDirection = TrainDirection.reverse;
    _lastNonStopDirection = TrainDirection.reverse;

    final notch = _localNotch > 0 ? _localNotch : 1;
    _localNotch = notch;

    _bleService.sendCommandImmediate(BleCommands.reverse(notch));
  }

  /// 停车
  void setStop() {
    if (state.isSlave) return;

    _localDirection = TrainDirection.stop;
    _localNotch = 0;
    _bleService.sendCommandImmediate(BleCommands.stop);
  }

  // === 油门控制 ===

  /// 设置档位（拖动过程中，带节流）
  void setNotch(int notch) {
    if (state.isSlave) return;

    notch = notch.clamp(0, BleConstants.maxNotch);
    _localNotch = notch;

    if (notch == 0) {
      _bleService.sendCommand(BleCommands.stop);
      return;
    }

    // 如果当前方向是停车，自动恢复上次方向
    if (_localDirection == TrainDirection.stop) {
      _localDirection = _lastNonStopDirection;
    }

    final cmd = _localDirection == TrainDirection.reverse
        ? BleCommands.reverse(notch)
        : BleCommands.forward(notch);

    _bleService.sendCommand(cmd);

    // 触觉反馈
    HapticFeedback.lightImpact();
  }

  /// 设置档位（松手时，立即发送）
  void setNotchFinal(int notch) {
    if (state.isSlave) return;

    notch = notch.clamp(0, BleConstants.maxNotch);
    _localNotch = notch;

    if (notch == 0) {
      _bleService.sendCommandImmediate(BleCommands.stop);
      return;
    }

    if (_localDirection == TrainDirection.stop) {
      _localDirection = _lastNonStopDirection;
    }

    final cmd = _localDirection == TrainDirection.reverse
        ? BleCommands.reverse(notch)
        : BleCommands.forward(notch);

    _bleService.sendCommandImmediate(cmd);
    HapticFeedback.mediumImpact();
  }

  // === 紧急停车 ===
  void emergencyStop() {
    _localDirection = TrainDirection.stop;
    _localNotch = 0;
    _bleService.sendCommandImmediate(BleCommands.stop);
    HapticFeedback.heavyImpact();
  }

  // === 功能按钮 ===

  /// 切换车头灯
  void toggleLight() {
    if (state.isSlave) return;
    _bleService.sendCommandImmediate(BleCommands.lightToggle);
  }

  /// 切换音效
  void toggleSound() {
    if (state.isSlave) return;
    _bleService.sendCommandImmediate(BleCommands.soundToggle);
  }

  /// 换端（停车时可用）
  void changeCab() {
    if (state.isSlave) return;
    if (state.isRunning) return;
    _bleService.sendCommandImmediate(BleCommands.changeCab);
  }

  // === 重联控制 ===

  /// 发起/取消重联邀请
  void toggleCouple() {
    if (state.isSlave) return;

    if (state.coupleStatus == CoupleStatus.off) {
      _bleService.sendCommandImmediate(BleCommands.coupleInvite);
    } else if (state.coupleStatus == CoupleStatus.inviting) {
      _bleService.sendCommandImmediate(BleCommands.coupleStop);
    }
  }

  /// 接受重联邀请（A端）
  void acceptCoupleA() {
    _bleService.sendCommandImmediate(BleCommands.joinA());
  }

  /// 接受重联邀请（B端）
  void acceptCoupleB() {
    _bleService.sendCommandImmediate(BleCommands.joinB());
  }

  /// 解除重联
  void uncouple() {
    if (!state.isMaster) return;
    if (state.isRunning) return;
    _bleService.sendCommandImmediate(BleCommands.uncouple);
  }

  /// 设置速度系数
  void setSpeedCoefficient(double k) {
    if (!state.isMaster) return;
    k = k.clamp(BleConstants.minCoefficient, BleConstants.maxCoefficient);
    _bleService.sendCommand(BleCommands.setCoefficient(k));
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: TrainError.none);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}

// === 火车状态 Provider ===
final trainStateProvider =
    StateNotifierProvider<TrainStateNotifier, TrainState>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  return TrainStateNotifier(bleService);
});

// === 扫描结果 Provider ===
final scanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  return FlutterBluePlus.scanResults;
});

// === 是否正在扫描 Provider ===
final isScanningProvider = StreamProvider<bool>((ref) {
  return FlutterBluePlus.isScanning;
});