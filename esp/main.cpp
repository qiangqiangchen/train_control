/**
 * ============================================================================
 * 🚂 BLE 遥控火车 — 终极固件 (含双机重联) v1.6
 * ============================================================================
 *
 * v1.6 修改:
 *   - 修复 ESP-NOW 重联广播不可靠的问题
 *   - addEspNowPeer 明确指定 channel=1
 *   - 邀请广播每次发3包提高接收概率
 *   - 发邀请前重新固定WiFi信道 (防BLE导致漂移)
 *   - loop中周期性检查WiFi信道
 *   - 邀请间隔从500ms缩短到300ms
 *   - 邀请期间BLE notify间隔适当增大释放射频
 *   - 添加ESP-NOW收发调试日志
 *
 * v1.5 修改:
 *   - 取消固定周期状态上报
 *   - 改为纯事件驱动上报 (命令/PWM变化/电池/重联)
 *   - 去重机制: 内容相同不重复发送
 *   - F:0/R:0 正确处理为选档不启动
 *   - DIR 上报优先反映 targetDir
 *   - BLE 断连防抖 grace period
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
#include <esp_task_wdt.h>

// ============================================================================
// 调试开关
// ============================================================================
#define DEBUG_ENABLED  1

#if DEBUG_ENABLED
  #define DBG_INIT(baud)    Serial.begin(baud)
  #define DBG(msg)          Serial.println(F(msg))
  #define DBGF(fmt, ...)    Serial.printf(fmt "\n", ##__VA_ARGS__)
#else
  #define DBG_INIT(baud)    ((void)0)
  #define DBG(msg)          ((void)0)
  #define DBGF(fmt, ...)    ((void)0)
#endif

#define FIRMWARE_VERSION  "1.6.0"

// ============================================================================
// 引脚
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
#define MIN_PWM         200
#define MAX_PWM         255
#define THROTTLE_STEPS  8
#define KICK_PWM        255
#define KICK_TIME       500
#define RAMP_STEP       4
#define RAMP_INTERVAL   20
#define JOG_PULSE_US    800
#define JOG_GAP_US      200

// ============================================================================
// PWM
// ============================================================================
#define PWM_CH_IN1   0
#define PWM_CH_IN2   1
#define PWM_FREQ     200
#define PWM_RES      8

// ============================================================================
// 速度参数
// ============================================================================
#define MAX_SPEED_KMH 160
#define MIN_SPEED_KMH 10

// ============================================================================
// 演示
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
#define BATT_LOW_PCT          10

// ============================================================================
// ESP-NOW
// ============================================================================
#define ESPNOW_CMD_INTERVAL     100
#define ESPNOW_STATUS_INTERVAL  200
#define ESPNOW_INVITE_INTERVAL  300     // ★ v1.6: 从500ms缩短到300ms
#define ESPNOW_INVITE_TIMEOUT   30000
#define ESPNOW_INVITE_BURST     3       // ★ v1.6: 每次邀请发送包数
#define ESPNOW_INVITE_BURST_GAP 10000   // ★ v1.6: 连发间隔 10ms (微秒)
#define SLAVE_CMD_TIMEOUT       300
#define MASTER_STATUS_WARN      1000
#define MASTER_STATUS_TIMEOUT   3000
#define UNCOUPLE_RETRY_COUNT    3
#define UNCOUPLE_RETRY_INTERVAL 200

// ============================================================================
// WiFi 信道
// ============================================================================
#define ESPNOW_CHANNEL              1       // ★ v1.6: ESP-NOW 使用的固定信道
#define WIFI_CHANNEL_CHECK_INTERVAL 5000    // ★ v1.6: 信道检查间隔 5秒

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
// BLE 上报
// ============================================================================
#define BLE_NOTIFY_MIN_GAP     50

// ============================================================================
// BLE 断连防抖
// ============================================================================
#define BLE_DISCONNECT_GRACE   500

// ============================================================================
// 缓冲区
// ============================================================================
#define BLE_CMD_BUF_SIZE    64
#define ESPNOW_RX_BUF_SIZE 64

// ============================================================================
// ESP-NOW 数据结构
// ============================================================================
#pragma pack(push, 1)

struct InvitePayload {
  uint8_t masterMAC[6];
  uint8_t masterTailEnd;
};

struct AcceptPayload {
  uint8_t slaveMAC[6];
  uint8_t slaveCoupleEnd;
};

struct CmdPayload {
  uint8_t  targetDir;
  uint8_t  targetPWM;
  uint8_t  lightEndA;
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
  ROLE_STANDALONE, ROLE_INVITING, ROLE_INVITED, ROLE_MASTER, ROLE_SLAVE
};

enum MotorState : uint8_t {
  STATE_IDLE, STATE_KICK, STATE_RAMPING, STATE_RUNNING
};

enum DemoState : uint8_t {
  DEMO_WAITING, DEMO_RUNNING, DEMO_EXITING, DEMO_OFF
};

// ============================================================================
// 全局状态
// ============================================================================
volatile bool cabAtEndA   = true;
volatile bool headlightOn = false;
volatile bool soundEnabled = false;

volatile uint8_t  targetDir    = 0;
volatile uint8_t  actualDir    = 0;
volatile uint8_t  targetLevel  = 0;
volatile uint16_t targetPWM    = 0;
volatile uint16_t actualPWM    = 0;
uint16_t prevActualPWM = 0;

volatile MotorState motorState = STATE_IDLE;
unsigned long kickStartTime = 0;
unsigned long lastRampTime  = 0;

volatile DemoState demoState = DEMO_WAITING;
unsigned long bootTime = 0;

uint16_t batteryMV   = 4500;
uint8_t  batteryPct  = 100;
uint16_t battSamples[BATT_AVG_COUNT];
uint8_t  battSampleIdx     = 0;
bool     battSamplesFilled = false;
unsigned long lastBattTime  = 0;

volatile RoleState roleState = ROLE_STANDALONE;
uint8_t  peerMAC[6]  = {};
uint8_t  slaveCoupleEnd        = 'A';
uint8_t  masterCoupleEndStored = 'B';
float    speedCoeff  = 1.00f;
uint8_t  cmdSeqNum   = 0;

uint8_t  slaveActualPWM    = 0;
uint8_t  slaveBatteryPct   = 0;
uint16_t slaveBatteryMV    = 0;
bool     slaveStatusValid  = false;
bool     slaveStatusWarn   = false;

unsigned long inviteStartTime = 0;
unsigned long lastInviteTime  = 0;
uint8_t  inviterMAC[6] = {};

uint8_t  uncoupleRetryLeft     = 0;
unsigned long lastUncoupleTime = 0;

unsigned long lastSlaveCmd       = 0;
unsigned long lastSlaveStatus    = 0;
unsigned long lastCmdSendTime    = 0;
unsigned long lastStatusSendTime = 0;
unsigned long lastNotifyTime     = 0;

BLEServer*         pServer      = nullptr;
BLECharacteristic* pCtrlChar    = nullptr;
BLECharacteristic* pStatusChar  = nullptr;
volatile bool deviceConnected   = false;
bool wasConnected               = false;

volatile bool bleCmdPending = false;
char          bleCmdBuf[BLE_CMD_BUF_SIZE];
portMUX_TYPE  bleCmdMux = portMUX_INITIALIZER_UNLOCKED;

volatile bool statusPushRequested = false;

volatile bool errorPushPending = false;
char          errorPushBuf[40];

volatile bool espnowRxPending = false;
uint8_t       espnowRxMAC[6];
uint8_t       espnowRxBuf[ESPNOW_RX_BUF_SIZE];
int           espnowRxLen = 0;
portMUX_TYPE  espnowRxMux = portMUX_INITIALIZER_UNLOCKED;

volatile bool bleJustConnected    = false;
volatile bool bleJustDisconnected = false;
unsigned long bleDisconnectTime   = 0;

uint8_t myMAC[6];

uint32_t loopCounter = 0;
unsigned long lastLoopReport = 0;

// 状态上报去重
char lastStatusBuf[220] = {0};

// ★ v1.6: WiFi信道检查
unsigned long lastChannelCheck = 0;

// ★ v1.6: ESP-NOW 发送统计 (调试用)
uint32_t espnowTxCount   = 0;
uint32_t espnowTxFail    = 0;
uint32_t espnowRxCount   = 0;
uint32_t espnowDelivFail = 0;

// ============================================================================
// 工具函数
// ============================================================================

uint16_t levelToPWM(uint8_t lv) {
  if (lv == 0)              return 0;
  if (lv >= THROTTLE_STEPS) return MAX_PWM;
  return MIN_PWM + (uint16_t)(lv - 1) * (MAX_PWM - MIN_PWM) / (THROTTLE_STEPS - 1);
}

uint8_t pwmToLevel(uint16_t pwm) {
  if (pwm == 0) return 0;
  for (uint8_t l = 1; l <= THROTTLE_STEPS; l++) {
    if (levelToPWM(l) >= pwm) return l;
  }
  return THROTTLE_STEPS;
}

uint16_t clampPWM(uint16_t pwm) {
  if (pwm > MAX_PWM) return MAX_PWM;
  if (pwm > 0 && pwm < MIN_PWM) return MIN_PWM;
  return pwm;
}

bool isFullyStopped() {
  return targetPWM == 0 && actualPWM == 0;
}

bool isDemoActive() {
  return demoState == DEMO_RUNNING || demoState == DEMO_EXITING;
}

const char* roleStr() {
  switch (roleState) {
    case ROLE_STANDALONE: return "STANDALONE";
    case ROLE_INVITING:   return "INVITING";
    case ROLE_INVITED:    return "INVITED";
    case ROLE_MASTER:     return "MASTER";
    case ROLE_SLAVE:      return "SLAVE";
    default:              return "?";
  }
}

const char* motorStr() {
  switch (motorState) {
    case STATE_IDLE:    return "IDLE";
    case STATE_KICK:    return "KICK";
    case STATE_RAMPING: return "RAMP";
    case STATE_RUNNING: return "RUN";
    default:            return "?";
  }
}

// ★ v1.6: ESP-NOW 包类型名 (调试用)
const char* pktTypeStr(uint8_t type) {
  switch (type) {
    case PKT_INVITE:       return "INVITE";
    case PKT_ACCEPT:       return "ACCEPT";
    case PKT_CMD:          return "CMD";
    case PKT_STATUS:       return "STATUS";
    case PKT_UNCOUPLE:     return "UNCOUPLE";
    case PKT_UNCOUPLE_ACK: return "UNCOUPLE_ACK";
    default:               return "UNKNOWN";
  }
}

uint16_t pwmToSpeed(uint16_t pwm) {
  if (pwm == 0) return 0;
  if (pwm <= MIN_PWM) return MIN_SPEED_KMH;
  if (pwm >= MAX_PWM) return MAX_SPEED_KMH;
  return MIN_SPEED_KMH +
         (uint32_t)(pwm - MIN_PWM) * (MAX_SPEED_KMH - MIN_SPEED_KMH) / (MAX_PWM - MIN_PWM);
}

// ★ v1.6: 确保WiFi信道正确
void ensureWifiChannel() {
  uint8_t primary;
  wifi_second_chan_t second;
  esp_wifi_get_channel(&primary, &second);
  if (primary != ESPNOW_CHANNEL) {
    DBGF("[WIFI] Channel drifted to %d, fixing to %d", primary, ESPNOW_CHANNEL);
    esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE);
  }
}

// ============================================================================
// 电机输出
// ============================================================================

void motorJogPulse() {
  ledcWrite(PWM_CH_IN1, 255);
  ledcWrite(PWM_CH_IN2, 0);
  delayMicroseconds(JOG_PULSE_US);
  ledcWrite(PWM_CH_IN1, 0);
  ledcWrite(PWM_CH_IN2, 255);
  delayMicroseconds(JOG_PULSE_US);
  ledcWrite(PWM_CH_IN1, 0);
  ledcWrite(PWM_CH_IN2, 0);
  delayMicroseconds(JOG_GAP_US);
}

void applyMotorPWM(uint8_t dir, uint16_t pwm) {
  if (pwm == 0 || dir == 0) {
    ledcWrite(PWM_CH_IN1, 0);
    ledcWrite(PWM_CH_IN2, 0);
    return;
  }
  bool rev = (dir == 2);
  if (!cabAtEndA) rev = !rev;
  ledcWrite(PWM_CH_IN1, rev ? 0   : pwm);
  ledcWrite(PWM_CH_IN2, rev ? pwm : 0);
}

void startMotor(uint8_t dir) {
  if (dir == 0) return;
  actualDir = dir;
  motorJogPulse();
  actualPWM = KICK_PWM;
  applyMotorPWM(actualDir, actualPWM);
  kickStartTime = millis();
  motorState = STATE_KICK;
}

// ============================================================================
// 灯光
// ============================================================================

static inline void setEndLight(uint8_t pinW, uint8_t pinR,
                               uint8_t mode, bool hlOn) {
  switch (mode) {
    case 0:  digitalWrite(pinW, LOW);             digitalWrite(pinR, LOW);  break;
    case 1:  digitalWrite(pinW, hlOn ? HIGH:LOW); digitalWrite(pinR, LOW);  break;
    case 2:  digitalWrite(pinW, LOW);             digitalWrite(pinR, HIGH); break;
    default: digitalWrite(pinW, LOW);             digitalWrite(pinR, LOW);  break;
  }
}

void updateLights(uint8_t* outSlaveLightA = nullptr,
                  uint8_t* outSlaveLightB = nullptr,
                  bool*    outSlaveHL     = nullptr)
{
  uint8_t modeA = 0, modeB = 0;
  if (roleState == ROLE_MASTER) {
    if (cabAtEndA) { modeA = 1; modeB = 0; }
    else           { modeA = 0; modeB = 1; }
  } else if (roleState == ROLE_SLAVE) {
    return;
  } else {
    if (cabAtEndA) { modeA = 1; modeB = 2; }
    else           { modeA = 2; modeB = 1; }
  }
  setEndLight(LED_A_WHITE, LED_A_RED, modeA, headlightOn);
  setEndLight(LED_B_WHITE, LED_B_RED, modeB, headlightOn);

  if (roleState == ROLE_MASTER && outSlaveLightA && outSlaveLightB && outSlaveHL) {
    bool cabAtCouple = (cabAtEndA  && masterCoupleEndStored == 'A') ||
                       (!cabAtEndA && masterCoupleEndStored == 'B');
    uint8_t nearMode = 0, farMode;
    bool sHL;
    if (!cabAtCouple) { farMode = 2; sHL = false; }
    else              { farMode = 1; sHL = headlightOn; }
    if (slaveCoupleEnd == 'A') {
      *outSlaveLightA = nearMode; *outSlaveLightB = farMode;
    } else {
      *outSlaveLightA = farMode;  *outSlaveLightB = nearMode;
    }
    *outSlaveHL = sHL;
  }
}

// ============================================================================
// 音效
// ============================================================================

void updateSound() {
  bool on = soundEnabled && actualPWM > 0;
  digitalWrite(SOUND_POWER, on ? HIGH : LOW);
}

// ============================================================================
// 电池
// ============================================================================

static uint16_t adcReadMedian(uint8_t pin, uint8_t n = 5) {
  uint16_t buf[7];
  if (n > 7) n = 7;
  for (uint8_t i = 0; i < n; i++) buf[i] = analogRead(pin);
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
// ESP-NOW 发送
// ============================================================================

// ★ v1.6: 添加发送结果日志和统计
bool espnowSend(const uint8_t* dest, const void* data, size_t len) {
  esp_err_t err = esp_now_send(dest, (const uint8_t*)data, len);
  espnowTxCount++;
  if (err != ESP_OK) {
    espnowTxFail++;
    DBGF("[ESPNOW] TX FAIL err=%d dest=%02X:%02X:%02X:%02X:%02X:%02X type=0x%02X",
         err, dest[0], dest[1], dest[2], dest[3], dest[4], dest[5],
         ((const uint8_t*)data)[0]);
    return false;
  }
  return true;
}

// ★ v1.6: 每次发3包，提高广播可靠性
void sendInviteBroadcast() {
  uint8_t buf[1 + sizeof(InvitePayload)];
  buf[0] = PKT_INVITE;
  InvitePayload* p = (InvitePayload*)(buf + 1);
  memcpy(p->masterMAC, myMAC, 6);
  p->masterTailEnd = cabAtEndA ? 'B' : 'A';
  uint8_t bc[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

  for (int i = 0; i < ESPNOW_INVITE_BURST; i++) {
    espnowSend(bc, buf, sizeof(buf));
    if (i < ESPNOW_INVITE_BURST - 1) {
      delayMicroseconds(ESPNOW_INVITE_BURST_GAP);
    }
  }

  DBGF("[COUPLE] Invite broadcast sent (%d packets), tailEnd=%c",
       ESPNOW_INVITE_BURST, cabAtEndA ? 'B' : 'A');
}

void sendAcceptPkt(const uint8_t* masterMAC, uint8_t coupleEnd) {
  uint8_t buf[1 + sizeof(AcceptPayload)];
  buf[0] = PKT_ACCEPT;
  AcceptPayload* p = (AcceptPayload*)(buf + 1);
  memcpy(p->slaveMAC, myMAC, 6);
  p->slaveCoupleEnd = coupleEnd;

  // ★ v1.6: Accept 也发3次提高可靠性
  for (int i = 0; i < 3; i++) {
    espnowSend(masterMAC, buf, sizeof(buf));
    if (i < 2) delayMicroseconds(ESPNOW_INVITE_BURST_GAP);
  }

  DBGF("[COUPLE] Accept sent to %02X:%02X:%02X:%02X:%02X:%02X end=%c",
       masterMAC[0], masterMAC[1], masterMAC[2],
       masterMAC[3], masterMAC[4], masterMAC[5], coupleEnd);
}

void sendCmdToSlave() {
  if (roleState != ROLE_MASTER) return;
  uint8_t sDir = targetDir;
  if (slaveCoupleEnd == 'B' && sDir != 0) sDir = (sDir == 1) ? 2 : 1;
  uint16_t sPWM = (targetPWM == 0) ? 0
                : clampPWM((uint16_t)(targetPWM * speedCoeff + 0.5f));
  uint8_t lA = 0, lB = 0; bool sHL = false;
  updateLights(&lA, &lB, &sHL);
  uint8_t buf[1 + sizeof(CmdPayload)];
  buf[0] = PKT_CMD;
  CmdPayload* p = (CmdPayload*)(buf + 1);
  p->targetDir = sDir; p->targetPWM = (uint8_t)sPWM;
  p->lightEndA = lA; p->lightEndB = lB;
  p->headlightOn = sHL ? 1 : 0; p->soundEnabled = soundEnabled ? 1 : 0;
  p->seqNum = cmdSeqNum++;
  espnowSend(peerMAC, buf, sizeof(buf));
}

void sendStatusToMaster() {
  if (roleState != ROLE_SLAVE) return;
  uint8_t buf[1 + sizeof(StatusPayload)];
  buf[0] = PKT_STATUS;
  StatusPayload* p = (StatusPayload*)(buf + 1);
  p->actualPWM = (uint8_t)actualPWM; p->batteryPct = batteryPct; p->batteryMV = batteryMV;
  espnowSend(peerMAC, buf, sizeof(buf));
}

void sendUncouplePkt() {
  uint8_t buf[1] = { PKT_UNCOUPLE };
  espnowSend(peerMAC, buf, 1);
  DBGF("[COUPLE] Uncouple sent to %02X:%02X:%02X:%02X:%02X:%02X",
       peerMAC[0], peerMAC[1], peerMAC[2],
       peerMAC[3], peerMAC[4], peerMAC[5]);
}

void sendUncoupleAckPkt() {
  uint8_t buf[1] = { PKT_UNCOUPLE_ACK };
  espnowSend(peerMAC, buf, 1);
  DBG("[COUPLE] Uncouple ACK sent");
}

// ============================================================================
// 重联管理
// ============================================================================

// ★ v1.6: 明确指定信道，已存在时先删再加
void addEspNowPeer(const uint8_t* mac) {
  if (esp_now_is_peer_exist(mac)) {
    esp_now_del_peer(mac);
    DBGF("[ESPNOW] Peer deleted (re-add): %02X:%02X:%02X:%02X:%02X:%02X",
         mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  }
  esp_now_peer_info_t pi = {};
  memcpy(pi.peer_addr, mac, 6);
  pi.channel = ESPNOW_CHANNEL;  // ★ v1.6: 明确指定信道，不用0
  pi.encrypt = false;
  esp_err_t err = esp_now_add_peer(&pi);
  if (err == ESP_OK) {
    DBGF("[ESPNOW] Peer added: %02X:%02X:%02X:%02X:%02X:%02X ch=%d",
         mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], ESPNOW_CHANNEL);
  } else {
    DBGF("[ESPNOW] Add peer FAILED: %d", err);
  }
}

void enterMaster(const uint8_t* slaveMAC, uint8_t slvEnd) {
  roleState = ROLE_MASTER;
  memcpy(peerMAC, slaveMAC, 6);
  slaveCoupleEnd = slvEnd;
  masterCoupleEndStored = cabAtEndA ? 'B' : 'A';
  speedCoeff = 1.00f;
  slaveActualPWM = slaveBatteryPct = 0; slaveBatteryMV = 0;
  slaveStatusValid = slaveStatusWarn = false;
  lastSlaveStatus = lastCmdSendTime = millis();
  cmdSeqNum = 0; uncoupleRetryLeft = 0;
  addEspNowPeer(peerMAC);
  updateLights();
  DBGF("[COUPLE] Entered MASTER, slave=%02X:%02X:%02X:%02X:%02X:%02X end=%c",
       slaveMAC[0], slaveMAC[1], slaveMAC[2],
       slaveMAC[3], slaveMAC[4], slaveMAC[5], slvEnd);
}

void enterSlave(const uint8_t* masterMAC) {
  roleState = ROLE_SLAVE;
  memcpy(peerMAC, masterMAC, 6);
  lastSlaveCmd = lastStatusSendTime = millis();
  addEspNowPeer(peerMAC);
  DBGF("[COUPLE] Entered SLAVE, master=%02X:%02X:%02X:%02X:%02X:%02X",
       masterMAC[0], masterMAC[1], masterMAC[2],
       masterMAC[3], masterMAC[4], masterMAC[5]);
}

void exitCoupling() {
  DBGF("[COUPLE] Exiting %s mode", roleStr());
  if (roleState == ROLE_MASTER || roleState == ROLE_SLAVE)
    esp_now_del_peer(peerMAC);
  roleState = ROLE_STANDALONE;
  memset(peerMAC, 0, 6);
  slaveStatusValid = slaveStatusWarn = false;
  uncoupleRetryLeft = 0;
  updateLights();
}

// ============================================================================
// BLE 状态上报 — 纯事件驱动 + 去重
// ============================================================================

// ★ v1.6: 邀请期间增大 notify 间隔，释放射频给 ESP-NOW
bool safeNotify(BLECharacteristic* pChar, const char* value) {
  if (!deviceConnected) return false;
  unsigned long now = millis();

  unsigned long minGap = BLE_NOTIFY_MIN_GAP;
  if (roleState == ROLE_INVITING) {
    minGap = 100;  // ★ 邀请期间 100ms 间隔 (正常 50ms)
  }

  if (now - lastNotifyTime < minGap) return false;
  pChar->setValue(value);
  pChar->notify();
  lastNotifyTime = now;
  return true;
}

void sendStatus() {
  if (!deviceConnected) return;

  char buf[220];
  int cap = sizeof(buf), pos = 0;

  #define APPEND(fmt, ...) do { \
    int n = snprintf(buf + pos, cap - pos, fmt, ##__VA_ARGS__); \
    if (n > 0 && pos + n < cap) pos += n; \
  } while(0)

  const char* dirStr;
  if (targetDir == 1)       dirStr = "FWD";
  else if (targetDir == 2)  dirStr = "REV";
  else if (actualPWM > 0)   dirStr = (actualDir == 1 ? "FWD" : "REV");
  else                      dirStr = "STOP";

  bool sndOn = soundEnabled && actualPWM > 0;

  APPEND("CAB:%c HL:%s DIR:%s LV:%d APWM:%d TPWM:%d MS:%s",
    cabAtEndA ? 'A' : 'B',
    headlightOn ? "ON" : "OFF",
    dirStr,
    (int)targetLevel, (int)actualPWM, (int)targetPWM,
    motorStr());

  APPEND(" SE:%s SND:%s DM:%s",
    soundEnabled ? "ON" : "OFF",
    sndOn ? "ON" : "OFF",
    isDemoActive() ? "ON" : "OFF");

  APPEND(" BAT:%d BATV:%d.%02d",
    batteryPct, batteryMV / 1000, (batteryMV % 1000) / 10);

  if (batteryPct <= BATT_LOW_PCT) APPEND(" BLOW:1");

  APPEND(" SPD:%d", (int)pwmToSpeed(actualPWM));

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

  if (strcmp(buf, lastStatusBuf) == 0) return;
  strncpy(lastStatusBuf, buf, sizeof(lastStatusBuf) - 1);
  lastStatusBuf[sizeof(lastStatusBuf) - 1] = '\0';

  if (safeNotify(pStatusChar, buf)) {
    DBGF("[STATUS] %s", buf);
  }
}

void sendError(const char* msg) {
  snprintf(errorPushBuf, sizeof(errorPushBuf), "ERR:%s", msg);
  errorPushPending = true;
}

// ============================================================================
// ESP-NOW 接收
// ============================================================================

void IRAM_ATTR onEspNowRecv(const uint8_t* mac, const uint8_t* data, int len) {
  portENTER_CRITICAL(&espnowRxMux);
  if (!espnowRxPending && len > 0 && len <= ESPNOW_RX_BUF_SIZE) {
    memcpy(espnowRxMAC, mac, 6);
    memcpy(espnowRxBuf, data, len);
    espnowRxLen = len;
    espnowRxPending = true;
  }
  portEXIT_CRITICAL(&espnowRxMux);
}

// ★ v1.6: 添加发送确认日志
void onEspNowSent(const uint8_t* mac, esp_now_send_status_t status) {
  if (status != ESP_NOW_SEND_SUCCESS) {
    espnowDelivFail++;
    #if DEBUG_ENABLED
    if (mac) {
      DBGF("[ESPNOW] Delivery FAILED to %02X:%02X:%02X:%02X:%02X:%02X (total fails: %d)",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], espnowDelivFail);
    }
    #endif
  }
}

void processEspNowRx() {
  if (!espnowRxPending) return;
  uint8_t mac[6], data[ESPNOW_RX_BUF_SIZE]; int len;
  portENTER_CRITICAL(&espnowRxMux);
  memcpy(mac, espnowRxMAC, 6);
  len = espnowRxLen;
  memcpy(data, espnowRxBuf, len);
  espnowRxPending = false;
  portEXIT_CRITICAL(&espnowRxMux);

  if (len < 1) return;
  uint8_t type = data[0];
  const uint8_t* pl = data + 1;

  espnowRxCount++;

  // ★ v1.6: 接收日志
  DBGF("[ESPNOW] RX %s (0x%02X) len=%d from=%02X:%02X:%02X:%02X:%02X:%02X role=%s",
       pktTypeStr(type), type, len,
       mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
       roleStr());

  switch (type) {
  case PKT_INVITE: {
    if (roleState != ROLE_STANDALONE && roleState != ROLE_INVITED) {
      DBGF("[COUPLE] Invite ignored, current role=%s", roleStr());
      return;
    }
    if (len < 1 + (int)sizeof(InvitePayload)) {
      DBGF("[COUPLE] Invite too short: %d bytes", len);
      return;
    }
    const InvitePayload* inv = (const InvitePayload*)pl;

    DBGF("[COUPLE] Invite from %02X:%02X:%02X:%02X:%02X:%02X tailEnd=%c",
         inv->masterMAC[0], inv->masterMAC[1], inv->masterMAC[2],
         inv->masterMAC[3], inv->masterMAC[4], inv->masterMAC[5],
         inv->masterTailEnd);

    if (demoState == DEMO_RUNNING) {
      demoState = DEMO_EXITING; soundEnabled = false;
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = millis(); }
      updateSound();
      memcpy(inviterMAC, inv->masterMAC, 6);
      roleState = ROLE_INVITED;
      slaveCoupleEnd = cabAtEndA ? 'A' : 'B';
      statusPushRequested = true;
      DBG("[COUPLE] Demo interrupted by invite, exiting demo");
      return;
    }
    memcpy(inviterMAC, inv->masterMAC, 6);
    roleState = ROLE_INVITED;
    statusPushRequested = true;
    DBG("[COUPLE] Role changed to INVITED");
    break;
  }
  case PKT_ACCEPT: {
    if (roleState != ROLE_INVITING) {
      DBGF("[COUPLE] Accept ignored, current role=%s", roleStr());
      return;
    }
    if (len < 1 + (int)sizeof(AcceptPayload)) {
      DBGF("[COUPLE] Accept too short: %d bytes", len);
      return;
    }
    const AcceptPayload* acc = (const AcceptPayload*)pl;
    DBGF("[COUPLE] Accept from %02X:%02X:%02X:%02X:%02X:%02X end=%c",
         acc->slaveMAC[0], acc->slaveMAC[1], acc->slaveMAC[2],
         acc->slaveMAC[3], acc->slaveMAC[4], acc->slaveMAC[5],
         acc->slaveCoupleEnd);
    enterMaster(acc->slaveMAC, acc->slaveCoupleEnd);
    statusPushRequested = true;
    break;
  }
  case PKT_CMD: {
    if (roleState != ROLE_SLAVE) return;
    if (len < 1 + (int)sizeof(CmdPayload)) return;
    const CmdPayload* cmd = (const CmdPayload*)pl;
    lastSlaveCmd = millis();
    setEndLight(LED_A_WHITE, LED_A_RED, cmd->lightEndA, cmd->headlightOn);
    setEndLight(LED_B_WHITE, LED_B_RED, cmd->lightEndB, cmd->headlightOn);
    soundEnabled = cmd->soundEnabled;
    if (cmd->targetPWM == 0) {
      targetDir = targetLevel = targetPWM = 0;
    } else if (actualPWM > 0 && actualDir != 0 && actualDir != cmd->targetDir) {
      targetDir = targetLevel = targetPWM = 0;
    } else {
      targetDir = cmd->targetDir; targetPWM = cmd->targetPWM;
      targetLevel = pwmToLevel(cmd->targetPWM);
      if (actualPWM == 0) startMotor(cmd->targetDir);
      else { motorState = STATE_RAMPING; lastRampTime = millis(); }
    }
    break;
  }
  case PKT_STATUS: {
    if (roleState != ROLE_MASTER) return;
    if (len < 1 + (int)sizeof(StatusPayload)) return;
    const StatusPayload* st = (const StatusPayload*)pl;
    slaveActualPWM = st->actualPWM; slaveBatteryPct = st->batteryPct;
    slaveBatteryMV = st->batteryMV;
    slaveStatusValid = true; slaveStatusWarn = false;
    lastSlaveStatus = millis();
    statusPushRequested = true;
    break;
  }
  case PKT_UNCOUPLE: {
    if (roleState != ROLE_SLAVE) return;
    sendUncoupleAckPkt();
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = millis(); }
    exitCoupling();
    statusPushRequested = true;
    break;
  }
  case PKT_UNCOUPLE_ACK: {
    if (roleState != ROLE_MASTER) return;
    uncoupleRetryLeft = 0;
    exitCoupling();
    statusPushRequested = true;
    break;
  }
  default:
    DBGF("[ESPNOW] Unknown packet type: 0x%02X", type);
    break;
  }
}

// ============================================================================
// BLE 回调
// ============================================================================

static class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    deviceConnected = true; bleJustConnected = true;
    DBG("[BLE] Connected");
  }
  void onDisconnect(BLEServer*) override {
    deviceConnected = false; bleJustDisconnected = true;
    DBG("[BLE] Disconnected");
  }
} serverCbInstance;

static class CtrlCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    std::string val = pChar->getValue();
    if (val.empty()) return;
    size_t copyLen = val.length();
    if (copyLen >= BLE_CMD_BUF_SIZE) copyLen = BLE_CMD_BUF_SIZE - 1;
    portENTER_CRITICAL(&bleCmdMux);
    memcpy(bleCmdBuf, val.c_str(), copyLen);
    bleCmdBuf[copyLen] = '\0';
    bleCmdPending = true;
    portEXIT_CRITICAL(&bleCmdMux);
  }
} ctrlCbInstance;

// ============================================================================
// BLE 指令处理
// ============================================================================

static void trimInPlace(char* s) {
  char* p = s;
  while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
  if (p != s) memmove(s, p, strlen(p) + 1);
  int len = strlen(s);
  while (len > 0 && (s[len-1]==' '||s[len-1]=='\t'||s[len-1]=='\r'||s[len-1]=='\n'))
    s[--len] = '\0';
}

void processBleCmd() {
  if (!bleCmdPending) return;
  char cmd[BLE_CMD_BUF_SIZE];
  portENTER_CRITICAL(&bleCmdMux);
  memcpy(cmd, bleCmdBuf, BLE_CMD_BUF_SIZE);
  bleCmdPending = false;
  portEXIT_CRITICAL(&bleCmdMux);

  trimInPlace(cmd);
  int cmdLen = strlen(cmd);
  if (cmdLen == 0) return;

  DBGF("[CMD] '%s' role=%s motor=%s dir=%d/%d pwm=%d/%d",
       cmd, roleStr(), motorStr(),
       (int)targetDir, (int)actualDir, (int)targetPWM, (int)actualPWM);

  if (demoState == DEMO_EXITING) { sendError("DEMO_STOPPING"); return; }
  if (roleState == ROLE_SLAVE)   { sendError("SLAVE_MODE"); return; }

  char c0 = cmd[0];

  // ---- L ----
  if (c0 == 'L') {
    if (strcmp(cmd,"L")==0)        headlightOn = !headlightOn;
    else if (strcmp(cmd,"L:0")==0) headlightOn = false;
    else if (strcmp(cmd,"L:1")==0) headlightOn = true;
    else return;
    updateLights();
    statusPushRequested = true;
    return;
  }

  // ---- M ----
  if (c0 == 'M') {
    if (strcmp(cmd,"M")==0)        soundEnabled = !soundEnabled;
    else if (strcmp(cmd,"M:0")==0) soundEnabled = false;
    else if (strcmp(cmd,"M:1")==0) soundEnabled = true;
    else return;
    updateSound();
    statusPushRequested = true;
    return;
  }

  // ---- C ----
  if (strcmp(cmd,"C") == 0) {
    if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
    if (roleState == ROLE_MASTER && slaveActualPWM > 0) { sendError("STOP_FIRST"); return; }
    cabAtEndA = !cabAtEndA;
    headlightOn = false;
    targetDir = 0;
    updateLights();
    statusPushRequested = true;
    return;
  }

  // ---- S ----
  if (strcmp(cmd,"S") == 0) {
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM == 0) { motorState = STATE_IDLE; actualDir = 0; }
    else { motorState = STATE_RAMPING; lastRampTime = millis(); }
    statusPushRequested = true;
    return;
  }

  // ---- F/R ----
  if ((c0 == 'F' || c0 == 'R') && cmdLen >= 3 && cmd[1] == ':') {
    uint8_t nd = (c0 == 'F') ? 1 : 2;
    int lv = atoi(cmd + 2);

    DBGF("[CMD] %c:%d cur_dir=%d actualPWM=%d motor=%s",
         c0, lv, (int)actualDir, (int)actualPWM, motorStr());

    if (lv < 0 || lv > 8) return;

    if (lv == 0) {
      if (actualPWM > 0 && actualDir != 0 && actualDir != nd) {
        sendError("STOP_FIRST");
        return;
      }
      targetDir   = nd;
      targetLevel = 0;
      targetPWM   = 0;
      if (actualPWM > 0) {
        motorState = STATE_RAMPING;
        lastRampTime = millis();
      }
      DBGF("[CMD] %c:0 dir=%d selected, motor unchanged", c0, nd);
      statusPushRequested = true;
      return;
    }

    if (actualPWM > 0 && actualDir != 0 && actualDir != nd) {
      sendError("STOP_FIRST");
      return;
    }
    targetDir   = nd;
    targetLevel = lv;
    targetPWM   = levelToPWM(lv);
    if (actualPWM == 0) startMotor(nd);
    else { motorState = STATE_RAMPING; lastRampTime = millis(); }
    statusPushRequested = true;
    return;
  }

  // ---- CP ----
  if (strcmp(cmd,"CP") == 0) {
    if (roleState != ROLE_STANDALONE) { sendError("ALREADY_COUPLED"); return; }
    if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }

    // ★ v1.6: 发邀请前重新固定WiFi信道
    ensureWifiChannel();

    roleState = ROLE_INVITING;
    inviteStartTime = millis(); lastInviteTime = 0;
    uint8_t bc[6]; memset(bc, 0xFF, 6);
    addEspNowPeer(bc);
    statusPushRequested = true;

    DBGF("[COUPLE] Inviting started, channel fixed to %d", ESPNOW_CHANNEL);
    return;
  }
  if (strcmp(cmd,"CP:STOP") == 0) {
    if (roleState == ROLE_INVITING) {
      roleState = ROLE_STANDALONE;
      statusPushRequested = true;
      DBG("[COUPLE] Inviting stopped by user");
    }
    return;
  }

  // ---- J ----
  if (c0 == 'J' && cmdLen >= 3 && cmd[1] == ':') {
    if (roleState != ROLE_INVITED) { sendError("NOT_INVITED"); return; }
    if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
    char end = cmd[2];
    if (end != 'A' && end != 'B') return;
    slaveCoupleEnd = end;

    // ★ v1.6: 接受前确保信道正确
    ensureWifiChannel();

    sendAcceptPkt(inviterMAC, end);
    enterSlave(inviterMAC);
    statusPushRequested = true;
    DBGF("[COUPLE] Accepted invite, end=%c", end);
    return;
  }

  // ---- U ----
  if (strcmp(cmd,"U") == 0) {
    if (roleState != ROLE_MASTER) { sendError("NOT_COUPLED"); return; }
    if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
    if (slaveActualPWM > 0) { sendError("STOP_FIRST"); return; }
    sendUncouplePkt();
    uncoupleRetryLeft = UNCOUPLE_RETRY_COUNT;
    lastUncoupleTime = millis();
    statusPushRequested = true;
    return;
  }

  // ---- K ----
  if (c0 == 'K' && cmdLen >= 3 && cmd[1] == ':') {
    if (roleState != ROLE_MASTER) { sendError("NOT_COUPLED"); return; }
    float k = atof(cmd + 2);
    if (k < 0.90f || k > 1.10f) { sendError("INVALID_COEFF"); return; }
    speedCoeff = k;
    statusPushRequested = true;
    return;
  }

  DBGF("[CMD] unknown: '%s'", cmd);
}

// ============================================================================
// 电机状态机
// ============================================================================

void motorStateMachine() {
  unsigned long now = millis();

  switch (motorState) {
  case STATE_IDLE:
    if (demoState == DEMO_EXITING && actualPWM == 0) {
      if (roleState == ROLE_INVITED) {
        sendAcceptPkt(inviterMAC, slaveCoupleEnd);
        enterSlave(inviterMAC);
        demoState = DEMO_OFF;
        statusPushRequested = true;
      } else {
        demoState = DEMO_OFF;
        actualDir = 0;
      }
    }
    break;

  case STATE_KICK:
    if (now - kickStartTime >= KICK_TIME) {
      if (targetPWM == 0) {
        actualPWM = KICK_PWM;
      } else if (targetPWM >= KICK_PWM) {
        actualPWM = targetPWM;
        applyMotorPWM(actualDir, actualPWM);
        motorState = STATE_RUNNING;
        break;
      } else {
        actualPWM = KICK_PWM;
      }
      motorState = STATE_RAMPING;
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
        else actualPWM -= RAMP_STEP;
        if (actualPWM > 0 && actualPWM < MIN_PWM) actualPWM = 0;
      }
      if (actualPWM == 0) {
        applyMotorPWM(0, 0);
        actualDir = 0;
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
      motorState = STATE_RAMPING;
      lastRampTime = millis();
    }
    break;
  }
}

// ============================================================================
// 演示
// ============================================================================

void demoStateMachine() {
  if (demoState != DEMO_WAITING) return;
  if (deviceConnected) { demoState = DEMO_OFF; return; }
  if (millis() - bootTime < DEMO_WAIT_TIME) return;
  demoState = DEMO_RUNNING; soundEnabled = true;
  targetDir = DEMO_DIR; targetLevel = DEMO_LEVEL; targetPWM = levelToPWM(DEMO_LEVEL);
  startMotor(DEMO_DIR);
  updateSound();
  DBG("[DEMO] Demo started");
}

// ============================================================================
// 重联任务
// ============================================================================

void couplingTasks() {
  unsigned long now = millis();

  if (roleState == ROLE_INVITING) {
    if (now - inviteStartTime >= ESPNOW_INVITE_TIMEOUT) {
      roleState = ROLE_STANDALONE;
      statusPushRequested = true;
      DBG("[COUPLE] Invite timeout, back to STANDALONE");
      return;
    }
    if (now - lastInviteTime >= ESPNOW_INVITE_INTERVAL) {
      lastInviteTime = now;
      sendInviteBroadcast();
    }
  }

  if (roleState == ROLE_SLAVE && now - lastSlaveCmd >= SLAVE_CMD_TIMEOUT) {
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
    DBG("[COUPLE] Slave cmd timeout, exiting");
    exitCoupling();
    statusPushRequested = true;
    return;
  }

  if (roleState == ROLE_MASTER) {
    unsigned long el = now - lastSlaveStatus;
    if (el >= MASTER_STATUS_TIMEOUT) {
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
      DBG("[COUPLE] Slave status timeout, exiting");
      exitCoupling();
      statusPushRequested = true;
      return;
    }
    if (el >= MASTER_STATUS_WARN && !slaveStatusWarn) {
      slaveStatusWarn = true;
      DBG("[COUPLE] Slave status warning");
    }
  }

  if (roleState == ROLE_MASTER && now - lastCmdSendTime >= ESPNOW_CMD_INTERVAL) {
    lastCmdSendTime = now;
    sendCmdToSlave();
  }

  if (roleState == ROLE_SLAVE && now - lastStatusSendTime >= ESPNOW_STATUS_INTERVAL) {
    lastStatusSendTime = now;
    sendStatusToMaster();
  }

  if (roleState == ROLE_MASTER && uncoupleRetryLeft > 0) {
    if (now - lastUncoupleTime >= UNCOUPLE_RETRY_INTERVAL) {
      lastUncoupleTime = now;
      sendUncouplePkt();
      uncoupleRetryLeft--;
      if (uncoupleRetryLeft == 0) {
        DBG("[COUPLE] Uncouple retries exhausted, force exit");
        exitCoupling();
        statusPushRequested = true;
      }
    }
  }
}

// ============================================================================
// 自检
// ============================================================================

void selfTest() {
  DBG("[BOOT] Self-test starting...");
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_A_WHITE, HIGH); digitalWrite(LED_B_WHITE, HIGH);
    digitalWrite(LED_A_RED, HIGH);   digitalWrite(LED_B_RED, HIGH);
    delay(200);
    digitalWrite(LED_A_WHITE, LOW);  digitalWrite(LED_B_WHITE, LOW);
    digitalWrite(LED_A_RED, LOW);    digitalWrite(LED_B_RED, LOW);
    delay(200);
  }
  cabAtEndA = true;  headlightOn = true;  updateLights(); delay(500);
  cabAtEndA = false; headlightOn = true;  updateLights(); delay(500);
  digitalWrite(SOUND_POWER, HIGH); delay(500); digitalWrite(SOUND_POWER, LOW);
  cabAtEndA = true; headlightOn = false; soundEnabled = false;
  updateLights(); updateSound();
  DBG("[BOOT] Self-test complete");
}

// ============================================================================
// setup
// ============================================================================

void setup() {
  DBG_INIT(115200);
  delay(100);
  DBGF("[BOOT] BLE Train v%s", FIRMWARE_VERSION);

  esp_task_wdt_init(15, true);
  esp_task_wdt_add(NULL);

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

  selfTest();

  // ---- WiFi / ESP-NOW ----
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE);
  esp_read_mac(myMAC, ESP_MAC_WIFI_STA);
  DBGF("[BOOT] MAC: %02X:%02X:%02X:%02X:%02X:%02X",
    myMAC[0], myMAC[1], myMAC[2], myMAC[3], myMAC[4], myMAC[5]);

  // ★ v1.6: 验证WiFi信道设置成功
  {
    uint8_t primary;
    wifi_second_chan_t second;
    esp_wifi_get_channel(&primary, &second);
    DBGF("[BOOT] WiFi channel: %d (expected %d)", primary, ESPNOW_CHANNEL);
  }

  if (esp_now_init() != ESP_OK) {
    DBG("[BOOT] ESP-NOW init FAILED!");
  } else {
    DBG("[BOOT] ESP-NOW init OK");
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_register_send_cb(onEspNowSent);

  // ---- BLE ----
  BLEDevice::init("BLE_Train");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(&serverCbInstance);

  BLEService* svc = pServer->createService(SERVICE_UUID);

  pCtrlChar = svc->createCharacteristic(CHAR_CTRL_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pCtrlChar->setCallbacks(&ctrlCbInstance);

  pStatusChar = svc->createCharacteristic(CHAR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());

  BLECharacteristic* pVerChar = svc->createCharacteristic(CHAR_VERSION_UUID,
    BLECharacteristic::PROPERTY_READ);
  char verBuf[48];
  snprintf(verBuf, sizeof(verBuf), "FW:%s %s %s", FIRMWARE_VERSION, __DATE__, __TIME__);
  pVerChar->setValue(verBuf);

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

// ============================================================================
// loop
// ============================================================================

void loop() {
  unsigned long now = millis();

  esp_task_wdt_reset();
  loopCounter++;

  #if DEBUG_ENABLED
  if (now - lastLoopReport >= 5000) {
    unsigned long elapsed = now - lastLoopReport;
    uint32_t rate = (elapsed > 0) ? (loopCounter * 1000 / elapsed) : 0;
    DBGF("[PERF] %lu/s heap=%lu motor=%s pwm=%d/%d dir=%d/%d role=%s",
         (unsigned long)rate, (unsigned long)esp_get_free_heap_size(),
         motorStr(), (int)actualPWM, (int)targetPWM,
         (int)actualDir, (int)targetDir, roleStr());

    // ★ v1.6: ESP-NOW 统计
    if (espnowTxCount > 0 || espnowRxCount > 0) {
      DBGF("[ESPNOW] stats: tx=%d txFail=%d rx=%d delivFail=%d",
           espnowTxCount, espnowTxFail, espnowRxCount, espnowDelivFail);
    }

    loopCounter = 0;
    lastLoopReport = now;
  }
  #endif

  // ---- BLE 连接 ----
  if (bleJustConnected) {
    bleJustConnected = false;
    bleDisconnectTime = 0;
    if (demoState == DEMO_WAITING) demoState = DEMO_OFF;
    else if (demoState == DEMO_RUNNING) {
      demoState = DEMO_EXITING; soundEnabled = false;
      targetDir = targetLevel = targetPWM = 0;
      if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
      updateSound();
    }
    lastStatusBuf[0] = '\0';
    statusPushRequested = true;
  }

  // ---- BLE 断连防抖 ----
  if (bleJustDisconnected) {
    bleJustDisconnected = false;
    bleDisconnectTime = now;
  }
  if (bleDisconnectTime > 0 && !deviceConnected &&
      now - bleDisconnectTime >= BLE_DISCONNECT_GRACE) {
    bleDisconnectTime = 0;
    targetDir = targetLevel = targetPWM = 0;
    if (actualPWM > 0) { motorState = STATE_RAMPING; lastRampTime = now; }
  }
  if (bleDisconnectTime > 0 && deviceConnected) {
    bleDisconnectTime = 0;
  }

  if (wasConnected && !deviceConnected) pServer->startAdvertising();
  wasConnected = deviceConnected;

  // 处理命令
  processBleCmd();
  processEspNowRx();

  // 演示
  demoStateMachine();

  // 电机
  motorStateMachine();

  // ★ 音效 + PWM变化时触发上报
  if (actualPWM != prevActualPWM) {
    updateSound();
    prevActualPWM = actualPWM;
    statusPushRequested = true;
  }

  // 电池
  if (now - lastBattTime >= BATT_SAMPLE_INTERVAL) {
    lastBattTime = now;
    sampleBattery();
    statusPushRequested = true;
  }

  // ★ v1.6: 周期性检查WiFi信道 (防BLE连接导致漂移)
  if (now - lastChannelCheck >= WIFI_CHANNEL_CHECK_INTERVAL) {
    lastChannelCheck = now;
    ensureWifiChannel();
  }

  // 重联
  couplingTasks();

  // 错误推送
  if (errorPushPending && deviceConnected) {
    if (safeNotify(pStatusChar, errorPushBuf))
      errorPushPending = false;
  }

  // ★ 统一上报入口
  if (statusPushRequested && deviceConnected) {
    sendStatus();
    statusPushRequested = false;
  }

  delay(1);
}