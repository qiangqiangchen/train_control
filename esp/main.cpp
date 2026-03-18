/**
 * ============================================================================
 * 🚂 BLE 遥控火车 — 终极固件 (含双机重联) v1.1 优化版
 * ============================================================================
 *
 * v1.1 优化内容:
 *   - 编译期调试开关，发布版零 Serial 开销
 *   - 统一灯光/音效更新入口，消除重复代码
 *   - kickstart 结束后平滑坡道过渡（而非跳变到目标值）
 *   - 状态字符串构建优化，防缓冲区溢出
 *   - ESP-NOW 发送结果检测
 *   - 电池低电量警告 (10%)
 *   - BLE 重连时立即推送状态
 *   - ADC 多次采样取中值，消除尖刺噪声
 *   - loop() 中音效更新仅在 PWM 变化时执行
 *   - 解联增加重试机制
 *
 * 硬件: ESP32-C3 Super Mini + DRV8833 + 5×2N7002
 * 供电: 3×AA (4.5V)
 * ============================================================================
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_now.h>
#include <WiFi.h>
#include <esp_wifi.h>

// ============================================================================
// 调试开关 — 发布时设为 0，消除所有 Serial 字符串占用
// ============================================================================
#define DEBUG_ENABLED  1

#if DEBUG_ENABLED
  #define DBG_INIT(baud)    Serial.begin(baud)
  #define DBG(msg)          Serial.println(msg)
  #define DBGF(fmt, ...)    Serial.printf(fmt "\n", ##__VA_ARGS__)
#else
  #define DBG_INIT(baud)    ((void)0)
  #define DBG(msg)          ((void)0)
  #define DBGF(fmt, ...)    ((void)0)
#endif

// ============================================================================
// 固件版本
// ============================================================================
#define FIRMWARE_VERSION  "1.1.0"

// ============================================================================
// 引脚定义
// ============================================================================
#define BATT_ADC     0
#define MOTOR_IN1    2
#define MOTOR_IN2    3
#define LED_A_WHITE  4
#define LED_B_WHITE  5
#define LED_A_RED    6
#define LED_B_RED    7
#define SOUND_POWER  8

// ============================================================================
// 电机参数
// ============================================================================
#define MIN_PWM         160
#define MAX_PWM         255
#define THROTTLE_STEPS  8
#define KICK_PWM        255
#define KICK_TIME       80    // ms
#define RAMP_STEP       4
#define RAMP_INTERVAL   20   // ms

// ============================================================================
// 演示模式
// ============================================================================
#define DEMO_WAIT_TIME  20000
#define DEMO_LEVEL      5
#define DEMO_DIR        1

// ============================================================================
// 电池
// ============================================================================
#define BATT_SAMPLE_INTERVAL  5000
#define BATT_AVG_COUNT        10
#define BATT_MIN_MV           3000
#define BATT_MAX_MV           4500
#define BATT_LOW_PCT          10     // 低电量警告阈值

// ============================================================================
// ESP-NOW
// ============================================================================
#define ESPNOW_CMD_INTERVAL    100
#define ESPNOW_STATUS_INTERVAL 200
#define ESPNOW_INVITE_INTERVAL 500
#define ESPNOW_INVITE_TIMEOUT  30000
#define SLAVE_CMD_TIMEOUT      300
#define MASTER_STATUS_WARN     1000
#define MASTER_STATUS_TIMEOUT  3000
#define UNCOUPLE_RETRY_COUNT   3      // 解联包重发次数
#define UNCOUPLE_RETRY_INTERVAL 200   // 解联包重发间隔 ms

// ============================================================================
// PWM 通道
// ============================================================================
#define PWM_CH_IN1   0
#define PWM_CH_IN2   1
#define PWM_FREQ     1000
#define PWM_RES      8

// ============================================================================
// BLE UUID
// ============================================================================
#define SERVICE_UUID       "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_CTRL_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_STATUS_UUID   "8c224e70-1b0a-4f66-b4c3-16e4c2e70391"
#define CHAR_VERSION_UUID  "8c224e70-1b0a-4f66-b4c3-16e4c2e70394"

// ============================================================================
// ESP-NOW 包类型
// ============================================================================
#define PKT_INVITE       0x01
#define PKT_ACCEPT       0x02
#define PKT_CMD          0x10
#define PKT_STATUS       0x11
#define PKT_UNCOUPLE     0x20
#define PKT_UNCOUPLE_ACK 0x21

// ============================================================================
// ESP-NOW 数据结构
// ============================================================================
#pragma pack(push, 1)

struct InvitePayload {
  uint8_t masterMAC[6];
  uint8_t masterTailEnd;   // 'A' / 'B'
};

struct AcceptPayload {
  uint8_t slaveMAC[6];
  uint8_t slaveCoupleEnd;  // 'A' / 'B'
};

struct CmdPayload {
  uint8_t  targetDir;      // 0=停 1=FWD 2=REV (已映射)
  uint8_t  targetPWM;      // 0~255 (已含系数)
  uint8_t  lightEndA;      // 0=灭 1=白灯位 2=红灯
  uint8_t  lightEndB;
  uint8_t  headlightOn;
  uint8_t  soundEnabled;
  uint8_t  seqNum;
};

struct StatusPayload {
  uint8_t  actualPWM;
  uint8_t  batteryPct;
  uint16_t batteryMV;
};

#pragma pack(pop)

// ============================================================================
// 枚举
// ============================================================================
enum RoleState : uint8_t {
  ROLE_STANDALONE,
  ROLE_INVITING,
  ROLE_INVITED,
  ROLE_MASTER,
  ROLE_SLAVE
};

enum MotorState : uint8_t {
  STATE_IDLE,
  STATE_KICK,
  STATE_RAMPING,
  STATE_RUNNING
};

enum DemoState : uint8_t {
  DEMO_WAITING,
  DEMO_RUNNING,
  DEMO_EXITING,
  DEMO_OFF
};

// ============================================================================
// 全局状态
// ============================================================================

// 驾驶端 & 灯光
bool     cabAtEndA    = true;
bool     headlightOn  = false;

// 音效
bool     soundEnabled = false;

// 电机
uint8_t  targetDir    = 0;    // 0=停 1=FWD 2=REV
uint8_t  actualDir    = 0;
uint8_t  targetLevel  = 0;
uint16_t targetPWM    = 0;
uint16_t actualPWM    = 0;
uint16_t prevActualPWM = 0;   // 上一轮的 actualPWM (用于变化检测)

// 状态机
MotorState motorState = STATE_IDLE;
unsigned long kickStartTime = 0;
unsigned long lastRampTime  = 0;

// 演示
DemoState demoState = DEMO_WAITING;
unsigned long bootTime = 0;

// 电池
uint16_t batteryMV   = 4500;
uint8_t  batteryPct  = 100;
uint16_t battSamples[BATT_AVG_COUNT];
uint8_t  battSampleIdx     = 0;
bool     battSamplesFilled = false;
unsigned long lastBattTime  = 0;

// 重联
RoleState roleState = ROLE_STANDALONE;
uint8_t  peerMAC[6]  = {};
uint8_t  slaveCoupleEnd       = 'A';
uint8_t  masterCoupleEndStored = 'B';
float    speedCoeff  = 1.00f;
uint8_t  cmdSeqNum   = 0;

// SLAVE 侧缓存
uint8_t  slaveCmdDir       = 0;
uint8_t  slaveCmdPWM       = 0;

// MASTER 侧缓存
uint8_t  slaveActualPWM    = 0;
uint8_t  slaveBatteryPct   = 0;
uint16_t slaveBatteryMV    = 0;
bool     slaveStatusValid  = false;
bool     slaveStatusWarn   = false;

// 邀请
unsigned long inviteStartTime = 0;
unsigned long lastInviteTime  = 0;
uint8_t  inviterMAC[6] = {};

// 解联重试
uint8_t  uncoupleRetryLeft    = 0;
unsigned long lastUncoupleTime = 0;

// 超时计时
unsigned long lastSlaveCmd       = 0;
unsigned long lastSlaveStatus    = 0;
unsigned long lastCmdSendTime    = 0;
unsigned long lastStatusSendTime = 0;
unsigned long lastBleStatusTime  = 0;

// BLE
BLEServer*         pServer      = nullptr;
BLECharacteristic* pCtrlChar    = nullptr;
BLECharacteristic* pStatusChar  = nullptr;
bool deviceConnected = false;
bool wasConnected    = false;

// 自身 MAC
uint8_t myMAC[6];

// ============================================================================
// 工具函数
// ============================================================================

/** 档位 → PWM (0→0, 1→160, 8→255) */
uint16_t levelToPWM(uint8_t lv) {
  if (lv == 0)              return 0;
  if (lv >= THROTTLE_STEPS) return MAX_PWM;
  return MIN_PWM + (uint16_t)(lv - 1) * (MAX_PWM - MIN_PWM) / (THROTTLE_STEPS - 1);
}

