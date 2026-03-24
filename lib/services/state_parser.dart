import '../models/train_state.dart';

class StateParser {
  StateParser._();

  static TrainState parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('ERR:')) {
      return TrainState(error: _parseError(trimmed), rawData: trimmed);
    }


    final Map<String, String> fields = {};
    for (final part in trimmed.split(' ')) {
      final i = part.indexOf(':');
      if (i > 0) fields[part.substring(0, i)] = part.substring(i + 1);
    }

    return TrainState(
      cab: fields['CAB'] == 'B' ? CabEnd.b : CabEnd.a,
      headlight: fields['HL'] == 'ON',
      direction: _parseDir(fields['DIR']),
      level: int.tryParse(fields['LV'] ?? '') ?? 0,
      actualPwm: int.tryParse(fields['APWM'] ?? '') ?? 0,
      targetPwm: int.tryParse(fields['TPWM'] ?? '') ?? 0,
      soundEnabled: fields['SE'] == 'ON',
      soundPlaying: fields['SND'] == 'ON',
      demoMode: fields['DM'] == 'ON',
      battery: int.tryParse(fields['BAT'] ?? '') ?? 0,
      batteryVoltage: double.tryParse(fields['BATV'] ?? '') ?? 0.0,
      batteryLow: fields['BLOW'] == '1',
      coupleStatus: _parseCP(fields['CP']),
      inviterMac: fields['INV'],
      slaveCab: fields.containsKey('SC') ? (fields['SC'] == 'B' ? CabEnd.b : CabEnd.a) : null,
      slaveActualPwm: int.tryParse(fields['SAPWM'] ?? ''),
      slaveBattery: int.tryParse(fields['SBAT'] ?? ''),
      slaveBatteryVoltage: double.tryParse(fields['SBATV'] ?? ''),
      speedCoefficient: double.tryParse(fields['SK'] ?? ''),
      speed:int.tryParse(fields['SPD'] ?? '') ?? 0,
      slaveWarning: fields['SWARN'] == '1',
      firmwareVersion: fields['FW'] ?? '',
      error: TrainError.none,
      rawData: trimmed,
    );
  }

  static TrainDirection _parseDir(String? v) {
    if (v == 'FWD') return TrainDirection.forward;
    if (v == 'REV') return TrainDirection.reverse;
    return TrainDirection.stop;
  }

  static CoupleStatus _parseCP(String? v) {
    if (v == 'INVITING') return CoupleStatus.inviting;
    if (v == 'INVITED') return CoupleStatus.invited;
    if (v == 'MASTER') return CoupleStatus.master;
    if (v == 'SLAVE') return CoupleStatus.slave;
    return CoupleStatus.off;
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

  static String errorMessage(TrainError e) {
    switch (e) {
      case TrainError.stopFirst: return '请先停车';
      case TrainError.slaveMode: return '补机模式下不可操作';
      case TrainError.demoStopping: return '演示模式正在停止';
      case TrainError.alreadyCoupled: return '已处于重联状态';
      case TrainError.notCoupled: return '未处于重联状态';
      case TrainError.invalidCoeff: return '无效的速度系数';
      case TrainError.unknown: return '未知错误';
      case TrainError.none: return '';
    }
  }
}