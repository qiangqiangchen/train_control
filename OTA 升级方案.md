

# ESP32-C3 BLE OTA 升级完整方案

## 一、方案概述

通过已有 BLE 连接，从 Flutter App 直接推送固件升级到 ESP32-C3，无需额外硬件。

```
┌─────────────────────────────────────────────────────────┐
│                 ESP32-C3 Flash 分区布局 (4MB)           │
│                                                         │
│  ┌──────────┐  0x0000                                   │
│  │Bootloader│  (36KB, 固定不可覆盖)                     │
│  ├──────────┤  0x9000                                   │
│  │   NVS    │  (20KB, 非易失存储)                       │
│  ├──────────┤  0xE000                                   │
│  │ OTA Data │  (8KB, 记录当前启动分区)                  │
│  ├──────────┤  0x10000                                  │
│  │          │                                           │
│  │   app0   │  (1.875MB, 当前运行的固件)                │
│  │          │                                           │
│  ├──────────┤  0x200000                                 │
│  │          │                                           │
│  │   app1   │  (1.875MB, OTA接收的新固件)               │
│  │          │                                           │
│  ├──────────┤  0x3F0000                                 │
│  │  空闲    │  (64KB)                                   │
│  └──────────┘  0x400000                                 │
│                                                         │
│  升级流程:                                              │
│  1. App 通过 BLE 将新固件写入 app1 分区                 │
│  2. 写入完成后 ESP32 自动校验 MD5                       │
│  3. 校验通过 → 标记 app1 为下次启动分区                 │
│  4. 重启 → 从 app1 启动新固件                           │
│  5. 新固件自检通过 → 确认有效 (否则自动回滚到 app0)     │
└─────────────────────────────────────────────────────────┘
```

---

## 二、分区表配置

### 2.1 创建 `partitions_ota.csv`

在项目根目录下创建：

```csv
# Name,   Type, SubType, Offset,     Size,      Flags
nvs,      data, nvs,     0x9000,     0x5000,
otadata,  data, ota,     0xE000,     0x2000,
app0,     app,  ota_0,   0x10000,    0x1F0000,
app1,     app,  ota_1,   0x200000,   0x1F0000,
```

### 2.2 地址校验

```
nvs:     0x9000  → 0xE000   (20KB)  ✅
otadata: 0xE000  → 0x10000  (8KB)   ✅
app0:    0x10000 → 0x200000 (1.875MB = 1,966,080 字节) ✅
app1:    0x200000→ 0x3F0000 (1.875MB = 1,966,080 字节) ✅
总计:    0x3F0000 < 0x400000 (4MB)   ✅ 不越界
```

### 2.3 构建配置

**Arduino IDE：**
```
工具 → Partition Scheme → 选择 "Custom" 
并确保 partitions_ota.csv 在项目目录中
```

**PlatformIO (`platformio.ini`)：**
```ini
[env:esp32c3]
platform = espressif32
board = esp32-c3-devkitm-1
framework = arduino
board_build.partitions = partitions_ota.csv
```

---

## 三、ESP32 固件改动

### 3.1 新增头文件

```cpp
#include <Update.h>
#include <esp_ota_ops.h>
```

### 3.2 新增宏定义

```cpp
// ============================================================================
// OTA 配置
// ============================================================================
#define CHAR_OTA_UUID         "8c224e70-1b0a-4f66-b4c3-16e4c2e70392"
#define CHAR_OTA_CTRL_UUID    "8c224e70-1b0a-4f66-b4c3-16e4c2e70393"
#define OTA_PARTITION_SIZE    0x1F0000    // 1.875MB, 与分区表一致
#define OTA_TIMEOUT           60000      // 60秒无数据自动中止
#define OTA_PROGRESS_INTERVAL 2000       // 进度上报间隔 2秒
```

### 3.3 新增全局变量

```cpp
// ============================================================================
// OTA 状态
// ============================================================================
BLECharacteristic* pOtaDataChar    = nullptr;
BLECharacteristic* pOtaCtrlChar    = nullptr;
volatile bool      otaInProgress   = false;
uint32_t           otaTotalSize    = 0;
uint32_t           otaReceived     = 0;
unsigned long      otaLastDataTime = 0;
unsigned long      otaLastNotify   = 0;
```

### 3.4 新增 OTA 回调类