/** PWM → 近似档位 (用于补机从 PWM 反推档位显示) */
uint8_t pwmToLevel(uint16_t pwm) {
  if (pwm == 0) return 0;
  for (uint8_t l = 1; l <= THROTTLE_STEPS; l++) {
    if (levelToPWM(l) >= pwm) return l;
  }
  return THROTTLE_STEPS;
}

/** 钳位函数 */
uint16_t clampPWM(uint16_t pwm) {
  if (pwm > MAX_PWM) return MAX_PWM;
  if (pwm > 0 && pwm < MIN_PWM) return MIN_PWM;
  return pwm;
}

/** 完全停稳判断 */
bool isFullyStopped() {
  return targetPWM == 0 && actualPWM == 0;
}

/** 演示模式活跃判断 */
bool isDemoActive() {
  return demoState == DEMO_RUNNING || demoState == DEMO_EXITING;
}

// ============================================================================
// 电机输出
// ============================================================================

/**
 * 将 PWM 值写入 DRV8833
 * 方向根据 cabAtEndA 自动翻转物理转向
 */
void applyMotorPWM(uint8_t dir, uint16_t pwm) {
  if (pwm == 0 || dir == 0) {
    ledcWrite(PWM_CH_IN1, 0);
    ledcWrite(PWM_CH_IN2, 0);
    return;
  }
  // 判断物理正反
  bool rev = (dir == 2);
  if (!cabAtEndA) rev = !rev;

  ledcWrite(PWM_CH_IN1, rev ? 0 : pwm);
  ledcWrite(PWM_CH_IN2, rev ? pwm : 0);
}

// ============================================================================
// 灯光
// ============================================================================

