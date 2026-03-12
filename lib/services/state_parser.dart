/// BLE 状态字符串解析器
///
/// 将火车上报的空格分隔 key:value 字符串解析为 TrainState 对象。
/// 同时处理错误消息的解析。

import '../models/train_state.dart';

class StateParser {
  StateParser._();

  /// 解析状态字符串，返回 TrainState
  static TrainState parse(String raw) {
    final trimmed = raw.trim();

    // 检查是否为错误消息
    if (trimmed.startsWith('ERR:')) {
      return TrainState(
        error: _parseError(trimmed),
        rawData: trimmed,
      );
    }

    // 解析 key:value 对
    final Map<String, String> fields = {};
    final parts = trimmed.split(' ');
    for (final part in parts) {
      final colonIndex = part.indexOf(':');
      if (colonIndex > 0) {
        final key = part.substring(0, colonIndex);
        final value = part.substring(colonIndex + 1);
        fields[key] = value;
      }
    }

    return TrainState(
      cab: _parseCab(fields['CAB']),
      headlight: fields['HL'] == 'ON',
      direction: _parseDirection(fields['DIR']),
      level: _parseInt(fields['LV'], 0),
      actualPwm: _parseInt(fields['APWM'], 0),
      targetPwm: _parseInt(fields['TPWM'], 0),
      soundEnabled: fields['SE'] == 'ON',
      soundPlaying: fields['SND'] == 'ON',
      demoMode: fields['DM'] == 'ON',
      battery: _parseInt(fields['BAT'], 0),
      batteryVoltage: _parseDouble(fields['BATV'], 0.0),
      batteryLow: fields['BLOW'] == '1',
      coupleStatus: _parseCoupleStatus(fields['CP']),
      inviterMac: fields['INV'],
      slaveCab: fields.containsKey('SC') ? _parseCab(fields['SC']) : null,
      slaveActualPwm: _parseIntNullable(fields['SAPWM']),
      slaveBattery: _parseIntNullable(fields['SBAT']),
      slaveBatteryVoltage: _parseDoubleNullable(fields['SBATV']),
      speedCoefficient: _parseDoubleNullable(fields['SK']),
      slaveWarning: fields['SWARN'] == '1',
      firmwareVersion: fields['FW'] ?? '',
      error: TrainError.none,
      rawData: trimmed,
    );
  }

  static CabEnd _parseCab(String? value) {
    if (value == 'B') return CabEnd.b;
    return CabEnd.a;
  }

  static TrainDirection _parseDirection(String? value) {
    switch (value) {
      case 'FWD':
        return TrainDirection.forward;
      case 'REV':
        return TrainDirection.reverse;
      default:
        return TrainDirection.stop;
    }
  }

  static CoupleStatus _parseCoupleStatus(String? value) {
    switch (value) {
      case 'INVITING':
        return CoupleStatus.inviting;
      case 'INVITED':
        return CoupleStatus.invited;
      case 'MASTER':
        return CoupleStatus.master;
      case 'SLAVE':
        return CoupleStatus.slave;
      default:
        return CoupleStatus.off;
    }
  }

  static TrainError _parseError(String raw) {
    if (raw.contains('STOP_FIRST')) return TrainError.stopFirst;
    if (raw.contains('SLAVE_MODE')) return TrainError.slaveMode;
    if (raw.contains('DEMO_STOPPING')) return TrainError.demoStopping;
    if (raw.contains('ALREADY_COUPLED')) return TrainError.alreadyCoupled;
    if (raw.contains('NOT_COUPLED')) return TrainError.notCoupled;
    if (raw.contains('INVALID_COEFF')) return TrainError.invalidCoeff;
    return TrainError.unknown;
  }

  static int _parseInt(String? value, int defaultValue) {
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }

  static int? _parseIntNullable(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }

  static double _parseDouble(String? value, double defaultValue) {
    if (value == null) return defaultValue;
    return double.tryParse(value) ?? defaultValue;
  }

  static double? _parseDoubleNullable(String? value) {
    if (value == null) return null;
    return double.tryParse(value);
  }

  /// 获取错误的可读消息
  static String errorMessage(TrainError error) {
    switch (error) {
      case TrainError.stopFirst:
        return '请先停车';
      case TrainError.slaveMode:
        return '补机模式下不可操作';
      case TrainError.demoStopping:
        return '演示模式正在停止';
      case TrainError.alreadyCoupled:
        return '已经处于重联状态';
      case TrainError.notCoupled:
        return '未处于重联状态';
      case TrainError.invalidCoeff:
        return '无效的速度系数';
      case TrainError.unknown:
        return '未知错误';
      case TrainError.none:
        return '';
    }
  }
}