```cpp
// ============================================================================
// OTA 控制特征回调
// ============================================================================
// App 通过此特征发送控制指令:
//   "OTA:BEGIN:184320"  — 开始OTA, 184320为固件字节数
//   "OTA:END"           — 传输完成, 执行校验和重启
//   "OTA:ABORT"         — 中止OTA
//
// 固件通过此特征回复状态:
//   "OTA:READY"         — 已准备好接收
//   "OTA:PROGRESS:50"   — 进度50%
//   "OTA:OK"            — 升级成功, 即将重启
//   "OTA:FAIL:原因"     — 升级失败
// ============================================================================

static class OtaCtrlCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = String(pChar->getValue().c_str());
    val.trim();

    // ---- 开始 OTA ----
    if (val.startsWith("OTA:BEGIN:")) {
      uint32_t fwSize = val.substring(10).toInt();

      // 校验固件大小
      if (fwSize == 0 || fwSize > OTA_PARTITION_SIZE) {
        pOtaCtrlChar->setValue("OTA:FAIL:INVALID_SIZE");
        pOtaCtrlChar->notify();
        DBGF("[OTA] Invalid size: %d (max %d)", fwSize, OTA_PARTITION_SIZE);
        return;
      }

      // 必须停车
      if (actualPWM > 0) {
        pOtaCtrlChar->setValue("OTA:FAIL:STOP_FIRST");
        pOtaCtrlChar->notify();
        DBG("[OTA] Rejected: motor running");
        return;
      }

      // 强制停止所有输出
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      actualPWM = 0; actualDir = 0;
      motorState = STATE_IDLE;
      applyMotorPWM(0, 0);
      soundEnabled = false;
      updateSound();
      headlightOn = false;
      updateLights();

      // 开始写入
      if (!Update.begin(fwSize)) {
        char buf[40];
        snprintf(buf, sizeof(buf), "OTA:FAIL:BEGIN_%d", Update.getError());
        pOtaCtrlChar->setValue(buf);
        pOtaCtrlChar->notify();
        DBGF("[OTA] Begin failed: %d", Update.getError());
        return;
      }

      otaInProgress   = true;
      otaTotalSize    = fwSize;
      otaReceived     = 0;
      otaLastDataTime = millis();
      otaLastNotify   = 0;

      pOtaCtrlChar->setValue("OTA:READY");
      pOtaCtrlChar->notify();
      DBGF("[OTA] Started, expecting %d bytes (%.1f KB)", fwSize, fwSize / 1024.0f);
      return;
    }

    // ---- 传输完成 ----
    if (val == "OTA:END") {
      if (!otaInProgress) return;

      DBGF("[OTA] END received, total %d/%d bytes", otaReceived, otaTotalSize);

      if (Update.end(true)) {
        otaInProgress = false;
        pOtaCtrlChar->setValue("OTA:OK");
        pOtaCtrlChar->notify();
        DBGF("[OTA] Success! v%s → new firmware. Rebooting...", FIRMWARE_VERSION);
        delay(2000);  // 等待 BLE 通知发出
        ESP.restart();
      } else {
        otaInProgress = false;
        char buf[40];
        snprintf(buf, sizeof(buf), "OTA:FAIL:VERIFY_%d", Update.getError());
        pOtaCtrlChar->setValue(buf);
        pOtaCtrlChar->notify();
        DBGF("[OTA] Verify failed: %d", Update.getError());
      }
      return;
    }

    // ---- 中止 OTA ----
    if (val == "OTA:ABORT") {
      if (otaInProgress) {
        Update.abort();
        otaInProgress = false;
        pOtaCtrlChar->setValue("OTA:ABORTED");
        pOtaCtrlChar->notify();
        DBG("[OTA] Aborted by user");
      }
      return;
    }
  }
} otaCtrlCbInstance;

// ============================================================================
// OTA 数据特征回调
// ============================================================================
// App 将固件二进制数据分包写入此特征
// 使用 Write Without Response 以获得最高传输速度
// 每包有效载荷取决于协商的 MTU (通常 500~509 字节)
// ============================================================================

static class OtaDataCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    if (!otaInProgress) return;

    std::string val = pChar->getValue();
    const uint8_t* data = (const uint8_t*)val.data();
    size_t len = val.length();
    if (len == 0) return;

    // 写入 Flash
    size_t written = Update.write(data, len);
    if (written != len) {
      otaInProgress = false;
      Update.abort();
      char buf[40];
      snprintf(buf, sizeof(buf), "OTA:FAIL:WRITE@%d", otaReceived);
      pOtaCtrlChar->setValue(buf);
      pOtaCtrlChar->notify();
      DBGF("[OTA] Write error at %d bytes (wrote %d/%d)", otaReceived, written, len);
      return;
    }

    otaReceived     += len;
    otaLastDataTime  = millis();  // 更新活动时间 (用于超时检测)

    // 定时上报进度
    unsigned long now = millis();
    if (now - otaLastNotify >= OTA_PROGRESS_INTERVAL) {
      otaLastNotify = now;
      uint8_t pct = (uint8_t)((uint32_t)otaReceived * 100 / otaTotalSize);
      char buf[24];
      snprintf(buf, sizeof(buf), "OTA:PROGRESS:%d", pct);
      pOtaCtrlChar->setValue(buf);
      pOtaCtrlChar->notify();
      DBGF("[OTA] %d%% (%d/%d bytes)", pct, otaReceived, otaTotalSize);
    }
  }
} otaDataCbInstance;
```