/** 设置单端灯光 (内联减少调用开销) */
static inline void setEndLight(uint8_t pinW, uint8_t pinR,
                               uint8_t mode, bool hlOn) {
  // mode: 0=全灭  1=白灯位(受hlOn控)  2=红灯
  switch (mode) {
    case 0:  digitalWrite(pinW, LOW);             digitalWrite(pinR, LOW);  break;
    case 1:  digitalWrite(pinW, hlOn ? HIGH:LOW); digitalWrite(pinR, LOW);  break;
    case 2:  digitalWrite(pinW, LOW);             digitalWrite(pinR, HIGH); break;
    default: digitalWrite(pinW, LOW);             digitalWrite(pinR, LOW);  break;
  }
}

/**
 * 统一灯光刷新入口
 * 根据角色计算本车 A/B 端各自的灯光模式后一次性写入
 *
 * 返回值:  同时通过指针输出补机灯光参数 (仅 MASTER 有意义)
 */
void updateLights(uint8_t* outSlaveLightA  = nullptr,
                  uint8_t* outSlaveLightB  = nullptr,
                  bool*    outSlaveHL      = nullptr)
{
  // --- 本车 A/B 端的灯光模式 ---
  uint8_t modeA = 0, modeB = 0;

  if (roleState == ROLE_MASTER) {
    // 本务机: 驾驶端=车头(白灯位), 连接端=全灭
    if (cabAtEndA) { modeA = 1; modeB = 0; }
    else           { modeA = 0; modeB = 1; }
  }
  else if (roleState == ROLE_SLAVE) {
    // SLAVE 灯光完全由 CMD 包直接设置，这里不处理
    return;
  }
  else {
    // 独立 / INVITING / INVITED
    if (cabAtEndA) { modeA = 1; modeB = 2; }   // A=车头  B=车尾红灯
    else           { modeA = 2; modeB = 1; }   // A=车尾红灯  B=车头
  }

  setEndLight(LED_A_WHITE, LED_A_RED, modeA, headlightOn);
  setEndLight(LED_B_WHITE, LED_B_RED, modeB, headlightOn);

  // --- 计算补机灯光 (仅 MASTER 需要) ---
  if (roleState == ROLE_MASTER && outSlaveLightA && outSlaveLightB && outSlaveHL) {
    uint8_t slaveFar  = (slaveCoupleEnd == 'A') ? 'B' : 'A';
    bool cabAtCouple  = (cabAtEndA  && masterCoupleEndStored == 'A') ||
                        (!cabAtEndA && masterCoupleEndStored == 'B');

    uint8_t nearMode = 0;  // 连接端始终全灭
    uint8_t farMode;
    bool    sHL;

    if (!cabAtCouple) {
      farMode = 2;  // 补机远端 = 整列车尾 → 红灯
      sHL = false;
    } else {
      farMode = 1;  // 补机远端 = 整列车头 → 白灯位
      sHL = headlightOn;
    }

    if (slaveCoupleEnd == 'A') {
      *outSlaveLightA = nearMode;
      *outSlaveLightB = farMode;
    } else {
      *outSlaveLightA = farMode;
      *outSlaveLightB = nearMode;
    }
    *outSlaveHL = sHL;
  }
}

// ============================================================================
// 音效
// ============================================================================

/** 更新 Q5 输出 (仅在 PWM 发生变化时需要调用) */
void updateSound() {
  digitalWrite(SOUND_POWER, (soundEnabled && actualPWM > 0) ? HIGH : LOW);
}

// ============================================================================
// 电池
// ============================================================================

/**
 * ADC 中值采样：连续读5次取中值，消除尖刺噪声
 * 比简单的单次读取更稳定
 */
static uint16_t adcReadMedian(uint8_t pin, uint8_t n = 5) {
  uint16_t buf[7];  // 最多7次
  if (n > 7) n = 7;
  for (uint8_t i = 0; i < n; i++) buf[i] = analogRead(pin);
  // 简单冒泡排序 (n很小, 开销忽略)
  for (uint8_t i = 0; i < n - 1; i++)
    for (uint8_t j = i + 1; j < n; j++)
      if (buf[j] < buf[i]) { uint16_t t = buf[i]; buf[i] = buf[j]; buf[j] = t; }
  return buf[n / 2];
}

void sampleBattery() {
  uint16_t raw = adcReadMedian(BATT_ADC, 5);
  uint32_t mv  = (uint32_t)raw * 5000 / 4095;

  battSamples[battSampleIdx] = (uint16_t)mv;
  battSampleIdx = (battSampleIdx + 1) % BATT_AVG_COUNT;
  if (battSampleIdx == 0) battSamplesFilled = true;

  uint8_t  cnt = battSamplesFilled ? BATT_AVG_COUNT : (battSampleIdx ? battSampleIdx : 1);
  uint32_t sum = 0;
  for (uint8_t i = 0; i < cnt; i++) sum += battSamples[i];
  batteryMV = sum / cnt;

  if      (batteryMV <= BATT_MIN_MV) batteryPct = 0;
  else if (batteryMV >= BATT_MAX_MV) batteryPct = 100;
  else batteryPct = (uint8_t)((uint32_t)(batteryMV - BATT_MIN_MV) * 100
                              / (BATT_MAX_MV - BATT_MIN_MV));
}

