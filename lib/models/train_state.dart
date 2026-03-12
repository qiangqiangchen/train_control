/// 火车状态数据模型
///
/// 解析 BLE 上报的状态字符串，存储所有火车参数。
/// 包含本车状态和补机状态（重联模式时）。

import 'package:flutter/foundation.dart';

/// 运行方向枚举
enum TrainDirection { stop, forward, reverse }

/// 重联状态枚举
enum CoupleStatus { off, inviting, invited, master, slave }

/// 驾驶端枚举
enum CabEnd { a, b }

/// 错误类型枚举
enum TrainError {
  none,
  stopFirst,
  slaveMode,
  demoStopping,
  alreadyCoupled,
  notCoupled,
  invalidCoeff,
  unknown,
}

@immutable
class TrainState {
  /// 驾驶端
  final CabEnd cab;

  /// 车头灯
  final bool headlight;

  /// 物理运行方向
  final TrainDirection direction;

  /// 目标档位 (0~8)
  final int level;

  /// 实际 PWM (0~255)
  final int actualPwm;

  /// 目标 PWM (0~255)
  final int targetPwm;

  /// 音效总开关
  final bool soundEnabled;

  /// 音效实际播放
  final bool soundPlaying;

  /// 演示模式
  final bool demoMode;

  /// 电池百分比 (0~100)
  final int battery;

  /// 电池电压
  final double batteryVoltage;

  /// 低电量警告
  final bool batteryLow;

  /// 重联状态
  final CoupleStatus coupleStatus;

  /// 邀请来源 MAC (仅 INVITED 状态)
  final String? inviterMac;

  /// 补机连接端 (仅 MASTER)
  final CabEnd? slaveCab;

  /// 补机实际 PWM (仅 MASTER)
  final int? slaveActualPwm;

  /// 补机电量 (仅 MASTER)
  final int? slaveBattery;

  /// 补机电压 (仅 MASTER)
  final double? slaveBatteryVoltage;

  /// 速度系数 (仅 MASTER)
  final double? speedCoefficient;

  /// 补机通信异常 (仅 MASTER)
  final bool slaveWarning;

  /// 固件版本
  final String firmwareVersion;

  /// 错误信息
  final TrainError error;

  /// 原始状态字符串
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

  /// 是否正在运行（实际 PWM > 0）
  bool get isRunning => actualPwm > 0;

  /// 是否为本务机
  bool get isMaster => coupleStatus == CoupleStatus.master;

  /// 是否为补机
  bool get isSlave => coupleStatus == CoupleStatus.slave;

  /// 是否重联运行中
  bool get isCoupled => isMaster || isSlave;

  /// 是否正在邀请
  bool get isInviting => coupleStatus == CoupleStatus.inviting;

  /// 是否收到邀请
  bool get isInvited => coupleStatus == CoupleStatus.invited;

  /// 复制修改
  TrainState copyWith({
    CabEnd? cab,
    bool? headlight,
    TrainDirection? direction,
    int? level,
    int? actualPwm,
    int? targetPwm,
    bool? soundEnabled,
    bool? soundPlaying,
    bool? demoMode,
    int? battery,
    double? batteryVoltage,
    bool? batteryLow,
    CoupleStatus? coupleStatus,
    String? inviterMac,
    CabEnd? slaveCab,
    int? slaveActualPwm,
    int? slaveBattery,
    double? slaveBatteryVoltage,
    double? speedCoefficient,
    bool? slaveWarning,
    String? firmwareVersion,
    TrainError? error,
    String? rawData,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainState &&
          runtimeType == other.runtimeType &&
          rawData == other.rawData;

  @override
  int get hashCode => rawData.hashCode;
}