### 3.5 修改 `setup()` — 完整插入位置

```cpp
void setup() {
  DBG_INIT(115200);
  delay(100);
  DBGF("[BOOT] BLE Train v%s", FIRMWARE_VERSION);

  esp_task_wdt_init(15, true);
  esp_task_wdt_add(NULL);

  // ---- 引脚初始化 ----
  const uint8_t outPins[] = {LED_A_WHITE, LED_B_WHITE, LED_A_RED, LED_B_RED, SOUND_POWER};
  for (auto p : outPins) { pinMode(p, OUTPUT); digitalWrite(p, LOW); }

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  ledcSetup(PWM_CH_IN1, PWM_FREQ, PWM_RES);
  ledcSetup(PWM_CH_IN2, PWM_FREQ, PWM_RES);
  ledcAttachPin(MOTOR_IN1, PWM_CH_IN1);
  ledcAttachPin(MOTOR_IN2, PWM_CH_IN2);
  ledcWrite(PWM_CH_IN1, 0);
  ledcWrite(PWM_CH_IN2, 0);

  for (int i = 0; i < BATT_AVG_COUNT; i++) { sampleBattery(); delay(10); }

  // ---- 自检 ----
  selfTest();

  // ★★★ OTA 启动确认 (自检通过后才确认新固件有效) ★★★
  {
    const esp_partition_t* running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;
    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
      if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_ota_mark_app_valid_cancel_rollback();
        DBGF("[OTA] New firmware v%s confirmed OK", FIRMWARE_VERSION);
      }
    }
    DBGF("[OTA] Running partition: %s", running->label);
  }

  // ---- WiFi / ESP-NOW ----
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
  esp_read_mac(myMAC, ESP_MAC_WIFI_STA);
  DBGF("[BOOT] MAC: %02X:%02X:%02X:%02X:%02X:%02X",
    myMAC[0],myMAC[1],myMAC[2],myMAC[3],myMAC[4],myMAC[5]);

  if (esp_now_init() != ESP_OK) DBG("[BOOT] ESP-NOW FAIL");
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_register_send_cb(onEspNowSent);

  // ---- BLE ----
  BLEDevice::init("BLE_Train");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(&serverCbInstance);

  BLEService* svc = pServer->createService(
    BLEUUID(SERVICE_UUID),
    30  // ★ 增加 handle 数量以容纳 OTA 特征 (原默认15可能不够)
  );

  // 控制特征
  pCtrlChar = svc->createCharacteristic(CHAR_CTRL_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pCtrlChar->setCallbacks(&ctrlCbInstance);

  // 状态特征
  pStatusChar = svc->createCharacteristic(CHAR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());

  // 版本特征
  BLECharacteristic* pVerChar = svc->createCharacteristic(CHAR_VERSION_UUID,
    BLECharacteristic::PROPERTY_READ);
  char verBuf[48];
  snprintf(verBuf, sizeof(verBuf), "FW:%s %s %s", FIRMWARE_VERSION, __DATE__, __TIME__);
  pVerChar->setValue(verBuf);

  // ★★★ OTA 数据特征 (App写入固件二进制数据) ★★★
  pOtaDataChar = svc->createCharacteristic(CHAR_OTA_UUID,
    BLECharacteristic::PROPERTY_WRITE_NR);
  pOtaDataChar->setCallbacks(&otaDataCbInstance);

  // ★★★ OTA 控制特征 (控制指令 + 状态回报) ★★★
  pOtaCtrlChar = svc->createCharacteristic(CHAR_OTA_CTRL_UUID,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY);
  pOtaCtrlChar->addDescriptor(new BLE2902());
  pOtaCtrlChar->setCallbacks(&otaCtrlCbInstance);

  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  bootTime = millis();
  demoState = DEMO_WAITING;

  DBGF("[BOOT] heap=%lu done", (unsigned long)esp_get_free_heap_size());
}
```