// ============================================================================
// ESP-NOW 发送 (带错误检测)
// ============================================================================

bool espnowSend(const uint8_t* dest, const void* data, size_t len) {
  esp_err_t r = esp_now_send(dest, (const uint8_t*)data, len);
  if (r != ESP_OK) {
    DBGF("ESP-NOW send fail: %d", r);
    return false;
  }
  return true;
}

void sendInviteBroadcast() {
  uint8_t buf[1 + sizeof(InvitePayload)];
  buf[0] = PKT_INVITE;
  InvitePayload* p = (InvitePayload*)(buf + 1);
  memcpy(p->masterMAC, myMAC, 6);
  p->masterTailEnd = cabAtEndA ? 'B' : 'A';
  uint8_t bc[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
  espnowSend(bc, buf, sizeof(buf));
}

void sendAcceptPkt(const uint8_t* masterMAC, uint8_t coupleEnd) {
  uint8_t buf[1 + sizeof(AcceptPayload)];
  buf[0] = PKT_ACCEPT;
  AcceptPayload* p = (AcceptPayload*)(buf + 1);
  memcpy(p->slaveMAC, myMAC, 6);
  p->slaveCoupleEnd = coupleEnd;
  espnowSend(masterMAC, buf, sizeof(buf));
}

void sendCmdToSlave() {
  if (roleState != ROLE_MASTER) return;

  // 方向映射
  uint8_t sDir = targetDir;
  if (slaveCoupleEnd == 'B' && sDir != 0)
    sDir = (sDir == 1) ? 2 : 1;

  // PWM × 系数
  uint16_t sPWM = (targetPWM == 0) ? 0
                : clampPWM((uint16_t)(targetPWM * speedCoeff + 0.5f));

  // 灯光
  uint8_t lA = 0, lB = 0;
  bool sHL = false;
  updateLights(&lA, &lB, &sHL);   // 同时刷新本车灯光

  uint8_t buf[1 + sizeof(CmdPayload)];
  buf[0] = PKT_CMD;
  CmdPayload* p = (CmdPayload*)(buf + 1);
  p->targetDir    = sDir;
  p->targetPWM    = (uint8_t)sPWM;
  p->lightEndA    = lA;
  p->lightEndB    = lB;
  p->headlightOn  = sHL ? 1 : 0;
  p->soundEnabled = soundEnabled ? 1 : 0;
  p->seqNum       = cmdSeqNum++;

  espnowSend(peerMAC, buf, sizeof(buf));
}

void sendStatusToMaster() {
  if (roleState != ROLE_SLAVE) return;
  uint8_t buf[1 + sizeof(StatusPayload)];
  buf[0] = PKT_STATUS;
  StatusPayload* p = (StatusPayload*)(buf + 1);
  p->actualPWM  = (uint8_t)actualPWM;
  p->batteryPct = batteryPct;
  p->batteryMV  = batteryMV;
  espnowSend(peerMAC, buf, sizeof(buf));
}

void sendUncouplePkt() {
  uint8_t buf[1] = { PKT_UNCOUPLE };
  espnowSend(peerMAC, buf, 1);
}

void sendUncoupleAckPkt() {
  uint8_t buf[1] = { PKT_UNCOUPLE_ACK };
  espnowSend(peerMAC, buf, 1);
}

// ============================================================================
// 重联管理
// ============================================================================

void addEspNowPeer(const uint8_t* mac) {
  if (esp_now_is_peer_exist(mac)) return;
  esp_now_peer_info_t pi = {};
  memcpy(pi.peer_addr, mac, 6);
  pi.channel = 0;
  pi.encrypt = false;
  esp_now_add_peer(&pi);
}

void enterMaster(const uint8_t* slaveMAC, uint8_t slvEnd) {
  roleState = ROLE_MASTER;
  memcpy(peerMAC, slaveMAC, 6);
  slaveCoupleEnd = slvEnd;
  masterCoupleEndStored = cabAtEndA ? 'B' : 'A';
  speedCoeff = 1.00f;
  slaveActualPWM = slaveBatteryPct = 0;
  slaveBatteryMV = 0;
  slaveStatusValid = slaveStatusWarn = false;
  lastSlaveStatus = lastCmdSendTime = millis();
  cmdSeqNum = 0;
  uncoupleRetryLeft = 0;
  addEspNowPeer(peerMAC);
  updateLights();
  DBG("→ MASTER");
}

void enterSlave(const uint8_t* masterMAC) {
  roleState = ROLE_SLAVE;
  memcpy(peerMAC, masterMAC, 6);
  lastSlaveCmd = lastStatusSendTime = millis();
  addEspNowPeer(peerMAC);
  DBG("→ SLAVE");
}

void exitCoupling() {
  if (roleState == ROLE_MASTER || roleState == ROLE_SLAVE)
    esp_now_del_peer(peerMAC);
  roleState = ROLE_STANDALONE;
  memset(peerMAC, 0, 6);
  slaveStatusValid = slaveStatusWarn = false;
  uncoupleRetryLeft = 0;
  updateLights();
  DBG("→ STANDALONE");
}

// ============================================================================
// BLE 状态上报
// ============================================================================

/**
 * 构建并发送状态字符串
 * 使用 snprintf 逐段追加，带溢出保护
 */
void sendStatus() {
  if (!deviceConnected) return;

  char buf[220];
  int  cap = sizeof(buf);
  int  pos = 0;

  // 宏: 安全追加
  #define APPEND(fmt, ...) \
    pos += snprintf(buf + pos, cap - pos, fmt, ##__VA_ARGS__)

  bool sndOn = soundEnabled && actualPWM > 0;

  APPEND("CAB:%c HL:%s DIR:%s LV:%d APWM:%d TPWM:%d",
    cabAtEndA ? 'A' : 'B',
    headlightOn ? "ON" : "OFF",
    actualPWM == 0 ? "STOP" : (actualDir == 1 ? "FWD" : "REV"),
    targetLevel, actualPWM, targetPWM);

  APPEND(" SE:%s SND:%s DM:%s",
    soundEnabled ? "ON" : "OFF",
    sndOn ? "ON" : "OFF",
    isDemoActive() ? "ON" : "OFF");

  APPEND(" BAT:%d BATV:%d.%02d",
    batteryPct, batteryMV / 1000, (batteryMV % 1000) / 10);

  // 低电量警告标志
  if (batteryPct <= BATT_LOW_PCT) APPEND(" BLOW:1");

  // 重联字段
  switch (roleState) {
    case ROLE_STANDALONE: APPEND(" CP:OFF"); break;
    case ROLE_INVITING:   APPEND(" CP:INVITING"); break;
    case ROLE_INVITED:
      APPEND(" CP:INVITED INV:%02X:%02X:%02X:%02X:%02X:%02X",
        inviterMAC[0],inviterMAC[1],inviterMAC[2],
        inviterMAC[3],inviterMAC[4],inviterMAC[5]);
      break;
    case ROLE_MASTER:
      APPEND(" CP:MASTER SC:%c SAPWM:%d SBAT:%d SBATV:%d.%02d SK:%d.%02d",
        slaveCoupleEnd, slaveActualPWM, slaveBatteryPct,
        slaveBatteryMV/1000, (slaveBatteryMV%1000)/10,
        (int)speedCoeff, (int)(speedCoeff*100)%100);
      if (slaveStatusWarn) APPEND(" SWARN:1");
      break;
    case ROLE_SLAVE: APPEND(" CP:SLAVE"); break;
  }

  APPEND(" FW:%s", FIRMWARE_VERSION);

  #undef APPEND

  pStatusChar->setValue(buf);
  pStatusChar->notify();
}

void sendError(const char* msg) {
  if (!deviceConnected) return;
  char buf[40];
  snprintf(buf, sizeof(buf), "ERR:%s", msg);
  pStatusChar->setValue(buf);
  pStatusChar->notify();
}

// ============================================================================
// ESP-NOW 接收回调
// ============================================================================

void onEspNowRecv(const uint8_t* mac, const uint8_t* data, int len) {
  if (len < 1) return;
  uint8_t type = data[0];
  const uint8_t* pl = data + 1;

  switch (type) {

  case PKT_INVITE: {
    if (roleState != ROLE_STANDALONE && roleState != ROLE_INVITED) return;
    if (len < 1 + (int)sizeof(InvitePayload)) return;
    const InvitePayload* inv = (const InvitePayload*)pl;

    if (demoState == DEMO_RUNNING) {
      demoState    = DEMO_EXITING;
      soundEnabled = false;
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = millis(); }
      updateSound();
      memcpy(inviterMAC, inv->masterMAC, 6);
      roleState = ROLE_INVITED;
      slaveCoupleEnd = cabAtEndA ? 'A' : 'B';
      return;
    }
    memcpy(inviterMAC, inv->masterMAC, 6);
    roleState = ROLE_INVITED;
    sendStatus();
    break;
  }

  case PKT_ACCEPT: {
    if (roleState != ROLE_INVITING) return;
    if (len < 1 + (int)sizeof(AcceptPayload)) return;
    const AcceptPayload* acc = (const AcceptPayload*)pl;
    enterMaster(acc->slaveMAC, acc->slaveCoupleEnd);
    sendStatus();
    break;
  }

  case PKT_CMD: {
    if (roleState != ROLE_SLAVE) return;
    if (len < 1 + (int)sizeof(CmdPayload)) return;
    const CmdPayload* cmd = (const CmdPayload*)pl;
    lastSlaveCmd = millis();

    // 灯光 & 音效立即执行
    setEndLight(LED_A_WHITE, LED_A_RED, cmd->lightEndA, cmd->headlightOn);
    setEndLight(LED_B_WHITE, LED_B_RED, cmd->lightEndB, cmd->headlightOn);
    soundEnabled = cmd->soundEnabled;

    // 电机
    if (cmd->targetPWM == 0) {
      targetDir = targetLevel = targetPWM = 0;
    } else if (actualPWM > 0 && actualDir != 0 && actualDir != cmd->targetDir) {
      // 运行中换向 → 先停
      targetDir = targetLevel = targetPWM = 0;
    } else {
      targetDir  = cmd->targetDir;
      targetPWM  = cmd->targetPWM;
      targetLevel = pwmToLevel(cmd->targetPWM);
      if (actualPWM == 0) {
        actualDir = targetDir;
        actualPWM = KICK_PWM;
        applyMotorPWM(actualDir, actualPWM);
        kickStartTime = millis();
        motorState = STATE_KICK;
      } else {
        motorState = STATE_RAMPING;
      }
    }
    break;
  }

  case PKT_STATUS: {
    if (roleState != ROLE_MASTER) return;
    if (len < 1 + (int)sizeof(StatusPayload)) return;
    const StatusPayload* st = (const StatusPayload*)pl;
    slaveActualPWM  = st->actualPWM;
    slaveBatteryPct = st->batteryPct;
    slaveBatteryMV  = st->batteryMV;
    slaveStatusValid = true;
    slaveStatusWarn  = false;
    lastSlaveStatus  = millis();
    break;
  }

  case PKT_UNCOUPLE: {
    if (roleState != ROLE_SLAVE) return;
    sendUncoupleAckPkt();
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = millis(); }
    exitCoupling();
    sendStatus();
    break;
  }

  case PKT_UNCOUPLE_ACK: {
    if (roleState != ROLE_MASTER) return;
    uncoupleRetryLeft = 0;
    exitCoupling();
    sendStatus();
    break;
  }
  } // switch
}

