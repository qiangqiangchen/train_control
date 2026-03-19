import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  BleConstants._();

  static const String deviceNameFilter = 'BLE_Train';
  static final Guid serviceUuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid controlCharUuid = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');
  static final Guid statusCharUuid = Guid('8c224e70-1b0a-4f66-b4c3-16e4c2e70391');
  static final Guid versionCharUuid = Guid('8c224e70-1b0a-4f66-b4c3-16e4c2e70394');

  static const int commandThrottleMs = 150;
  static const int maxReconnectAttempts = 3;
  static const int reconnectIntervalSec = 2;
  static const int maxNotch = 8;
  static const int maxPwm = 255;
  static const double minCoefficient = 0.90;
  static const double maxCoefficient = 1.10;
  static const double coefficientStep = 0.01;
}

class BleCommands {
  BleCommands._();
  static String forward(int notch) => 'F:$notch';
  static String reverse(int notch) => 'R:$notch';
  static const String stop = 'S';
  static const String lightToggle = 'L';
  static const String soundToggle = 'M';
  static const String changeCab = 'C';
  static const String coupleInvite = 'CP';
  static const String coupleStop = 'CP:STOP';
  static String joinA() => 'J:A';
  static String joinB() => 'J:B';
  static const String uncouple = 'U';
  static String setCoefficient(double k) => 'K:${k.toStringAsFixed(2)}';
}