### 3.6 修改 `loop()` — 完整开头部分

```cpp
void loop() {
  unsigned long now = millis();

  esp_task_wdt_reset();
  loopCounter++;

  // ★★★ OTA 进行中: 冻结所有控制逻辑 ★★★
  if (otaInProgress) {
    esp_task_wdt_reset();

    // 安全保障: 强制所有输出关闭
    applyMotorPWM(0, 0);
    digitalWrite(SOUND_POWER, LOW);

    // 超时保护: 60秒无新数据 → 自动中止
    if (millis() - otaLastDataTime >= OTA_TIMEOUT) {
      Update.abort();
      otaInProgress = false;
      DBG("[OTA] Timeout, aborted");
      if (deviceConnected) {
        pOtaCtrlChar->setValue("OTA:FAIL:TIMEOUT");
        pOtaCtrlChar->notify();
      }
    }

    delay(1);
    return;  // 跳过后续所有正常逻辑
  }

  // ---- 以下为原有正常逻辑 (不变) ----

  #if DEBUG_ENABLED
  if (now - lastLoopReport >= 5000) {
    // ... 原有性能日志 ...
  }
  #endif

  // ---- BLE 连接 ----
  if (bleJustConnected) {
    bleJustConnected = false;
    bleDisconnectTime = 0;
    // ... 原有逻辑 ...
  }

  // ---- BLE 断连防抖 ----
  if (bleJustDisconnected) {
    bleJustDisconnected = false;
    bleDisconnectTime = now;

    // ★★★ BLE 断连时中止 OTA ★★★
    if (otaInProgress) {
      Update.abort();
      otaInProgress = false;
      DBG("[OTA] BLE disconnected, OTA aborted");
    }
  }

  // ... 原有断连防抖逻辑继续 ...
  // ... 后续所有原有逻辑不变 ...
}
```

---

## 四、Flutter App 端实现

### 4.1 新增 `ble_service.dart` 中的 OTA 相关常量和方法

需要先看你的 `ble_service.dart`，但核心 OTA 逻辑应独立为一个 service。

### 4.2 新增 `lib/services/ota_service.dart`

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// OTA 升级状态
enum OtaStatus {
  idle,        // 空闲
  preparing,   // 准备中 (发送 BEGIN)
  uploading,   // 上传中
  verifying,   // 校验中 (发送 END, 等待结果)
  success,     // 成功, 设备即将重启
  failed,      // 失败
  aborted,     // 用户中止
}

/// OTA 进度信息
class OtaProgress {
  final OtaStatus status;
  final int totalBytes;
  final int sentBytes;
  final int percent;
  final String? error;

  const OtaProgress({
    this.status = OtaStatus.idle,
    this.totalBytes = 0,
    this.sentBytes = 0,
    this.percent = 0,
    this.error,
  });

  OtaProgress copyWith({
    OtaStatus? status,
    int? totalBytes,
    int? sentBytes,
    int? percent,
    String? error,
  }) {
    return OtaProgress(
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      sentBytes: sentBytes ?? this.sentBytes,
      percent: percent ?? this.percent,
      error: error ?? this.error,
    );
  }
}

/// BLE OTA 升级服务
class OtaService {
  static const String _otaDataUuid = '8c224e70-1b0a-4f66-b4c3-16e4c2e70392';
  static const String _otaCtrlUuid = '8c224e70-1b0a-4f66-b4c3-16e4c2e70393';
  static const String _serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

  /// 最大分区大小 (与 ESP32 分区表一致)
  static const int maxFirmwareSize = 0x1F0000; // 1.875MB

  /// 每包数据大小 (略小于 MTU, 留安全余量)
  static const int chunkSize = 500;

  /// 等待设备响应的超时时间
  static const Duration responseTimeout = Duration(seconds: 10);

  /// 进度流控制器
  final _progressCtrl = StreamController<OtaProgress>.broadcast();
  Stream<OtaProgress> get progressStream => _progressCtrl.stream;

  OtaProgress _progress = const OtaProgress();
  bool _abortRequested = false;

  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _ctrlChar;
  StreamSubscription? _notifySub;

  /// 校验固件文件有效性
  static String? validateFirmware(Uint8List data) {
    if (data.isEmpty) return '固件文件为空';
    if (data.length < 8) return '固件文件太小';
    if (data[0] != 0xE9) return '不是有效的 ESP32 固件文件';
    if (data.length > maxFirmwareSize) {
      final sizeMB = (data.length / 1024 / 1024).toStringAsFixed(2);
      return '固件大小 ${sizeMB}MB 超出分区容量限制';
    }
    return null; // null 表示校验通过
  }