void onEspNowSent(const uint8_t*, esp_now_send_status_t) {}

// ============================================================================
// BLE 回调
// ============================================================================

class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    deviceConnected = true;
    if (demoState == DEMO_WAITING) {
      demoState = DEMO_OFF;
    } else if (demoState == DEMO_RUNNING) {
      demoState    = DEMO_EXITING;
      soundEnabled = false;
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = millis(); }
      updateSound();
    }
  }
  void onDisconnect(BLEServer*) override { deviceConnected = false; }
};

/**
 * 指令解析 — 统一入口
 * 用首字符快速分发，减少 startsWith 调用
 */
class CtrlCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String v = String(pChar->getValue().c_str());
    v.trim();
    if (v.length() == 0) return;

    if (demoState == DEMO_EXITING)     { sendError("DEMO_STOPPING"); return; }
    if (roleState == ROLE_SLAVE)       { sendError("SLAVE_MODE");     return; }

    char c0 = v.charAt(0);

    // ---- L 灯光 ----
    if (c0 == 'L') {
      if      (v == "L")    headlightOn = !headlightOn;
      else if (v == "L:0")  headlightOn = false;
      else if (v == "L:1")  headlightOn = true;
      else return;
      updateLights();
      sendStatus();
      return;
    }

    // ---- M 音效 ----
    if (c0 == 'M') {
      if      (v == "M")    soundEnabled = !soundEnabled;
      else if (v == "M:0")  soundEnabled = false;
      else if (v == "M:1")  soundEnabled = true;
      else return;
      updateSound();
      sendStatus();
      return;
    }

    // ---- C 换端 ----
    if (v == "C") {
      if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
      if (roleState == ROLE_MASTER && slaveActualPWM > 0)
        { sendError("STOP_FIRST"); return; }
      cabAtEndA   = !cabAtEndA;
      headlightOn = false;
      updateLights();
      sendStatus();
      return;
    }

    // ---- S 停车 ----
    if (v == "S") {
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM == 0) { motorState = STATE_IDLE; actualDir = 0; }
      sendStatus();
      return;
    }

    // ---- F/R 前进后退 ----
    if ((c0 == 'F' || c0 == 'R') && v.length() >= 3 && v.charAt(1) == ':') {
      uint8_t nd = (c0 == 'F') ? 1 : 2;
      int lv = v.substring(2).toInt();
      if (lv < 1 || lv > 8) return;
      if (actualPWM > 0 && actualDir != 0 && actualDir != nd)
        { sendError("STOP_FIRST"); return; }

      targetDir   = nd;
      targetLevel = lv;
      targetPWM   = levelToPWM(lv);

      if (actualPWM == 0) {
        actualDir = nd;
        actualPWM = KICK_PWM;
        applyMotorPWM(actualDir, actualPWM);
        kickStartTime = millis();
        motorState = STATE_KICK;
      } else {
        motorState = STATE_RAMPING;
      }
      sendStatus();
      return;
    }

    // ---- CP 重联邀请 ----
    if (v == "CP") {
      if (roleState != ROLE_STANDALONE) { sendError("ALREADY_COUPLED"); return; }
      if (!isFullyStopped())            { sendError("STOP_FIRST");      return; }
      roleState = ROLE_INVITING;
      inviteStartTime = millis();
      lastInviteTime  = 0;
      uint8_t bc[6]; memset(bc, 0xFF, 6);
      addEspNowPeer(bc);
      sendStatus();
      return;
    }
    if (v == "CP:STOP") {
      if (roleState == ROLE_INVITING) { roleState = ROLE_STANDALONE; sendStatus(); }
      return;
    }

    // ---- J 接受邀请 ----
    if (c0 == 'J' && v.length() >= 3 && v.charAt(1) == ':') {
      if (roleState != ROLE_INVITED)  { sendError("NOT_INVITED"); return; }
      if (!isFullyStopped())          { sendError("STOP_FIRST");  return; }
      char end = v.charAt(2);
      if (end != 'A' && end != 'B') return;
      slaveCoupleEnd = end;
      sendAcceptPkt(inviterMAC, end);
      enterSlave(inviterMAC);
      sendStatus();
      return;
    }

    // ---- U 解联 ----
    if (v == "U") {
      if (roleState != ROLE_MASTER) { sendError("NOT_COUPLED"); return; }
      if (!isFullyStopped())        { sendError("STOP_FIRST");  return; }
      if (slaveActualPWM > 0)       { sendError("STOP_FIRST");  return; }
      // 发送解联包并启动重试
      sendUncouplePkt();
      uncoupleRetryLeft = UNCOUPLE_RETRY_COUNT;
      lastUncoupleTime  = millis();
      sendStatus();
      return;
    }

    // ---- K 速度系数 ----
    if (c0 == 'K' && v.length() >= 3 && v.charAt(1) == ':') {
      if (roleState != ROLE_MASTER)  { sendError("NOT_COUPLED");   return; }
      float k = v.substring(2).toFloat();
      if (k < 0.90f || k > 1.10f)   { sendError("INVALID_COEFF"); return; }
      speedCoeff = k;
      sendStatus();
      return;
    }
  }
};

