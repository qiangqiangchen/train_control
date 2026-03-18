/// BLE 通信常量和 UUID 定义
///
/// 包含所有 BLE 服务/特征 UUID、设备名称过滤、通信参数等。

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  BleConstants._();

  /// 设备名称过滤前缀
  static const String deviceNameFilter = 'BLE_Train';

  /// BLE 服务 UUID
  static final Guid serviceUuid =
      Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');

  /// 控制特征 UUID (App → 火车，Write + WriteWithoutResponse)
  static final Guid controlCharUuid =
      Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  /// 状态特征 UUID (火车 → App，Read + Notify)
  static final Guid statusCharUuid =
      Guid('8c224e70-1b0a-4f66-b4c3-16e4c2e70391');

  /// 版本特征 UUID (只读)
  static final Guid versionCharUuid =
      Guid('8c224e70-1b0a-4f66-b4c3-16e4c2e70394');

  /// 状态上报间隔（约200ms）
  static const int statusIntervalMs = 200;

  /// 指令节流间隔
  static const int commandThrottleMs = 150;

  /// 自动重连次数
  static const int maxReconnectAttempts = 3;

  /// 重连间隔（秒）
  static const int reconnectIntervalSec = 2;

  /// 最大档位
  static const int maxNotch = 8;

  /// 最大 PWM 值
  static const int maxPwm = 255;

  /// 速度系数范围
  static const double minCoefficient = 0.90;
  static const double maxCoefficient = 1.10;
  static const double coefficientStep = 0.01;
}

/// BLE 指令构建器
class BleCommands {
  BleCommands._();

  static String forward(int notch) => 'F:$notch';
  static String reverse(int notch) => 'R:$notch';
  static const String stop = 'S';
  static const String lightToggle = 'L';
  static String lightOn() => 'L:1';
  static String lightOff() => 'L:0';
  static const String soundToggle = 'M';
  static String soundOn() => 'M:1';
  static String soundOff() => 'M:0';
  static const String changeCab = 'C';
  static const String coupleInvite = 'CP';
  static const String coupleStop = 'CP:STOP';
  static String joinA() => 'J:A';
  static String joinB() => 'J:B';
  static const String uncouple = 'U';
  static String setCoefficient(double k) => 'K:${k.toStringAsFixed(2)}';
}