  /// 执行 OTA 升级
  ///
  /// [device] - 已连接的 BLE 设备
  /// [firmware] - 固件二进制数据
  Future<bool> performOta(BluetoothDevice device, Uint8List firmware) async {
    _abortRequested = false;

    try {
      // 1. 查找 OTA 特征
      _updateProgress(OtaStatus.preparing);
      await _discoverCharacteristics(device);

      // 2. 请求最大 MTU
      await device.requestMtu(512);
      await Future.delayed(const Duration(milliseconds: 300));

      // 3. 订阅 OTA 控制特征通知
      await _ctrlChar!.setNotifyValue(true);

      // 4. 发送开始指令
      final beginCmd = 'OTA:BEGIN:${firmware.length}';
      await _ctrlChar!.write(
        Uint8List.fromList(beginCmd.codeUnits),
        withoutResponse: false,
      );

      // 5. 等待 READY 响应
      final readyResp = await _waitForNotification(timeout: responseTimeout);
      if (readyResp != 'OTA:READY') {
        throw OtaException('设备拒绝升级: $readyResp');
      }

      // 6. 分包发送固件数据
      _updateProgress(OtaStatus.uploading, totalBytes: firmware.length);
      await _sendFirmwareData(firmware);

      if (_abortRequested) return false;

      // 7. 发送完成指令
      _updateProgress(OtaStatus.verifying);
      await _ctrlChar!.write(
        Uint8List.fromList('OTA:END'.codeUnits),
        withoutResponse: false,
      );

      // 8. 等待校验结果
      final result = await _waitForNotification(
        timeout: const Duration(seconds: 30),
      );

      if (result == 'OTA:OK') {
        _updateProgress(OtaStatus.success);
        return true;
      } else {
        throw OtaException('校验失败: $result');
      }
    } on OtaException catch (e) {
      _updateProgress(OtaStatus.failed, error: e.message);
      return false;
    } catch (e) {
      _updateProgress(OtaStatus.failed, error: '升级异常: $e');
      return false;
    } finally {
      _notifySub?.cancel();
      _notifySub = null;
    }
  }

  /// 中止 OTA
  Future<void> abort() async {
    _abortRequested = true;
    if (_ctrlChar != null) {
      try {
        await _ctrlChar!.write(
          Uint8List.fromList('OTA:ABORT'.codeUnits),
          withoutResponse: false,
        );
      } catch (_) {}
    }
    _updateProgress(OtaStatus.aborted);
  }

  /// 发现 OTA 相关 BLE 特征
  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothService? targetService;

    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase().contains(
          _serviceUuid.toLowerCase())) {
        targetService = svc;
        break;
      }
    }

    if (targetService == null) {
      throw OtaException('未找到 BLE 服务');
    }

    for (final char in targetService.characteristics) {
      final uuid = char.uuid.toString().toLowerCase();
      if (uuid.contains(_otaDataUuid.toLowerCase())) {
        _dataChar = char;
      } else if (uuid.contains(_otaCtrlUuid.toLowerCase())) {
        _ctrlChar = char;
      }
    }

    if (_dataChar == null || _ctrlChar == null) {
      throw OtaException('设备不支持 OTA 升级 (未找到 OTA 特征)');
    }
  }

  /// 分包发送固件数据
  Future<void> _sendFirmwareData(Uint8List firmware) async {
    int offset = 0;
    final total = firmware.length;

    while (offset < total) {
      if (_abortRequested) return;

      final end = (offset + chunkSize).clamp(0, total);
      final chunk = firmware.sublist(offset, end);

      // Write Without Response 以获得最高速度
      await _dataChar!.write(chunk, withoutResponse: true);

      offset = end;
      final pct = (offset * 100 ~/ total).clamp(0, 100);

      _updateProgress(
        OtaStatus.uploading,
        totalBytes: total,
        sentBytes: offset,
        percent: pct,
      );

      // 每发16包 yield 一次, 避免阻塞 UI
      if ((offset ~/ chunkSize) % 16 == 0) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
  }

  /// 等待 OTA 控制特征的通知
  Future<String> _waitForNotification({
    required Duration timeout,
  }) async {
    final completer = Completer<String>();

    _notifySub?.cancel();
    _notifySub = _ctrlChar!.onValueReceived.listen((value) {
      final str = String.fromCharCodes(value).trim();
      if (str.startsWith('OTA:PROGRESS:')) {
        // 进度通知 — 更新 UI 但不完成 completer
        final pct = int.tryParse(str.substring(13)) ?? 0;
        _updateProgress(OtaStatus.uploading, percent: pct);
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(str);
      }
    });

    // 超时处理
    return completer.future.timeout(timeout, onTimeout: () {
      throw OtaException('等待设备响应超时');
    });
  }

  /// 更新进度
  void _updateProgress(OtaStatus status, {
    int? totalBytes,
    int? sentBytes,
    int? percent,
    String? error,
  }) {
    _progress = _progress.copyWith(
      status: status,
      totalBytes: totalBytes,
      sentBytes: sentBytes,
      percent: percent,
      error: error,
    );
    _progressCtrl.add(_progress);
  }

  /// 释放资源
  void dispose() {
    _notifySub?.cancel();
    _progressCtrl.close();
  }
}