// ============================================================================
// 电机状态机
// ============================================================================

void motorStateMachine() {
  unsigned long now = millis();

  switch (motorState) {

  case STATE_IDLE:
    // 演示退出完成
    if (demoState == DEMO_EXITING && actualPWM == 0) {
      if (roleState == ROLE_INVITED) {
        sendAcceptPkt(inviterMAC, slaveCoupleEnd);
        enterSlave(inviterMAC);
        demoState = DEMO_OFF;
        sendStatus();
      } else {
        demoState = DEMO_OFF;
        actualDir = 0;
      }
    }
    break;

  case STATE_KICK:
    if (now - kickStartTime >= KICK_TIME) {
      if (targetPWM == 0) {
        // kick 期间收到停车 → 从 KICK_PWM 开始减速
        actualPWM = KICK_PWM;
      } else if (targetPWM >= KICK_PWM) {
        // 目标就是最大值，直接到位
        actualPWM = targetPWM;
        applyMotorPWM(actualDir, actualPWM);
        motorState = STATE_RUNNING;
        lastRampTime = now;
        break;
      } else {
        // ★ 优化: kick 结束后进入坡道平滑过渡到目标
        //    而非直接跳变 (消除 255→214 的瞬间跌落感)
        actualPWM = KICK_PWM;
      }
      motorState  = STATE_RAMPING;
      lastRampTime = now;
    }
    break;

  case STATE_RAMPING:
    if (now - lastRampTime >= RAMP_INTERVAL) {
      lastRampTime = now;

      if (actualPWM < targetPWM) {
        actualPWM += RAMP_STEP;
        if (actualPWM > targetPWM) actualPWM = targetPWM;
      } else if (actualPWM > targetPWM) {
        if (actualPWM <= RAMP_STEP) actualPWM = 0;
        else                        actualPWM -= RAMP_STEP;
        if (actualPWM > 0 && actualPWM < MIN_PWM) actualPWM = 0;
      }

      if (actualPWM == 0) {
        applyMotorPWM(0, 0);
        actualDir  = 0;
        motorState = STATE_IDLE;
      } else {
        applyMotorPWM(actualDir, actualPWM);
      }

      if (actualPWM == targetPWM) {
        motorState = (actualPWM == 0) ? STATE_IDLE : STATE_RUNNING;
        if (actualPWM == 0) actualDir = 0;
      }
    }
    break;

  case STATE_RUNNING:
    if (actualPWM != targetPWM) {
      motorState  = STATE_RAMPING;
      lastRampTime = millis();
    }
    break;
  }
}

