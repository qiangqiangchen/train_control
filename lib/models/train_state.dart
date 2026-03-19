import 'package:flutter/foundation.dart';

enum TrainDirection { stop, forward, reverse }
enum CoupleStatus { off, inviting, invited, master, slave }
enum CabEnd { a, b }
enum TrainError {
  none, stopFirst, slaveMode, demoStopping,
  alreadyCoupled, notCoupled, invalidCoeff, unknown
}

@immutable
class TrainState {
  final CabEnd cab;
  final bool headlight;
  final TrainDirection direction;
  final int level;
  final int actualPwm;
  final int targetPwm;
  final bool soundEnabled;
  final bool soundPlaying;
  final bool demoMode;
  final int battery;
  final double batteryVoltage;
  final bool batteryLow;
  final CoupleStatus coupleStatus;
  final String? inviterMac;
  final CabEnd? slaveCab;
  final int? slaveActualPwm;
  final int? slaveBattery;
  final double? slaveBatteryVoltage;
  final double? speedCoefficient;
  final bool slaveWarning;
  final String firmwareVersion;
  final TrainError error;
  final String rawData;

  const TrainState({
    this.cab = CabEnd.a,
    this.headlight = false,
    this.direction = TrainDirection.stop,
    this.level = 0,
    this.actualPwm = 0,
    this.targetPwm = 0,
    this.soundEnabled = false,
    this.soundPlaying = false,
    this.demoMode = false,
    this.battery = 0,
    this.batteryVoltage = 0.0,
    this.batteryLow = false,
    this.coupleStatus = CoupleStatus.off,
    this.inviterMac,
    this.slaveCab,
    this.slaveActualPwm,
    this.slaveBattery,
    this.slaveBatteryVoltage,
    this.speedCoefficient,
    this.slaveWarning = false,
    this.firmwareVersion = '',
    this.error = TrainError.none,
    this.rawData = '',
  });

  bool get isRunning => actualPwm > 0;
  bool get isMaster => coupleStatus == CoupleStatus.master;
  bool get isSlave => coupleStatus == CoupleStatus.slave;
  bool get isCoupled => isMaster || isSlave;
  bool get isInviting => coupleStatus == CoupleStatus.inviting;
  bool get isInvited => coupleStatus == CoupleStatus.invited;

  TrainState copyWith({
    CabEnd? cab, bool? headlight, TrainDirection? direction, int? level,
    int? actualPwm, int? targetPwm, bool? soundEnabled, bool? soundPlaying,
    bool? demoMode, int? battery, double? batteryVoltage, bool? batteryLow,
    CoupleStatus? coupleStatus, String? inviterMac, CabEnd? slaveCab,
    int? slaveActualPwm, int? slaveBattery, double? slaveBatteryVoltage,
    double? speedCoefficient, bool? slaveWarning, String? firmwareVersion,
    TrainError? error, String? rawData,
  }) {
    return TrainState(
      cab: cab ?? this.cab,
      headlight: headlight ?? this.headlight,
      direction: direction ?? this.direction,
      level: level ?? this.level,
      actualPwm: actualPwm ?? this.actualPwm,
      targetPwm: targetPwm ?? this.targetPwm,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundPlaying: soundPlaying ?? this.soundPlaying,
      demoMode: demoMode ?? this.demoMode,
      battery: battery ?? this.battery,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryLow: batteryLow ?? this.batteryLow,
      coupleStatus: coupleStatus ?? this.coupleStatus,
      inviterMac: inviterMac ?? this.inviterMac,
      slaveCab: slaveCab ?? this.slaveCab,
      slaveActualPwm: slaveActualPwm ?? this.slaveActualPwm,
      slaveBattery: slaveBattery ?? this.slaveBattery,
      slaveBatteryVoltage: slaveBatteryVoltage ?? this.slaveBatteryVoltage,
      speedCoefficient: speedCoefficient ?? this.speedCoefficient,
      slaveWarning: slaveWarning ?? this.slaveWarning,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      error: error ?? this.error,
      rawData: rawData ?? this.rawData,
    );
  }
}