/// OTA 异常
class OtaException implements Exception {
  final String message;
  OtaException(this.message);

  @override
  String toString() => 'OtaException: $message';
}
```

### 4.3 新增 `lib/providers/ota_provider.dart`

```dart
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ota_service.dart';

/// OTA 服务 Provider
final otaServiceProvider = Provider<OtaService>((ref) {
  final svc = OtaService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

/// OTA 进度流 Provider
final otaProgressProvider = StreamProvider<OtaProgress>((ref) {
  return ref.watch(otaServiceProvider).progressStream;
});
```

### 4.4 新增 `lib/widgets/ota_update_sheet.dart`

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/train_theme.dart';
import '../services/ota_service.dart';
import '../providers/ota_provider.dart';
import '../providers/train_provider.dart';

/// OTA 升级面板
class OtaUpdateSheet extends ConsumerStatefulWidget {
  const OtaUpdateSheet({super.key});

  @override
  ConsumerState<OtaUpdateSheet> createState() => _OtaUpdateSheetState();
}

class _OtaUpdateSheetState extends ConsumerState<OtaUpdateSheet> {
  Uint8List? _firmware;
  String? _fileName;
  String? _fileError;
  bool _isRunning = false;

  @override
  Widget build(BuildContext context) {
    final otaProgress = ref.watch(otaProgressProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Row(
            children: [
              Icon(Icons.system_update, color: TrainTheme.glowCyan, size: 24),
              const SizedBox(width: 10),
              Text(
                '固件升级',
                style: TrainTheme.rajdhaniStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (!_isRunning)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 当前版本
          _infoRow('当前版本',
              ref.watch(trainStateProvider).firmwareVersion.isNotEmpty
                  ? ref.watch(trainStateProvider).firmwareVersion
                  : '未知'),
          const SizedBox(height: 12),

          // 选择固件文件
          if (!_isRunning) ...[
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: Text(
                _fileName ?? '选择固件文件 (.bin)',
                style: TrainTheme.rajdhaniStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: TrainTheme.glowCyan,
                side: BorderSide(color: TrainTheme.glowCyan.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            if (_fileError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _fileError!,
                  style: TrainTheme.rajdhaniStyle(
                    fontSize: 12,
                    color: TrainTheme.glowRed,
                  ),
                ),
              ),
            if (_firmware != null && _fileError == null) ...[
              const SizedBox(height: 8),
              _infoRow('文件大小',
                  '${(_firmware!.length / 1024).toStringAsFixed(1)} KB'),
            ],
            const SizedBox(height: 16),
          ],

          // 升级进度
          otaProgress.when(
            data: (p) => _buildProgress(p),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),

          // 操作按钮
          if (!_isRunning && _firmware != null && _fileError == null)
            ElevatedButton.icon(
              onPressed: _startOta,
              icon: const Icon(Icons.upload),
              label: Text(
                '开始升级',
                style: TrainTheme.rajdhaniStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: TrainTheme.glowCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),

          if (_isRunning)
            OutlinedButton.icon(
              onPressed: _abortOta,
              icon: const Icon(Icons.cancel),
              label: Text(
                '中止升级',
                style: TrainTheme.rajdhaniStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: TrainTheme.glowRed,
                side: BorderSide(color: TrainTheme.glowRed.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

          const SizedBox(height: 8),
          // 安全提示
          Text(
            '⚠️ 升级期间请勿关闭 App 或断开蓝牙连接',
            style: TrainTheme.rajdhaniStyle(
              fontSize: 11,
              color: TrainTheme.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TrainTheme.rajdhaniStyle(fontSize: 13, color: TrainTheme.textDim),
        ),
        Text(
          value,
          style: TrainTheme.orbitronStyle(fontSize: 12, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildProgress(OtaProgress p) {
    if (p.status == OtaStatus.idle) return const SizedBox();

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (p.status) {
      case OtaStatus.preparing:
        statusColor = TrainTheme.glowCyan;
        statusText = '准备中...';
        statusIcon = Icons.hourglass_top;
        break;
      case OtaStatus.uploading:
        statusColor = TrainTheme.glowCyan;
        statusText = '上传中 ${p.percent}%';
        statusIcon = Icons.upload;
        break;
      case OtaStatus.verifying:
        statusColor = TrainTheme.glowYellow;
        statusText = '校验中...';
        statusIcon = Icons.verified;
        break;
      case OtaStatus.success:
        statusColor = TrainTheme.glowGreen;
        statusText = '升级成功！设备重启中...';
        statusIcon = Icons.check_circle;
        break;
      case OtaStatus.failed:
        statusColor = TrainTheme.glowRed;
        statusText = '升级失败: ${p.error ?? "未知错误"}';
        statusIcon = Icons.error;
        break;
      case OtaStatus.aborted:
        statusColor = TrainTheme.glowOrange;
        statusText = '已中止';
        statusIcon = Icons.cancel;
        break;
      default:
        return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TrainTheme.rajdhaniStyle(
                    fontSize: 14,
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (p.status == OtaStatus.uploading ||
              p.status == OtaStatus.verifying) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p.status == OtaStatus.verifying
                    ? null
                    : p.percent / 100.0,
                backgroundColor: Colors.white.withOpacity(0.08),
                color: statusColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            if (p.status == OtaStatus.uploading)
              Text(
                '${(p.sentBytes / 1024).toStringAsFixed(0)} / ${(p.totalBytes / 1024).toStringAsFixed(0)} KB',
                style: TrainTheme.orbitronStyle(
                  fontSize: 10,
                  color: TrainTheme.textDim,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 选择固件文件
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();

      final error = OtaService.validateFirmware(bytes);

      setState(() {
        _firmware = bytes;
        _fileName = file.name;
        _fileError = error;
      });
    } catch (e) {
      setState(() {
        _fileError = '读取文件失败: $e';
      });
    }
  }

  /// 开始 OTA 升级
  Future<void> _startOta() async {
    if (_firmware == null) return;

    // 检查是否停车
    final ts = ref.read(trainStateProvider);
    if (ts.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 请先停车再升级',
              style: TrainTheme.rajdhaniStyle(fontSize: 14)),
          backgroundColor: TrainTheme.glowRed.withOpacity(0.8),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isRunning = true);

    final ble = ref.read(bleServiceProvider);
    final device = ble.connectedDevice;
    if (device == null) {
      setState(() => _isRunning = false);
      return;
    }

    final ota = ref.read(otaServiceProvider);
    final success = await ota.performOta(device, _firmware!);

    if (mounted) {
      setState(() => _isRunning = false);
      if (success) {
        // 升级成功，设备会重启，等待重连
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.pop(context);
        });
      }
    }
  }

  /// 中止 OTA
  Future<void> _abortOta() async {
    await ref.read(otaServiceProvider).abort();
    if (mounted) {
      setState(() => _isRunning = false);
    }
  }
}
```

### 4.5 `pubspec.yaml` 添加依赖

```yaml
dependencies:
  file_picker: ^8.0.0  # 文件选择器
```

---

## 五、升级流程图

```
Flutter App                      BLE                        ESP32
    │                             │                           │
 [用户选择 .bin 文件]             │                           │
 [App 校验: 0xE9 魔数 + 大小]     │                           │
    │                             │                           │
 [用户点击"开始升级"]             │                           │
    ├─ requestMtu(512) ──────────→│                           │
    │                             │                           │
    ├─ 写 OTA_CTRL:               │                           │
    │  "OTA:BEGIN:1433600" ──────→│──────────────────────────→│
    │                             │                           ├─ 校验大小 ✓
    │                             │                           ├─ 校验停车 ✓
    │                             │                           ├─ 关闭电机/灯/音
    │                             │                           ├─ Update.begin()
    │                             │←──────────────────────────┤
    │  ← 通知: "OTA:READY"        │                           │
    │                             │                           │
 [开始分包发送]                   │                           │
    ├─ 写 OTA_DATA: 500B ────────→│──────────────────────────→│
    ├─ 写 OTA_DATA: 500B ────────→│─────────────────────────→ │ Update.write()
    ├─ 写 OTA_DATA: 500B ────────→│─────────────────────────→ │
    │  ...                        │                           │
    │                             │←──────────────────────────┤
    │  ← 通知: "OTA:PROGRESS:25"  │                           │
    │  [更新进度条]               │                           │
    │  ...                        │                           │
    │  ← 通知: "OTA:PROGRESS:50"  │                           │
    │  ...                        │                           │
    │  ← 通知: "OTA:PROGRESS:100" │                           │
    │                             │                           │
 [发送完毕]                       │                           │
    ├─ 写 OTA_CTRL:               │                           │
    │  "OTA:END" ────────────────→│──────────────────────────→│
    │                             │                           ├─ Update.end(true)
    │                             │                           ├─ MD5 校验 ✓
    │                             │←──────────────────────────┤
    │  ← 通知: "OTA:OK"           │                           │
    │                             │                           │
 [显示"升级成功"]                 │                 2秒后     │
    │                             │                           ├─ ESP.restart()
    │                             │                           │
 [BLE 断连]                       │                           │
    │                             │           新固件启动      │
 [等待重新发现]                   │                           ├─ selfTest() ✓
 [自动重连]                       │                           ├─ ota_mark_valid()
    │                             │                           ├─ BLE 广播
    ├─ 重新连接 ─────────────────→│──────────────────────────→│
    │                             │                           │
 [读取新版本号]                   │                           │
 [显示升级完成 ✓]                 │                           │
```

---

## 六、安全机制总结

```
┌──────────────────────────────────────────────────────────────┐
│  OTA 安全保障                                                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ① 传输前 (App 端)                                           │
│     ├─ 检查文件魔数 0xE9                                     │
│     ├─ 检查文件大小 ≤ 1.875MB                                │
│     └─ 检查列车已停车                                        │
│                                                              │
│  ② 传输前 (ESP32 端)                                         │
│     ├─ 校验固件大小 ≤ OTA_PARTITION_SIZE                     │
│     ├─ 校验电机已停止 (actualPWM == 0)                       │
│     └─ 强制关闭电机/灯光/音效                                │
│                                                              │
│  ③ 传输中                                                    │
│     ├─ OTA 期间 loop() 冻结所有控制逻辑                      │
│     ├─ 每次 loop 强制 applyMotorPWM(0, 0)                    │
│     ├─ 看门狗持续喂狗 (不会误重启)                           │
│     ├─ 60 秒无数据 → 自动中止                                │
│     ├─ BLE 断连 → 自动中止                                   │
│     └─ App 可随时发送 OTA:ABORT 中止                         │
│                                                              │
│  ④ 传输后                                                    │
│     ├─ Update.end(true) 自动 MD5 校验                        │
│     └─ 校验失败 → 不切换分区, 不重启, 返回错误               │
│                                                              │
│  ⑤ 重启后                                                    │
│     ├─ 新固件执行完整 selfTest()                             │
│     ├─ 自检通过 → esp_ota_mark_app_valid()                   │
│     ├─ 自检失败/崩溃 → 看门狗重启 → 自动回滚旧固件           │
│     └─ 回滚后旧固件正常运行, 不会变砖                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 七、完整文件变动清单

| 文件 | 类型 | 说明 |
|------|------|------|
| **ESP32 端** | | |
| `partitions_ota.csv` | 新增 | OTA 双分区表, 每分区 1.875MB |
| `platformio.ini` | 修改 | `board_build.partitions = partitions_ota.csv` |
| 主固件 `.ino` | 修改 | 新增 `#include <Update.h>` 和 `#include <esp_ota_ops.h>` |
| | | 新增 OTA UUID / 宏定义 / 全局变量 |
| | | 新增 `OtaCtrlCB` 控制回调类 |
| | | 新增 `OtaDataCB` 数据回调类 |
| | | `setup()` 注册 OTA 特征 + 启动确认 |
| | | `setup()` 中 `createService` 增加 handle 数量为 30 |
| | | `loop()` 开头添加 OTA 冻结逻辑 |
| | | BLE 断连处理添加 OTA 中止 |
| **Flutter 端** | | |
| `lib/services/ota_service.dart` | 新增 | OTA 升级核心逻辑 |
| `lib/providers/ota_provider.dart` | 新增 | OTA Riverpod Provider |
| `lib/widgets/ota_update_sheet.dart` | 新增 | OTA 升级 UI 面板 |
| `pubspec.yaml` | 修改 | 添加 `file_picker` 依赖 |

**不影响现有功能**：所有 OTA 代码仅在用户主动触发升级时激活，正常运行时零开销。