// ============================================================================
// 演示模式
// ============================================================================

void demoStateMachine() {
  if (demoState != DEMO_WAITING) return;
  if (deviceConnected) { demoState = DEMO_OFF; return; }
  if (millis() - bootTime < DEMO_WAIT_TIME) return;

  demoState    = DEMO_RUNNING;
  soundEnabled = true;
  targetDir    = DEMO_DIR;
  targetLevel  = DEMO_LEVEL;
  targetPWM    = levelToPWM(DEMO_LEVEL);
  actualDir    = DEMO_DIR;
  actualPWM    = KICK_PWM;
  applyMotorPWM(actualDir, actualPWM);
  kickStartTime = millis();
  motorState   = STATE_KICK;
  updateSound();
  DBG("Demo started");
}

// ============================================================================
// 重联超时 & 周期任务
// ============================================================================

void couplingTasks() {
  unsigned long now = millis();

  // 邀请
  if (roleState == ROLE_INVITING) {
    if (now - inviteStartTime >= ESPNOW_INVITE_TIMEOUT) {
      roleState = ROLE_STANDALONE; sendStatus(); return;
    }
    if (now - lastInviteTime >= ESPNOW_INVITE_INTERVAL) {
      lastInviteTime = now;
      sendInviteBroadcast();
    }
  }

  // SLAVE: CMD 超时
  if (roleState == ROLE_SLAVE && now - lastSlaveCmd >= SLAVE_CMD_TIMEOUT) {
    DBG("Slave CMD timeout");
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
    exitCoupling();
    sendStatus();
    return;
  }

  // MASTER: STATUS 超时
  if (roleState == ROLE_MASTER) {
    unsigned long el = now - lastSlaveStatus;
    if (el >= MASTER_STATUS_TIMEOUT) {
      DBG("Master STATUS timeout");
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
      exitCoupling();
      sendStatus();
      return;
    }
    if (el >= MASTER_STATUS_WARN) slaveStatusWarn = true;
  }

  // MASTER: 定期发 CMD
  if (roleState == ROLE_MASTER && now - lastCmdSendTime >= ESPNOW_CMD_INTERVAL) {
    lastCmdSendTime = now;
    sendCmdToSlave();
  }

  // SLAVE: 定期发 STATUS
  if (roleState == ROLE_SLAVE && now - lastStatusSendTime >= ESPNOW_STATUS_INTERVAL) {
    lastStatusSendTime = now;
    sendStatusToMaster();
  }

  // MASTER: 解联重试
  if (roleState == ROLE_MASTER && uncoupleRetryLeft > 0) {
    if (now - lastUncoupleTime >= UNCOUPLE_RETRY_INTERVAL) {
      lastUncoupleTime = now;
      sendUncouplePkt();
      uncoupleRetryLeft--;
      if (uncoupleRetryLeft == 0) {
        // 重试耗尽，强制解联
        DBG("Uncouple ACK timeout, forced");
        exitCoupling();
        sendStatus();
      }
    }
  }
}

