import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/train_state.dart';
import '../models/saved_train.dart';
import '../services/ble_service.dart';
import '../services/state_parser.dart';
import '../utils/constants.dart';

final bleServiceProvider = Provider<BleService>((ref) {
  final svc = BleService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) {
  return ref.watch(bleServiceProvider).connectionStateStream;
});

final scanResultsProvider = StreamProvider<List<ScanResult>>((ref) {
  return FlutterBluePlus.scanResults;
});

final isScanningProvider = StreamProvider<bool>((ref) {
  return FlutterBluePlus.isScanning;
});

// 多火车管理
class TrainManagerNotifier extends StateNotifier<List<SavedTrain>> {
  TrainManagerNotifier() : super([]) {
    _load();
  }

  static const _key = 'saved_trains';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        final trains = SavedTrain.decodeList(json);
        if (mounted) {
          state = trains;
        }
      }
    } catch (e) {
      debugPrint('Load saved trains error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, SavedTrain.encodeList(state));
    } catch (e) {
      debugPrint('Save trains error: $e');
    }
  }

  void addTrain(SavedTrain train) {
    if (state.any((t) => t.id == train.id)) return;
    state = [...state, train];
    _save();
  }

  void removeTrain(String id) {
    state = state.where((t) => t.id != id).toList();
    _save();
  }

  void updateLastConnected(String id) {
    state = state.map((t) {
      if (t.id == id) {
        return SavedTrain(
          id: t.id,
          name: t.name,
          deviceName: t.deviceName,
          lastConnected: DateTime.now(),
        );
      }
      return t;
    }).toList();
    _save();
  }

  void renameTrain(String id, String newName) {
    state = state.map((t) {
      if (t.id == id) {
        return SavedTrain(
          id: t.id,
          name: newName,
          deviceName: t.deviceName,
          lastConnected: t.lastConnected,
        );
      }
      return t;
    }).toList();
    _save();
  }
}

final trainManagerProvider =
    StateNotifierProvider<TrainManagerNotifier, List<SavedTrain>>(
        (ref) => TrainManagerNotifier());

final selectedTrainIdProvider = StateProvider<String?>((ref) => null);

// 火车控制状态
class TrainStateNotifier extends StateNotifier<TrainState> {
  final BleService _ble;
  StreamSubscription<String>? _sub;

  TrainDirection _localDir = TrainDirection.stop;
  int _localNotch = 0;
  TrainDirection _lastNonStop = TrainDirection.forward;

  TrainDirection get localDirection => _localDir;
  int get localNotch => _localNotch;

  TrainStateNotifier(this._ble) : super(const TrainState()) {
    _sub = _ble.statusDataStream.listen(
      _onStatus,
      onError: (e) {
        debugPrint('Status stream error: $e');
      },
    );
  }

  void _onStatus(String data) {
    if (!mounted) return;
    try {
      final s = StateParser.parse(data);
      if (s.error != TrainError.none) {
        state = state.copyWith(error: s.error, rawData: data);
        return;
      }
      _localDir = s.direction;
      _localNotch = s.level;
      if (s.direction != TrainDirection.stop) _lastNonStop = s.direction;
      state = s.copyWith(error: TrainError.none);
    } catch (e) {
      debugPrint('Parse status error: $e');
    }
  }

  void setForward() {
    if (!mounted || state.isSlave) return;
    if (state.isRunning && _localDir == TrainDirection.reverse) return;
    _localDir = TrainDirection.forward;
    _lastNonStop = TrainDirection.forward;
    final notch = _localNotch > 0 ? _localNotch : 1;
    _localNotch = notch;
    _ble.sendImmediate(BleCommands.forward(notch));
  }

  void setReverse() {
    if (!mounted || state.isSlave) return;
    if (state.isRunning && _localDir == TrainDirection.forward) return;
    _localDir = TrainDirection.reverse;
    _lastNonStop = TrainDirection.reverse;
    final notch = _localNotch > 0 ? _localNotch : 1;
    _localNotch = notch;
    _ble.sendImmediate(BleCommands.reverse(notch));
  }

  void setStop() {
    if (!mounted || state.isSlave) return;
    _localDir = TrainDirection.stop;
    _localNotch = 0;
    _ble.sendImmediate(BleCommands.stop);
  }

  void setNotch(int notch) {
    if (!mounted || state.isSlave) return;
    notch = notch.clamp(0, BleConstants.maxNotch);
    _localNotch = notch;
    // 速度为0，不切换到停止状态
    // if (notch == 0) {
    //   _ble.sendCommand(BleCommands.stop);
    //   return;
    // }
    if (_localDir == TrainDirection.stop) _localDir = _lastNonStop;
    final cmd = _localDir == TrainDirection.reverse
        ? BleCommands.reverse(notch)
        : BleCommands.forward(notch);
    _ble.sendCommand(cmd);
    try { HapticFeedback.lightImpact(); } catch (_) {}
  }

  void setNotchFinal(int notch) {
    if (!mounted || state.isSlave) return;
    notch = notch.clamp(0, BleConstants.maxNotch);
    _localNotch = notch;
    // 速度为0，不切换到停止状态
    // if (notch == 0) {
    //   _ble.sendImmediate(BleCommands.stop);
    //   return;
    // }
    if (_localDir == TrainDirection.stop) _localDir = _lastNonStop;
    final cmd = _localDir == TrainDirection.reverse
        ? BleCommands.reverse(notch)
        : BleCommands.forward(notch);
    _ble.sendImmediate(cmd);
    try { HapticFeedback.mediumImpact(); } catch (_) {}
  }

  void emergencyStop() {
    if (!mounted) return;
    _localDir = TrainDirection.stop;
    _localNotch = 0;
    _ble.sendImmediate(BleCommands.stop);
    try { HapticFeedback.heavyImpact(); } catch (_) {}
  }

  void toggleLight() {
    if (!mounted || state.isSlave) return;
    _ble.sendImmediate(BleCommands.lightToggle);
  }

  void toggleSound() {
    if (!mounted || state.isSlave) return;
    _ble.sendImmediate(BleCommands.soundToggle);
  }

  void changeCab() {
    if (!mounted || state.isSlave || state.isRunning) return;
    _ble.sendImmediate(BleCommands.changeCab);
  }

  void toggleCouple() {
    if (!mounted || state.isSlave) return;
    if (state.coupleStatus == CoupleStatus.off) {
      _ble.sendImmediate(BleCommands.coupleInvite);
    } else if (state.isInviting) {
      _ble.sendImmediate(BleCommands.coupleStop);
    }
  }

  void acceptCoupleA() {
    if (!mounted) return;
    _ble.sendImmediate(BleCommands.joinA());
  }

  void acceptCoupleB() {
    if (!mounted) return;
    _ble.sendImmediate(BleCommands.joinB());
  }

  void uncouple() {
    if (!mounted || !state.isMaster || state.isRunning) return;
    _ble.sendImmediate(BleCommands.uncouple);
  }

  void setSpeedCoefficient(double k) {
    if (!mounted || !state.isMaster) return;
    k = k.clamp(BleConstants.minCoefficient, BleConstants.maxCoefficient);
    _ble.sendCommand(BleCommands.setCoefficient(k));
  }

  void clearError() {
    if (!mounted) return;
    if (state.error != TrainError.none) {
      state = state.copyWith(error: TrainError.none);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

final trainStateProvider =
    StateNotifierProvider<TrainStateNotifier, TrainState>((ref) {
  return TrainStateNotifier(ref.watch(bleServiceProvider));
});