// ============================================================================
// 开机自检
// ============================================================================

void selfTest() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_A_WHITE, HIGH); digitalWrite(LED_B_WHITE, HIGH);
    digitalWrite(LED_A_RED,   HIGH); digitalWrite(LED_B_RED,   HIGH);
    delay(200);
    digitalWrite(LED_A_WHITE, LOW);  digitalWrite(LED_B_WHITE, LOW);
    digitalWrite(LED_A_RED,   LOW);  digitalWrite(LED_B_RED,   LOW);
    delay(200);
  }
  cabAtEndA = true;  headlightOn = true;  updateLights(); delay(500);
  cabAtEndA = false; headlightOn = true;  updateLights(); delay(500);
  digitalWrite(SOUND_POWER, HIGH); delay(500); digitalWrite(SOUND_POWER, LOW);

  cabAtEndA = true;  headlightOn = false; soundEnabled = false;
  updateLights();
  updateSound();
}

// ============================================================================
// setup
// ============================================================================

void setup() {
  DBG_INIT(115200);

  // GPIO
  const uint8_t outPins[] = {LED_A_WHITE, LED_B_WHITE, LED_A_RED, LED_B_RED, SOUND_POWER};
  for (auto p : outPins) { pinMode(p, OUTPUT); digitalWrite(p, LOW); }

  // ADC
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  // PWM
  ledcSetup(PWM_CH_IN1, PWM_FREQ, PWM_RES);
  ledcSetup(PWM_CH_IN2, PWM_FREQ, PWM_RES);
  ledcAttachPin(MOTOR_IN1, PWM_CH_IN1);
  ledcAttachPin(MOTOR_IN2, PWM_CH_IN2);
  ledcWrite(PWM_CH_IN1, 0);
  ledcWrite(PWM_CH_IN2, 0);

  // 初始电池采样
  for (int i = 0; i < BATT_AVG_COUNT; i++) { sampleBattery(); delay(10); }

  selfTest();

  // WiFi (ESP-NOW)
  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
  esp_read_mac(myMAC, ESP_MAC_WIFI_STA);
  DBGF("MAC: %02X:%02X:%02X:%02X:%02X:%02X",
    myMAC[0],myMAC[1],myMAC[2],myMAC[3],myMAC[4],myMAC[5]);

  // ESP-NOW
  if (esp_now_init() != ESP_OK) DBG("ESP-NOW init FAIL");
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_register_send_cb(onEspNowSent);

  // BLE
  BLEDevice::init("BLE_Train");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCB());

  BLEService* svc = pServer->createService(SERVICE_UUID);

  pCtrlChar = svc->createCharacteristic(CHAR_CTRL_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pCtrlChar->setCallbacks(new CtrlCB());

  pStatusChar = svc->createCharacteristic(CHAR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());

  // 版本特征 (只读)
  BLECharacteristic* pVerChar = svc->createCharacteristic(CHAR_VERSION_UUID,
    BLECharacteristic::PROPERTY_READ);
  char verBuf[32];
  snprintf(verBuf, sizeof(verBuf), "FW:%s %s", FIRMWARE_VERSION, __DATE__);
  pVerChar->setValue(verBuf);

  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  bootTime = millis();
  demoState = DEMO_WAITING;
  DBG("BLE_Train ready!");
}

// ============================================================================
// loop
// ============================================================================

void loop() {
  unsigned long now = millis();

  demoStateMachine();
  motorStateMachine();

  // ★ 优化: 仅当 actualPWM 发生变化时才更新音效 GPIO
  //    避免每次 loop 都执行 digitalWrite (约节省 2~3μs/次)
  if (actualPWM != prevActualPWM) {
    updateSound();
    prevActualPWM = actualPWM;
  }

  // 电池
  if (now - lastBattTime >= BATT_SAMPLE_INTERVAL) {
    lastBattTime = now;
    sampleBattery();
  }

  // 重联
  couplingTasks();

  // BLE 断连
  if (wasConnected && !deviceConnected) {
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
    delay(500);
    pServer->startAdvertising();
    DBG("BLE disconnected");
  }
  // ★ 优化: BLE 重连时立即推送完整状态
  if (!wasConnected && deviceConnected) {
    sendStatus();
    DBG("BLE connected, status pushed");
  }
  wasConnected = deviceConnected;

  // 周期上报
  if (deviceConnected && now - lastBleStatusTime >= 200) {
    lastBleStatusTime = now;
    sendStatus();
  }
}