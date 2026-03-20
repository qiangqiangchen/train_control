

# 🚂 BLE 遥控火车 — 终极开发全案（含双机重联）

## 一、项目概述

将带音效的玩具火车改装为 BLE 蓝牙遥控，模拟**真实铁路机车**的操控逻辑，并支持**ESP-NOW 双机重联运行**：

- 灯光跟随"驾驶端"而非行驶方向
- 8档油门分级控制（PWM 160~255）
- 原车音效可手动开关，开启后随油门自动播放/静音
- **非阻塞状态机**驱动所有电机变速/停车
- 运行中禁止换向和换端，平滑减速保护齿轮
- 开机20秒无BLE连接自动进入演示模式
- **电池电压实时监测**
- **ESP-NOW 双机重联**：本务机+补机协同运行

---

## 二、硬件清单

| 配件 | 数量 | 用途 |
|------|------|------|

| ESP32-C3 Super Mini | 1 | 主控（BLE + ESP-NOW） |
| DRV8833 | 1 | 电机驱动 |
| 2N7002 SOT-23 | **5** | Q1~Q4灯光 + Q5原车PCB供电 |
| 5mm 白色LED | 2 | A/B端车头灯 |
| 3mm 红白共阳双色LED | 4 | A/B端各2个 |
| 130马达 | 1 | 原车电机（ESP32接管） |
| 3×AA 电池盒 | 1 | 4.5V供电 |
| 100Ω 电阻 | 6 | 白灯限流 |
| 150Ω 电阻 | 4 | 红灯限流 |
| 10kΩ 电阻 | **5** | Q1~Q5 栅极下拉 |
| 100kΩ 电阻 | **2** | 电池电压分压器 |
| 0.1µF 瓷片电容 | 2 | 电机端子滤波 |
| 100µF 电解电容 | 1 | 电源滤波 |

---

## 三、GPIO 分配
 
| GPIO | 功能 | 外接目标 |
|------|------|---------|
| GPIO0 | BATT_ADC | 电池分压采样（100k+100k） |
| GPIO2 | MOTOR_IN1 | DRV8833 AIN1 |
| GPIO3 | MOTOR_IN2 | DRV8833 AIN2 |
| GPIO4 | LED_A_WHITE | Q1 Gate → A端白灯组 |
| GPIO5 | LED_B_WHITE | Q2 Gate → B端白灯组 |
| GPIO6 | LED_A_RED | Q3 Gate → A端红灯组 |
| GPIO7 | LED_B_RED | Q4 Gate → B端红灯组 |
| GPIO8 | SOUND_POWER | Q5 Gate → 原车PCB GND通断 |

---

## 四、接线总图

```
          【End A 灯组】                             【End B 灯组】
        ┌──────────────┐                          ┌──────────────┐
 VCC ─┬─┤ 5mm白LED(+)  │                          │  5mm白LED(+) ├─┬─ VCC
      │ │              │        车身走线          │              │ │
      │ │[双色①][双色②]│   ←── 3根线/端 ──→       │[双色③][双色④]│ │
      │ └──┬───┬───────┘                          └───┬───┬──────┘ │
      │    │   │                                      │   │        │
      │ A_White A_Red                             B_White B_Red    │
      │    │   │                                      │   │        │
      │    │   │       ┌──────────────────┐           │   │        │
      │    │   └───────┤ Q3 D(G6) Q4 D(G7)├───────────┘   │        │
      │    └───────────┤ Q1 D(G4) Q2 D(G5)├───────────────┘        │
      │                │  所有 Source→GND │                        │
      │                └────────┬─────────┘                        │
      │                         │                                  │
      │   VCC──[100kΩ]──┬──[100kΩ]──GND                            │
      │                 │                                          │
      │              GPIO0(ADC)                                    │
      │                         │                                  │
      │                ┌────────┴──────────┐                       │
      │                │    ESP32-C3       │       ┌────────────┐  │
      │                │                   │       │  原车PCB   │  │
      │                │ GPIO8 ────────────┼──Q5──→┤ GND(剪断)  │  │
      │                │                   │       │ 音频→喇叭  │  │
      │                │ GPIO2 ──┐         │       │电机输出✂断│  │
      │                │ GPIO3 ──┤         │       └────────────┘  │
      │                └─────────┤─────────┘                       │
      │                          │                                 │
      │                ┌─────────┤─────────┐                       │
      │                │    DRV8833        │                       │
      │                │                   │         [0.1µF]       │
      │                │ AOUT1─────马达(+)──┤├── 马达(-)──AOUT2     │
      │                └─────────┬─────────┘                       │
      │                          │                                 │
 VCC──┤                     [100µF]        物理开关保持ON           │
 GND──┴──────────────────────────┘        (作为总电源开关)          │
```

### 原车改装要点

```
┌─────────────────────────────────────────────────────────┐
│  1. 断开: 原PCB → 电机 的两根线 (ESP32+DRV8833接管)     │
│  2. 断开: 原PCB → GND 的线 (插入Q5做开关)               │
│  3. 保留: 原PCB → 喇叭 (音源不动)                       │
│  4. 保留: 开关 → 原PCB VCC (开关拨ON就给整个系统供电)   │
│  5. 新增: Q5 Drain ← 原PCB GND断口                      │
│           Q5 Source → 公共GND (电池-)                   │
│           Q5 Gate → GPIO8 + 10kΩ下拉                    │
│  6. 新增: 电池分压器 VCC→100kΩ→GPIO0→100kΩ→GND          │
└─────────────────────────────────────────────────────────┘
```

---

## 五、功能需求

### 5.1 灯光控制（真实机车逻辑）

| 规则 | 说明 |
|------|------|
| R1 | 系统维护一个"驾驶端"变量（`cabAtEndA`），决定哪端是车头、哪端是车尾 |
| R2 | **车尾端**：红灯**恒亮**，白灯**灭** |
| R3 | **车头端**：红灯**灭**，白灯由司机手动控制（开/关） |
| R4 | 电机操作**不影响灯光** |
| R5 | 灯光只在三种情况下改变：①手动按灯光开关 ②换端操作 ③重联/解联 |

### 5.2 油门与电机控制

| 规则 | 说明 |
|------|------|
| T1 | 8档油门，档位1~8映射PWM 160~255（步进≈14），0档=停车 |
| T2 | 前进/后退的物理方向根据当前驾驶端自动翻转 |
| T3 | 从静止启动时，先全压255脉冲80ms（kickstart），再过渡到目标PWM |
| T4 | 运行中调整**同方向**档位，**非阻塞平滑坡道**过渡 |
| T5 | **运行中禁止换向**：拒绝执行，BLE通知 `ERR:STOP_FIRST` |
| T6 | **所有变速过程通过 `loop()` 状态机驱动** |

### 5.3 减速保护（非阻塞状态机）

| 规则 | 说明 |
|------|------|
| D1 | **所有减速**均走平滑坡道，由 `loop()` 逐步执行 |
| D2 | 坡道参数：每步降4 PWM，间隔20ms |
| D3 | 全速(255)→停：约480ms |
| D4 | PWM降至MIN_PWM(160)以下时直接归零 |
| D5 | 停稳后coast模式（双路PWM=0） |
| D6 | BLE回调中仅设置目标值，0ms阻塞 |

### 5.4 换向与换端（统一安全规则）

| 规则 | 说明 |
|------|------|
| C1 | 换向和换端都必须在**完全停稳**时执行（`targetPWM==0` 且 `actualPWM==0`） |
| C2 | 运行中收到换向/换端指令 → 拒绝，BLE通知 `ERR:STOP_FIRST` |
| C3 | 换端后：驾驶端翻转，车头灯**默认关** |
| C4 | **重联模式下换端**：整列换端，本务机和补机灯光同步更新 |

### 5.5 音效控制（手动开关 + 自动随动）

| 规则 | 说明 |
|------|------|
| S1 | Q5控制原车PCB供电 |
| S2 | 音效总开关（`soundEnabled`），默认**关闭** |
| S3 | **总开关=关**：始终断电静音 |
| S4 | **总开关=开**：`actualPWM>0`→通电播放，`actualPWM==0`→断电 |
| S5 | 切换立即生效 |
| S6 | **重联模式**：本务机M指令**同时控制两车**音效 |

### 5.6 电池电量监测

| 规则 | 说明 |
|------|------|
| V1 | GPIO0 通过100k+100k分压读取电池电压 |
| V2 | ADC采样：每5秒一次，10次滑动平均 |
| V3 | 电压映射：3.0V=0%，4.5V=100%，线性 |
| V4 | 状态回报中包含 `BAT:百分比` 和 `BATV:电压` |
| V5 | 适用于3×1.5V碱性电池和3×1.2V充电电池（均以4.5V为100%） |

### 5.7 BLE 通信

| 规则 | 说明 |
|------|------|
| B1 | 设备名称：`BLE_Train` |
| B2 | 控制特征：可写（Write + Write Without Response） |
| B3 | 状态特征：可读 + 可通知（Notify） |
| B4 | 每次执行指令后立即上报状态 |
| B5 | 每200ms周期上报一次状态 |
| B6 | BLE断连处理详见 5.12 |

### 5.8 演示模式

| 规则 | 说明 |
|------|------|
| DM1 | 开机后20秒无BLE连接自动进入演示 |
| DM2 | 20秒内BLE已连接则取消演示 |
| DM3 | 演示行为：音效开启，5档前进 |
| DM4 | 演示中BLE连接 → 平滑减速停车 → 正常待命 |
| DM5 | 演示中收到ESP-NOW重联邀请 → 退出演示 → 自动以**车头端**接受邀请 |
| DM6 | 退出演示后音效恢复关闭 |

### 5.9 开机行为

| 规则 | 说明 |
|------|------|
| P1 | 灯光自检：全灯闪烁3次 → 换端演示 |
| P2 | 音效自检：Q5通电500ms |
| P3 | 初始状态：驾驶端=A，车头灯=关，B端红灯亮，电机停，音效总开关=关 |

### 5.10 ESP-NOW 双机重联

#### 5.10.1 角色定义

| 角色 | 说明 |
|------|------|
| STANDALONE | 独立模式（默认），完全自主运行 |
| MASTER | 本务机，发起重联，控制整列 |
| SLAVE | 补机，执行本务机指令，App只读 |

#### 5.10.2 重联邀请与配对

| 规则 | 说明 |
|------|------|
| CP1 | 本务机通过BLE指令 `CP` 发起邀请，ESP-NOW广播邀请包（每500ms） |
| CP2 | 邀请包含本务机MAC和车尾端标识 |
| CP3 | 场内所有STANDALONE火车均可收到邀请 |
| CP4 | 收到邀请的火车通过BLE通知其App显示邀请弹窗 |
| CP5 | 补机App选择连接端（A或B）后发送 `J:A` 或 `J:B` |
| CP6 | 补机发送ESP-NOW应答包给本务机 |
| CP7 | 本务机收到应答→重联成功，停止广播 |
| CP8 | 邀请30秒无人应答自动取消 |
| CP9 | 可通过 `CP:STOP` 手动取消邀请 |
| CP10 | **演示模式中收到邀请**：自动退出演示，默认以车头端接受，本务机App可后续调整连接端 |

#### 5.10.3 重联运行

| 规则 | 说明 |
|------|------|
| CR1 | 本务机每100ms通过ESP-NOW下发指令包给补机 |
| CR2 | 指令包含：目标方向、目标PWM（已乘系数）、灯光状态、音效开关 |
| CR3 | 补机执行本务机指令，使用自身状态机完成加减速 |
| CR4 | 补机每200ms通过ESP-NOW回报状态给本务机 |
| CR5 | 本务机合并双车状态后通过BLE上报给App |
| CR6 | **补机App仅显示状态，不能操控** |
| CR7 | 补机收到的控制BLE指令（除灯光/音效外）→ 返回 `ERR:SLAVE_MODE` |

#### 5.10.4 重联方向映射

| 规则 | 说明 |
|------|------|
| CD1 | 补机连接端=A → 补机方向与本务机**相同** |
| CD2 | 补机连接端=B → 补机方向与本务机**相反** |
| CD3 | 本务机计算好补机的物理方向后下发，补机无需知道拓扑 |

#### 5.10.5 重联灯光

| 规则 | 说明 |
|------|------|
| CL1 | 重联后两车视为一个整体 |
| CL2 | 整列车头端（本务机驾驶端）：白灯可控，红灯灭 |
| CL3 | 整列车尾端（补机远端）：红灯亮，白灯灭 |
| CL4 | 两车连接处（本务机车尾端+补机连接端）：**全灭** |
| CL5 | 换端后灯光整体翻转 |
| CL6 | 灯光状态由本务机统一计算并下发 |

#### 5.10.6 速度系数

| 规则 | 说明 |
|------|------|
| CK1 | 范围0.90~1.10，步进0.01，默认1.00 |
| CK2 | 本务机App通过 `K:0.95` 设置 |
| CK3 | 补机实际PWM = 本务机targetPWM × 系数（四舍五入，钳位到0~255） |
| CK4 | 系数随时可调，运行中立即生效 |

#### 5.10.7 解联

| 规则 | 说明 |
|------|------|
| CU1 | **仅本务机**可发起解联（补机App不能） |
| CU2 | 解联前必须**完全停稳** |
| CU3 | 解联流程：本务机ESP-NOW发送解联包→补机确认→双方恢复STANDALONE |
| CU4 | 解联后两车各自恢复独立灯光逻辑 |
| CU5 | 解联后补机App恢复控制权 |

### 5.11 超时保护

| 场景 | 超时 | 行为 |
|------|------|------|
| 补机未收到本务机指令 | 300ms | 补机自动平滑减速停车 |
| 本务机未收到补机状态 | 1000ms | App显示"补机通信异常"警告 |
| 本务机未收到补机状态 | 3000ms | 自动解联，双车各自减速停车 |
| 邀请广播无应答 | 30秒 | 自动取消邀请 |

### 5.12 BLE断连处理

| 场景 | 行为 |
|------|------|
| **独立模式BLE断连** | 目标归零→平滑减速→音效关→重新广播 |
| **本务机BLE断连** | 目标归零→本务机平滑减速→ESP-NOW下发停车给补机→补机也减速→**保持重联关系**→等待重连 |
| **补机BLE断连** | 不影响运行（补机听从ESP-NOW指令），补机重新广播BLE等手机重连 |

---

## 六、BLE 协议

### 6.1 指令格式（App → 固件）

```
┌──────────────┬──────────────────────────────────────────────────┐
│  指令        │  功能                                            │
├──────────────┼──────────────────────────────────────────────────┤
│ F:1~F:8      │  前进，档位1~8 (运行中仅同向调速)                │
│ R:1~R:8      │  后退，档位1~8 (运行中仅同向调速)                │
│ S            │  停车（平滑减速）                                │
├──────────────┼──────────────────────────────────────────────────┤
│ L            │  车头灯切换 (关↔开)                              │
│ L:0          │  车头灯关                                        │
│ L:1          │  车头灯开                                        │
├──────────────┼──────────────────────────────────────────────────┤
│ M            │  音效总开关切换 (关↔开, 重联时同步两车)          │
│ M:0          │  音效总开关关                                    │
│ M:1          │  音效总开关开                                    │
├──────────────┼──────────────────────────────────────────────────┤
│ C            │  换端 (停车时, 重联时整列换端)                   │
├──────────────┼──────────────────────────────────────────────────┤
│ CP           │  发起重联邀请 (开始ESP-NOW广播)                  │
│ CP:STOP      │  取消重联邀请                                    │
│ J:A          │  接受邀请，A端连接 (补机端)                      │
│ J:B          │  接受邀请，B端连接 (补机端)                      │
│ U            │  解除重联 (本务机, 必须停车)                     │
│ K:0.95       │  设置补机速度系数 (0.90~1.10)                    │
└──────────────┴──────────────────────────────────────────────────┘
```

### 6.2 状态回报格式（固件 → App）

```
【独立模式】
"CAB:A HL:ON DIR:FWD LV:5 APWM:214 TPWM:228 SE:ON SND:ON DM:OFF BAT:78 BATV:4.12 CP:OFF"

【本务机模式】
"CAB:A HL:ON DIR:FWD LV:5 APWM:214 TPWM:228 SE:ON SND:ON DM:OFF BAT:78 BATV:4.12 CP:MASTER SC:A SAPWM:210 SBAT:65 SBATV:3.89 SK:0.95"

【补机模式】
"CAB:A HL:OFF DIR:FWD LV:5 APWM:210 TPWM:214 SE:ON SND:ON BAT:65 BATV:3.89 CP:SLAVE"

【邀请中】
"... CP:INVITING"

【收到邀请】
"... CP:INVITED INV:AA:BB:CC:DD:EE:FF"

【错误】
"ERR:STOP_FIRST"
"ERR:SLAVE_MODE"
"ERR:DEMO_STOPPING"
"ERR:ALREADY_COUPLED"
"ERR:NOT_COUPLED"
"ERR:INVALID_COEFF"

字段说明:
  CAB:A/B          当前驾驶端
  HL:ON/OFF        车头灯状态
  DIR:STOP/FWD/REV 物理运行方向
  LV:0~8           目标档位
  APWM:0~255       实际PWM
  TPWM:0~255       目标PWM
  SE:ON/OFF        音效总开关
  SND:ON/OFF       音效实际播放
  DM:ON/OFF        演示模式
  BAT:0~100        电池百分比
  BATV:x.xx        电池电压(V)
  CP:OFF/INVITING/INVITED/MASTER/SLAVE  重联状态
  INV:MAC          邀请来源MAC (仅INVITED状态)
  SC:A/B           补机连接端 (仅MASTER)
  SAPWM:0~255      补机实际PWM (仅MASTER)
  SBAT:0~100       补机电量 (仅MASTER)
  SBATV:x.xx       补机电压 (仅MASTER)
  SK:0.90~1.10     速度系数 (仅MASTER)
```

### 6.3 App 解析逻辑

```
收到状态 →
├─ 以 "ERR:" 开头 → Toast提示错误信息
├─ CP:SLAVE → 切换为补机只读界面
│   ├─ 禁用所有控制按钮
│   ├─ 显示速度/灯光/电量信息
│   └─ 显示"操控权已移交本务机"提示
├─ CP:MASTER → 切换为本务机控制界面
│   ├─ 显示补机状态区 (SAPWM/SBAT/SBATV)
│   ├─ 显示速度系数滑块
│   └─ 启用解联按钮
├─ CP:INVITED → 弹窗显示重联邀请
│   └─ 提供 [A端连接] [B端连接] [拒绝] 按钮
├─ CP:INVITING → 显示"邀请中..."状态
├─ DM:ON → 显示"演示模式运行中"
├─ APWM==0 且 TPWM==0 → 换端/换向按钮可用
├─ APWM>0 或 TPWM>0 → 换端/换向按钮置灰
├─ BAT/BATV → 更新电量显示
└─ (其余字段同前)
```

---

## 七、UI 界面设计（横屏）

### 7.1 独立模式 / 本务机控制界面

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  🔵 BLE_Train [已连接]              🔋78% 4.12V                独立模式         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                             │                                                   │
│   ┌─────────────────────┐   │  ┌───────────────────────────────────────────┐    │
│   │                     │   │  │  油门  [1] [2] [3] [4] [5] [6] [7] [8]    │    │
│   │    ▲ 前 进          │   │  │  🐢───────────────●─────────────→🐇      │    │
│   │                     │   │  │                                           │    │
│   │    ■ 空 档          │   │  │  速度  ██████████████████░░░  228/228     │    │
│   │                     │   │  │                                           │    │
│   │    ▼ 后 退          │   │  ├───────────────────────────────────────────┤    │
│   │                     │   │  │  驾驶端: [A]    方向: 前进                │    │
│   └─────────────────────┘   │  │  灯光:   亮     音效: ON🔊                │    │
│                             │  │                                           │    │
│   ┌──────┐ ┌──────┐ ┌──────┐│  │  补机: 未连接                             │    │
│   │  💡  │ │  🔊  │ │  🔄  │ │  │                                           │    │
│   │ 灯光 │ │ 音效 │ │ 换端 ││  └───────────────────────────────────────────┘    │
│   └──────┘ └──────┘ └──────┘│                                                   │
│   ┌──────┐ ┌──────┐        │            ┌─────────────────────┐                 │
│   │  🔗  │ │  🛑  │         │            │    🛑 紧急停车      │                 │
│   │ 重联 │ │ 解联 │        │            └─────────────────────┘                 │
│   └──────┘ └──────┘        │                                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 本务机重联模式界面

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  🔵 BLE_Train [已连接]              🔋78% 4.12V              🔗 本务机模式       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                             │                                                   │
│   ┌─────────────────────┐   │  ┌───────────────────────────────────────────┐    │
│   │                     │   │  │  油门  [1] [2] [3] [4] [5] [6] [7] [8]    │    │
│   │    ▲ 前 进          │   │  │  🐢───────────────●─────────────→🐇        │    │
│   │                     │   │  │                                           │    │
│   │    ■ 空 档          │   │  │  本车速度  ████████████████░░░  228/228   │    │
│   │                     │   │  │  补机速度  ███████████████░░░░  210/214   │    │
│   │    ▼ 后 退          │   │  │                                           │    │
│   │                     │   │  ├───────────────────────────────────────────┤    │
│   └─────────────────────┘   │  │  驾驶端: [A]    方向: 前进                │    │
│                             │  │  灯光:   亮     音效: ON 🔊               │    │
│   ┌──────┐ ┌──────┐ ┌──────┐│  ├───────────────────────────────────────────┤    │
│   │  💡  │  │  🔊  │ │  🔄  ││  │  🔗 补机: 已连接 (A端)  🔋65% 3.89V        │    │
│   │ 灯光 │ │ 音效 │ │ 换端 ││  │  速度系数: 0.90 ─────●── 1.00 ──── 1.10   │    │
│   └──────┘ └──────┘ └──────┘│  │              [◀ 0.01] [0.01 ▶]            │    │
│   ┌──────┐ ┌──────┐         │  └───────────────────────────────────────────┘    │
│   │  🔗  │  │  🛑  │         │            ┌─────────────────────┐                │
│   │[灰]  │ │ 解联 │         │            │    🛑 紧急停车      │                │
│   └──────┘ └──────┘         │            └─────────────────────┘                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 补机只读界面

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  🔵 BLE_Train [已连接]              🔋65% 3.89V              🔗 补机模式         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                         │   │
│   │                 🚂  重联运行中 — 本务机控制                             │   │
│   │                                                                         │   │
│   │   方向: 前进                档位: 6                                     │   │
│   │   速度: ███████████████░░░░   APWM: 210 / TPWM: 214                     │   │
│   │   速度系数: ×0.95                                                       │   │
│   │                                                                         │   │
│   │   灯光: A端 [灭]  B端 [红灯亮]                                          │   │
│   │   音效: 开启 🔊                                                         │   │
│   │                                                                         │   │
│   │   本务机: 🔋78% 4.12V        补机(本车): 🔋65% 3.89V                     │   │
│   │                                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│           ⚠️  所有操控权限已移交本务机，如需操作请使用本务机控制端              │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.4 重联邀请弹窗（补机端）

```
┌────────────────────────────────────────────┐
│                                            │
│    📡 收到重联邀请                         │
│                                            │
│    来自: AA:BB:CC:DD:EE:FF                 │
│    信号强度: -45 dBm (很近)                │
│                                            │
│    选择本车连接端:                         │
│                                            │
│    ┌─────────────────┐                     │
│    │  🔵 A端(车头)连接 │  ← 推荐           │
│    └─────────────────┘                     │
│    ┌─────────────────┐                     │
│    │  🔵 B端(车尾)连接 │                   │
│    └─────────────────┘                     │
│    ┌─────────────────┐                     │
│    │  ❌ 拒绝          │                    │
│    └─────────────────┘                     │
│                                            │
└────────────────────────────────────────────┘
```

---

## 八、ESP-NOW 协议

### 8.1 数据包结构

```cpp
// 通用包头
struct __attribute__((packed)) EspNowPacket {
  uint8_t type;       // 包类型
  uint8_t payload[24]; // 载荷
};

// 包类型
#define PKT_INVITE       0x01  // 邀请广播 (本务→广播)
#define PKT_ACCEPT       0x02  // 接受邀请 (补机→本务)
#define PKT_CMD          0x10  // 运行指令 (本务→补机, 100ms)
#define PKT_STATUS       0x11  // 状态回报 (补机→本务, 200ms)
#define PKT_UNCOUPLE     0x20  // 解联指令 (本务→补机)
#define PKT_UNCOUPLE_ACK 0x21  // 解联确认 (补机→本务)
```

### 8.2 各包载荷定义

```cpp
// 邀请包 (PKT_INVITE, 广播发送, 每500ms)
struct __attribute__((packed)) InvitePayload {
  uint8_t masterMAC[6];    // 本务机MAC
  uint8_t masterTailEnd;   // 本务机车尾端 'A'/'B'
};

// 接受包 (PKT_ACCEPT, 单播给本务机)
struct __attribute__((packed)) AcceptPayload {
  uint8_t slaveMAC[6];     // 补机MAC
  uint8_t slaveCoupleEnd;  // 补机连接端 'A'/'B'
};

// 运行指令包 (PKT_CMD, 单播给补机, 每100ms)
struct __attribute__((packed)) CmdPayload {
  uint8_t  targetDir;      // 补机物理方向 0/1/2 (已经过本务机映射)
  uint8_t  targetPWM;      // 补机目标PWM (已乘系数, 0~255)
  uint8_t  lightEndA;      // 补机A端灯光 0=全灭 1=白灯 2=红灯
  uint8_t  lightEndB;      // 补机B端灯光 0=全灭 1=白灯 2=红灯
  uint8_t  headlightOn;    // 补机白灯开关 (整列车头端)
  uint8_t  soundEnabled;   // 音效开关
  uint8_t  seqNum;         // 序列号
};

// 状态回报包 (PKT_STATUS, 单播给本务机, 每200ms)
struct __attribute__((packed)) StatusPayload {
  uint8_t  actualPWM;      // 补机实际PWM
  uint8_t  batteryPct;     // 补机电量百分比
  uint16_t batteryMV;      // 补机电压(毫伏)
};

// 解联包 (PKT_UNCOUPLE, 无载荷)
// 解联确认包 (PKT_UNCOUPLE_ACK, 无载荷)
```

---

## 九、重联灯光逻辑详解

### 9.1 拓扑与灯光映射

```
【物理连接规则】
  本务机车尾端 ═══ 补机连接端
  (cabAtEndA=true时车尾=B端, false时车尾=A端)

【示例：cabAtEndA=true, slaveCoupleEnd=A】

  整列拓扑:
  [本务A]───本务机───[本务B]═══[补机A]───补机───[补机B]
   车头                连接处    连接处              车尾
   
  灯光:
   本务A: 白灯(可控), 红灯灭    ← 整列车头
   本务B: 全灭                  ← 连接处
   补机A: 全灭                  ← 连接处
   补机B: 红灯亮, 白灯灭        ← 整列车尾

【换端后：cabAtEndA=false, slaveCoupleEnd=A】

  整列拓扑 (反向):
  [补机B]───补机───[补机A]═══[本务B]───本务机───[本务A]
   车头               连接处   连接处               车尾

  灯光:
   补机B: 白灯(可控), 红灯灭    ← 整列车头
   补机A: 全灭                  ← 连接处
   本务B: 全灭                  ← 连接处
   本务A: 红灯亮, 白灯灭        ← 整列车尾
```

### 9.2 灯光计算算法

```
输入: cabAtEndA, slaveCoupleEnd, headlightOn

1. 确定本务机车尾端:
   masterTailEnd = cabAtEndA ? 'B' : 'A'

2. 确定整列4个端的角色:
   整列车头 = 本务机驾驶端 (cabAtEndA?A:B)
   整列车尾 = 补机远端 (slaveCoupleEnd=='A'?'B':'A')
   连接处1 = masterTailEnd
   连接处2 = slaveCoupleEnd

3. 灯光分配:
   整列车头: 白灯=headlightOn, 红灯=OFF
   整列车尾: 白灯=OFF, 红灯=ON
   连接处1: 白灯=OFF, 红灯=OFF (全灭)
   连接处2: 白灯=OFF, 红灯=OFF (全灭)

4. 将本务机2端的灯光本地执行
5. 将补机2端的灯光通过ESP-NOW下发
```

---

## 十、状态机总览

### 10.1 火车角色状态机

```
                      ┌────────────┐
           开机 ──→   │ STANDALONE │ ←───── 解联成功
                      │   (独立)   │ ←───── 邀请超时
                      └──┬─────┬───┘ ←───── 补机超时
                         │     │
                [CP]     │     │  [收到INVITE]
                         ▼     ▼
              ┌───────────┐   ┌───────────┐
              │ INVITING  │   │  INVITED  │
              │ (邀请中)   │   │ (被邀请)  │
              └─────┬─────┘   └─────┬─────┘
                    │ [收到ACCEPT]  │ [J:A/J:B]
                    ▼               ▼
              ┌───────────┐   ┌───────────┐
              │  MASTER   │   │   SLAVE   │
              │ (本务机)   │   │  (补机)   │
              └───────────┘   └───────────┘
```

### 10.2 演示模式与重联的交互

```
┌──────────┐     20秒无BLE     ┌──────────┐
│  DEMO    │ ←──────────────── │  DEMO    │
│ WAITING  │                   │ RUNNING  │
└────┬─────┘                   └────┬─────┘
     │                              │
     │ BLE连接                      │ BLE连接
     ▼                              ▼
 STANDALONE                    平滑减速→STANDALONE
     │                              │
     │                              │ 收到INVITE
     │                              ▼
     │                         退出演示→自动以车头端接受
     │                         (本务机App可后续调整)
     │                              │
     │                              ▼
     │                           SLAVE
```

---

## 十一、行为时序图

### 11.1 非阻塞架构（不变）

```
  onWrite("S") → targetPWM=0 → return     ← <1ms ✅
  loop()  每20ms: APWM: 255→251→247→...→0
  BLE协议栈全程畅通 ✅
```

### 11.2 完整单机操作场景（含电量）

```
时间 → → → → → → → → → → → → → → → → → → → → → → →

操作: [连接] [M:1] [L:1] [F:2]     [F:6]     [S]      [C]   [L:1] [F:3]
       │      │     │     │          │         │         │      │     │
上报:  ...BAT:78 BATV:4.12 CP:OFF...  (每条状态都含电量和重联状态)
```

### 11.3 重联配对时序

```
本务机App      本务机ESP32            补机ESP32           补机App
    │              │                     │                   │
  [CP]───────→     │                     │                   │
    │              ├─ roleState=INVITING │                   │
    │              ├─ ESP-NOW广播邀请    │                   │
    │              │  (每500ms) ────────→│                   │
    │              │                     ├─ 收到邀请         │
    │              │                     ├─ 检查:STANDALONE? │
    │              │                     ├─ BLE通知:         │
    │              │                     │  "...CP:INVITED   │
    │              │                     │   INV:AA:BB:..."  │
    │              │                     │ ─────────────────→│
    │              │                     │                   ├─弹窗
    │              │                     │                   │ [A端] [B端]
    │              │                     │                   │
    │              │                     │  ←──── "J:A" ─────┤
    │              │                     ├─ ESP-NOW单播:     │
    │              │                     │  ACCEPT(MAC,A端)  │
    │              │   ←─────────────────┤                   │
    │              ├─ 收到ACCEPT         │                   │
    │              ├─ 停止广播           │                   │
    │              ├─ roleState=MASTER   │                   │
    │              ├─ 计算灯光           │                   │
    │              ├─ 开始CMD周期        │                   │
    │    ←──"...CP:MASTER SC:A..."       │  "...CP:SLAVE"───→│
    │              │                     │                   ├─ 切换只读UI
```

### 11.4 重联运行时序

```
每100ms:
本务机 ──ESP-NOW──→ 补机
  CMD{dir=1, pwm=210, lightA=0, lightB=2, snd=1, seq=42}

每200ms:
补机 ──ESP-NOW──→ 本务机
  STATUS{apwm=208, bat=65, batMV=3890}

每200ms:
本务机 ──BLE──→ 手机A
  "CAB:A HL:ON DIR:FWD LV:6 APWM:228 TPWM:228 SE:ON SND:ON DM:OFF BAT:78 BATV:4.12 CP:MASTER SC:A SAPWM:208 SBAT:65 SBATV:3.89 SK:0.95"

补机 ──BLE──→ 手机B
  "CAB:A HL:OFF DIR:FWD LV:6 APWM:208 TPWM:210 SE:ON SND:ON BAT:65 BATV:3.89 CP:SLAVE"
```

### 11.5 重联换端时序

```
当前: cabAtEndA=true, slaveCoupleEnd=A
  拓扑: [本务A:头]──[本务B:连]═══[补机A:连]──[补机B:尾]

  [C] (必须停稳)
    │
    ├─ cabAtEndA = false
    ├─ headlightOn = false
    ├─ 重新计算灯光:
    │    本务A: 红灯亮 (新车尾)
    │    本务B: 全灭 (连接处)
    │    补机A: 全灭 (连接处)
    │    补机B: 白灯(关), 红灯灭 (新车头)
    ├─ 本地更新本务机灯光
    ├─ ESP-NOW下发补机灯光
    │
  新拓扑: [补机B:头]──[补机A:连]═══[本务B:连]──[本务A:尾]

  [L:1]
    │
    ├─ headlightOn = true
    ├─ 补机B端白灯亮 (通过ESP-NOW下发)
```

### 11.6 重联停车与解联时序

```
  [S] ─────→ 本务机targetPWM=0
              │
              ├─ 本务机状态机减速: 228→224→...→0
              ├─ 同时ESP-NOW: CMD{dir=0, pwm=0} 
              ├─ 补机也减速: 210→206→...→0
              │
              ├─ 双车停稳
              │
  [U] ─────→ 检查停稳 ✅
              │
              ├─ ESP-NOW: UNCOUPLE
              │          ──────→ 补机收到
              │                   ├─ roleState=STANDALONE
              │                   ├─ 恢复独立灯光
              │  ←── UNCOUPLE_ACK ┤
              │                   └─ BLE通知: "...CP:OFF"
              ├─ roleState=STANDALONE
              ├─ 恢复独立灯光
              └─ BLE通知: "...CP:OFF"
```

### 11.7 演示中收到重联邀请

```
  [演示运行中: F:5, APWM=214]
              │
              ├─ 收到ESP-NOW邀请包
              ├─ 退出演示: targetPWM=0, 减速
              ├─ 减速中...  APWM: 214→210→...→0
              │
              ├─ 停稳后
              ├─ 自动发送ACCEPT(车头端=A)
              ├─ roleState=SLAVE
              ├─ 等待本务机CMD指令
              │
  本务机App可后续通过界面调整补机连接端
  (需先解联→重新配对, 或预留ESP-NOW端调整指令)
```

### 11.8 补机超时保护

```
补机正常运行:  CMD ─100ms─ CMD ─100ms─ CMD ─100ms─ CMD
                                                      │
                                              (本务机断电)
                                                      │
              ···300ms无CMD···
                    │
              补机自动: targetPWM=0
              减速: APWM→...→0
              roleState=STANDALONE
              恢复独立灯光
              BLE通知: "...CP:OFF"
```

### 11.9 本务机BLE断连（重联中）

```
  [本务机BLE断连]
       │
       ├─ 本务机: targetPWM=0 (减速)
       ├─ ESP-NOW继续发CMD{dir=0, pwm=0} (减速指令)
       ├─ 补机也减速
       ├─ 双车停稳
       ├─ ★保持重联关系★ (不解联)
       ├─ 本务机重新广播BLE
       │
  [手机A重连]
       ├─ 上报当前状态 (CP:MASTER, 双车停稳)
       ├─ 可继续操作
```

---

## 十二、油门档位速查

```
档位:    0     1     2     3     4     5     6     7     8
PWM:     0    160   174   187   201   214   228   241   255

补机PWM (系数0.95):
         0    152   165   178   191   203   217   229   242

补机PWM (系数1.05):
         0    168   183   196   211   225   239   253   255(钳位)

停车耗时 (全速→停): ≈480ms (24步×20ms)
```

---

## 十三、完整代码

```cpp
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_now.h>
#include <WiFi.h>
#include <esp_wifi.h>

// ==================== 引脚定义 ====================
#define BATT_ADC     0
#define MOTOR_IN1    2
#define MOTOR_IN2    3
#define LED_A_WHITE  4
#define LED_B_WHITE  5
#define LED_A_RED    6
#define LED_B_RED    7
#define SOUND_POWER  8

// ==================== 电机参数 ====================
#define MIN_PWM         160
#define MAX_PWM         255
#define THROTTLE_STEPS  8
#define KICK_PWM        255
#define KICK_TIME       80
#define RAMP_STEP       4
#define RAMP_INTERVAL   20

// ==================== 演示模式参数 ====================
#define DEMO_WAIT_TIME  20000
#define DEMO_LEVEL      5
#define DEMO_DIR        1

// ==================== 电池参数 ====================
#define BATT_SAMPLE_INTERVAL  5000   // 5秒采样一次
#define BATT_AVG_COUNT        10     // 滑动平均次数
#define BATT_MIN_MV           3000   // 3.0V = 0%
#define BATT_MAX_MV           4500   // 4.5V = 100%

// ==================== ESP-NOW参数 ====================
#define ESPNOW_CMD_INTERVAL    100   // 100ms发指令
#define ESPNOW_STATUS_INTERVAL 200   // 200ms发状态
#define ESPNOW_INVITE_INTERVAL 500   // 500ms发邀请
#define ESPNOW_INVITE_TIMEOUT  30000 // 30秒邀请超时
#define SLAVE_CMD_TIMEOUT      300   // 300ms无指令超时
#define MASTER_STATUS_WARN     1000  // 1秒无状态警告
#define MASTER_STATUS_TIMEOUT  3000  // 3秒无状态解联

// ==================== PWM通道 ====================
#define PWM_CHANNEL_IN1  0
#define PWM_CHANNEL_IN2  1
#define PWM_FREQ         1000
#define PWM_RESOLUTION   8

// ==================== BLE UUIDs ====================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_CONTROL_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_STATUS_UUID    "8c224e70-1b0a-4f66-b4c3-16e4c2e70391"

// ==================== ESP-NOW包类型 ====================
#define PKT_INVITE       0x01
#define PKT_ACCEPT       0x02
#define PKT_CMD          0x10
#define PKT_STATUS       0x11
#define PKT_UNCOUPLE     0x20
#define PKT_UNCOUPLE_ACK 0x21

// ==================== ESP-NOW数据结构 ====================
struct __attribute__((packed)) EspNowPacket {
  uint8_t type;
  uint8_t payload[24];
};

struct __attribute__((packed)) InvitePayload {
  uint8_t masterMAC[6];
  uint8_t masterTailEnd;  // 'A' or 'B'
};

struct __attribute__((packed)) AcceptPayload {
  uint8_t slaveMAC[6];
  uint8_t slaveCoupleEnd; // 'A' or 'B'
};

struct __attribute__((packed)) CmdPayload {
  uint8_t  targetDir;
  uint8_t  targetPWM;
  uint8_t  lightEndA;     // 0=off 1=white 2=red
  uint8_t  lightEndB;
  uint8_t  headlightOn;
  uint8_t  soundEnabled;
  uint8_t  seqNum;
};

struct __attribute__((packed)) StatusPayload {
  uint8_t  actualPWM;
  uint8_t  batteryPct;
  uint16_t batteryMV;
};

// ==================== 角色状态 ====================
enum RoleState {
  ROLE_STANDALONE,
  ROLE_INVITING,
  ROLE_INVITED,
  ROLE_MASTER,
  ROLE_SLAVE
};

// ==================== 全局状态 ====================
// 驾驶端与灯光
bool cabAtEndA = true;
bool headlightOn = false;

// 音效
bool soundEnabled = false;

// 电机
uint8_t targetDir = 0;
uint8_t actualDir = 0;
uint8_t targetLevel = 0;
uint16_t targetPWM = 0;
uint16_t actualPWM = 0;

// 电机状态机
enum MotorState {
  STATE_IDLE,
  STATE_KICK,
  STATE_RAMPING,
  STATE_RUNNING
};
MotorState motorState = STATE_IDLE;
unsigned long kickStartTime = 0;
unsigned long lastRampTime = 0;

// 演示模式
enum DemoState {
  DEMO_WAITING,
  DEMO_RUNNING,
  DEMO_EXITING,
  DEMO_OFF
};
DemoState demoState = DEMO_WAITING;
unsigned long bootTime = 0;

// 电池
uint16_t batteryMV = 4500;
uint8_t  batteryPct = 100;
uint16_t battSamples[BATT_AVG_COUNT];
uint8_t  battSampleIdx = 0;
bool     battSamplesFilled = false;
unsigned long lastBattSampleTime = 0;

// 重联
RoleState roleState = ROLE_STANDALONE;
uint8_t peerMAC[6] = {0};
uint8_t slaveCoupleEnd = 'A';    // 补机连接端
float   speedCoeff = 1.00f;      // 速度系数
uint8_t cmdSeqNum = 0;

// 补机收到的指令 (SLAVE模式用)
uint8_t slaveCmdDir = 0;
uint8_t slaveCmdPWM = 0;
uint8_t slaveCmdLightA = 0;
uint8_t slaveCmdLightB = 0;
uint8_t slaveCmdHeadlight = 0;
uint8_t slaveCmdSound = 0;

// 补机回报的状态 (MASTER模式用)
uint8_t  slaveActualPWM = 0;
uint8_t  slaveBatteryPct = 0;
uint16_t slaveBatteryMV = 0;
bool     slaveStatusValid = false;
bool     slaveStatusWarn = false;

// 邀请相关
unsigned long inviteStartTime = 0;
unsigned long lastInviteTime = 0;
uint8_t inviterMAC[6] = {0};  // 收到邀请时的来源MAC

// 超时计时
unsigned long lastSlaveCmd = 0;     // SLAVE: 上次收到CMD
unsigned long lastSlaveStatus = 0;  // MASTER: 上次收到STATUS
unsigned long lastCmdSendTime = 0;  // MASTER: 上次发CMD
unsigned long lastStatusSendTime = 0; // SLAVE: 上次发STATUS
unsigned long lastBleStatusTime = 0;

// BLE
BLEServer* pServer = nullptr;
BLECharacteristic* pControlChar = nullptr;
BLECharacteristic* pStatusChar = nullptr;
bool deviceConnected = false;
bool wasConnected = false;

// 自身MAC
uint8_t myMAC[6];

// ==================== 辅助函数 ====================

uint16_t levelToPWM(uint8_t level) {
  if (level == 0) return 0;
  if (level > THROTTLE_STEPS) level = THROTTLE_STEPS;
  return MIN_PWM + (uint16_t)(level - 1) * (MAX_PWM - MIN_PWM) / (THROTTLE_STEPS - 1);
}

void applyMotorPWM(uint8_t dir, uint16_t pwm) {
  bool reverse = (dir == 2);
  if (!cabAtEndA) reverse = !reverse;

  if (pwm == 0 || dir == 0) {
    ledcWrite(PWM_CHANNEL_IN1, 0);
    ledcWrite(PWM_CHANNEL_IN2, 0);
  } else if (!reverse) {
    ledcWrite(PWM_CHANNEL_IN1, pwm);
    ledcWrite(PWM_CHANNEL_IN2, 0);
  } else {
    ledcWrite(PWM_CHANNEL_IN1, 0);
    ledcWrite(PWM_CHANNEL_IN2, pwm);
  }
}

// 独立/本务机模式灯光
void updateLightsStandalone() {
  if (cabAtEndA) {
    digitalWrite(LED_A_WHITE, headlightOn ? HIGH : LOW);
    digitalWrite(LED_A_RED, LOW);
    digitalWrite(LED_B_WHITE, LOW);
    digitalWrite(LED_B_RED, HIGH);
  } else {
    digitalWrite(LED_B_WHITE, headlightOn ? HIGH : LOW);
    digitalWrite(LED_B_RED, LOW);
    digitalWrite(LED_A_WHITE, LOW);
    digitalWrite(LED_A_RED, HIGH);
  }
}

// 本务机端重联模式灯光
void updateLightsMaster() {
  // 本务机驾驶端 = 整列车头
  // 本务机车尾端 = 连接处(全灭)
  if (cabAtEndA) {
    // A=车头, B=连接处
    digitalWrite(LED_A_WHITE, headlightOn ? HIGH : LOW);
    digitalWrite(LED_A_RED, LOW);
    digitalWrite(LED_B_WHITE, LOW);
    digitalWrite(LED_B_RED, LOW);  // 连接处全灭
  } else {
    // B=车头, A=连接处
    digitalWrite(LED_B_WHITE, headlightOn ? HIGH : LOW);
    digitalWrite(LED_B_RED, LOW);
    digitalWrite(LED_A_WHITE, LOW);
    digitalWrite(LED_A_RED, LOW);  // 连接处全灭
  }
}

// 补机灯光指令计算 (由本务机调用)
void calcSlaveLights(uint8_t* lightA, uint8_t* lightB, bool* slaveHL) {
  // 补机连接端 = 连接处(全灭)
  // 补机远端 = 整列车尾(红灯) 或 整列车头(换端后)
  
  uint8_t slaveNearEnd = slaveCoupleEnd;       // 连接端
  uint8_t slaveFarEnd = (slaveCoupleEnd == 'A') ? 'B' : 'A'; // 远端
  
  // 判断整列车头在哪
  bool trainHeadAtMasterCab = true; // 正常情况车头在本务机驾驶端
  // 换端后车头在补机远端
  // cabAtEndA=true: 车头=本务A, 车尾=补机远端
  // cabAtEndA=false: 车头=补机远端, 车尾=本务A
  
  // 本务机驾驶端是整列车头时:
  //   补机连接端=全灭, 补机远端=红灯(车尾)
  // 换端后(整列车头在补机远端):
  //   补机连接端=全灭, 补机远端=白灯(可控)(车头), 本务机驾驶端=红灯
  
  // 简化逻辑: 
  // cabAtEndA=true → 整列车头=本务A → 补机远端=车尾
  // cabAtEndA=false → 整列车头=补机远端 → 补机远端=车头

  bool headAtSlaveFar = !cabAtEndA;
  // 当cabAtEndA=false时, 如果本务机车尾=A, 那整列车头在补机远端

  // 更精确的判断:
  // 本务机车尾 = cabAtEndA ? B : A
  // 整列方向: 驾驶端→本务机车尾→补机连接端→补机远端
  // 整列车头 = 本务机驾驶端
  // 整列车尾 = 补机远端
  // 换端 = 翻转, 整列车头变为补机远端, 车尾变为本务机(原)驾驶端
  
  // 实际上换端只改变cabAtEndA, 不改变物理连接:
  // 换端前: 车头=本务机cabEnd, 车尾=补机farEnd
  // 换端后: cabAtEndA翻转, 新车头=本务机新cabEnd, 新车尾=补机新farEnd
  // 但物理连接不变: 本务机(原)尾端还是连着补机连接端
  
  // 所以无论是否换端:
  // 整列车头 = 本务机当前驾驶端 (cabAtEndA ? A : B)
  // 整列车尾 = 补机远端 (slaveCoupleEnd=='A' ? B : A)
  // 连接处 = 本务机车尾端 + 补机连接端 → 全灭

  // 补机端灯光:
  // 连接端(slaveNearEnd) = 全灭 (0)
  // 远端(slaveFarEnd) = 红灯 (2) → 整列车尾
  
  // 但如果换端后要让补机远端变车头... 这里有矛盾
  // 重新思考: 换端 = 整列换端
  // 换端意味着: 物理上不动, 但逻辑上列车头尾互换
  // 换端前: 本务A=车头, 补机B=车尾 (假设连接端A)
  // 换端后: 补机B=车头, 本务A=车尾
  // 此时cabAtEndA=false, 本务驾驶端=B(连接处!), 这不对
  
  // 重新理解换端:
  // 在重联模式下, "换端"应该理解为整列的车头车尾互换
  // 等价于: 原来的车尾变车头, 原来的车头变车尾
  // 那灯光: 原车尾(补机远端)变为新车头(白灯), 原车头(本务驾驶端)变为新车尾(红灯)
  
  // 用一个布尔变量 trainForward 表示整列当前车头位置:
  // trainForward=true: 车头=本务机初始驾驶端, 车尾=补机远端
  // trainForward=false: 车头=补机远端, 车尾=本务机初始驾驶端
  // 这个变量其实就是 cabAtEndA (初始=true=A端驾驶=A端为车头)
  // 换端: cabAtEndA翻转
  
  // OK, 结论:
  // cabAtEndA=true: 整列车头=本务A, 整列车尾=补机远端
  //   补机连接端=全灭, 补机远端=红灯
  // cabAtEndA=false: 整列车头=补机远端, 整列车尾=本务A  
  //   补机连接端=全灭, 补机远端=白灯(可控)

  // 注意: 本务机驾驶端始终是cabAtEndA指向的端
  // cabAtEndA=false时, 本务机驾驶端=B=连接处
  // 这时本务B=连接处也是驾驶端? 逻辑上不通...
  
  // 最终简化: 用 trainHeadAtMasterCab 标记
  // 初始: trainHeadAtMasterCab = true (车头在本务机驾驶端一侧)
  // 换端: trainHeadAtMasterCab = false (车头在补机远端一侧)
  // 再换端: trainHeadAtMasterCab = true
  // 这个变量和cabAtEndA独立, 不影响本务机的物理方向映射

  // *** 不, 让我重新简化: ***
  // 在重联模式下, cabAtEndA 在换端时依然翻转
  // 用 cabAtEndA 决定本务机的电机方向(不变)
  // 用一个额外变量 coupledHeadAtCab 标记整列车头在哪
  // 或者直接用 cabAtEndA:
  //   cabAtEndA=true, masterTailEnd=B: 车头=A(本务), 车尾=slaveFarEnd
  //   cabAtEndA=false, masterTailEnd=A: 车头=B(本务), 车尾=slaveFarEnd
  //   但此时masterTail=A, 不是连接处(连接处是B)... 不对!
  
  // 物理连接在配对时就确定了:
  // masterTailEnd在配对时 = cabAtEndA ? B : A
  // 配对后连接关系固定, 不随换端改变
  
  // 所以需要记录配对时的连接端:
  // masterCoupleEnd (本务机的连接端, 固定不变)
  // slaveCoupleEnd (补机的连接端, 固定不变)
  
  // 换端只改变cabAtEndA
  // cabAtEndA指向的端如果==masterCoupleEnd, 说明驾驶端在连接处一侧
  // 此时整列车头=补机远端
  
  uint8_t masterCoupleEnd = (slaveCoupleEnd == slaveCoupleEnd) ? 
    (cabAtEndA ? 'B' : 'A') : 0; // 这个不对, masterCoupleEnd应该在配对时记录

  // ... 这个在全局变量中记录为 masterCoupleEndStored

  // 先简化: 假设配对时记录了 masterCoupleEndStored
  // cabAtEndA端 == masterCoupleEndStored? 
  //   是: 驾驶端在连接侧, 整列车头=补机远端
  //   否: 驾驶端在外侧, 整列车头=本务机驾驶端
  
  // 为了代码清晰, 我用全局变量重新整理...
  // (见下方全局变量补充)
  
  // 这里先给出简化版本:
  bool cabIsAtCoupleEnd = (cabAtEndA && masterCoupleEndStored == 'A') ||
                          (!cabAtEndA && masterCoupleEndStored == 'B');
  
  if (!cabIsAtCoupleEnd) {
    // 正常: 整列车头=本务机驾驶端, 整列车尾=补机远端
    // 补机: 连接端=全灭, 远端=红灯(车尾)
    if (slaveFarEnd == 'A') { *lightA = 2; *lightB = 0; }
    else                    { *lightA = 0; *lightB = 2; }
    *slaveHL = false;
  } else {
    // 换端后: 整列车头=补机远端, 整列车尾=本务机驾驶端
    // 补机: 连接端=全灭, 远端=白灯(可控)(车头)
    if (slaveFarEnd == 'A') { *lightA = 1; *lightB = 0; }
    else                    { *lightA = 0; *lightB = 1; }
    *slaveHL = headlightOn;
  }
}

// 补机执行灯光指令 (SLAVE模式, 收到CMD后调用)
void applySlaveLight(uint8_t lA, uint8_t lB, uint8_t hl) {
  // lA: 0=off 1=white 2=red, lB同
  switch (lA) {
    case 0: digitalWrite(LED_A_WHITE, LOW);  digitalWrite(LED_A_RED, LOW);  break;
    case 1: digitalWrite(LED_A_WHITE, hl ? HIGH : LOW); digitalWrite(LED_A_RED, LOW); break;
    case 2: digitalWrite(LED_A_WHITE, LOW);  digitalWrite(LED_A_RED, HIGH); break;
  }
  switch (lB) {
    case 0: digitalWrite(LED_B_WHITE, LOW);  digitalWrite(LED_B_RED, LOW);  break;
    case 1: digitalWrite(LED_B_WHITE, hl ? HIGH : LOW); digitalWrite(LED_B_RED, LOW); break;
    case 2: digitalWrite(LED_B_WHITE, LOW);  digitalWrite(LED_B_RED, HIGH); break;
  }
}

void updateLights() {
  if (roleState == ROLE_MASTER) {
    updateLightsMaster();
  } else if (roleState == ROLE_SLAVE) {
    // SLAVE模式灯光由CMD指令控制, 不在这里处理
  } else {
    updateLightsStandalone();
  }
}

void updateSound() {
  bool shouldPlay = soundEnabled && (actualPWM > 0);
  digitalWrite(SOUND_POWER, shouldPlay ? HIGH : LOW);
}

bool isFullyStopped() {
  return (targetPWM == 0 && actualPWM == 0);
}

bool isDemoActive() {
  return (demoState == DEMO_RUNNING || demoState == DEMO_EXITING);
}

// ==================== 电池采样 ====================

void sampleBattery() {
  uint16_t raw = analogRead(BATT_ADC);
  // ESP32-C3 ADC: 12bit (0~4095), 参考电压约2.5V (有衰减)
  // 分压: Vbatt * 100k/(100k+100k) = Vbatt/2
  // ADC读数 = (Vbatt/2) / 2.5 * 4095
  // Vbatt(mV) = raw * 2 * 2500 / 4095
  uint32_t mv = (uint32_t)raw * 5000 / 4095;
  
  battSamples[battSampleIdx] = (uint16_t)mv;
  battSampleIdx = (battSampleIdx + 1) % BATT_AVG_COUNT;
  if (battSampleIdx == 0) battSamplesFilled = true;
  
  uint8_t count = battSamplesFilled ? BATT_AVG_COUNT : battSampleIdx;
  if (count == 0) count = 1;
  uint32_t sum = 0;
  for (uint8_t i = 0; i < count; i++) sum += battSamples[i];
  batteryMV = sum / count;
  
  if (batteryMV <= BATT_MIN_MV) batteryPct = 0;
  else if (batteryMV >= BATT_MAX_MV) batteryPct = 100;
  else batteryPct = (uint8_t)((uint32_t)(batteryMV - BATT_MIN_MV) * 100 / (BATT_MAX_MV - BATT_MIN_MV));
}

// ==================== ESP-NOW 发送 ====================

// 补充全局变量: 配对时记录的本务机连接端
uint8_t masterCoupleEndStored = 'B'; // 配对时确定, 默认B

void espnowSend(const uint8_t* dest, const void* data, size_t len) {
  esp_now_send(dest, (const uint8_t*)data, len);
}

void sendInviteBroadcast() {
  EspNowPacket pkt;
  pkt.type = PKT_INVITE;
  InvitePayload* p = (InvitePayload*)pkt.payload;
  memcpy(p->masterMAC, myMAC, 6);
  p->masterTailEnd = cabAtEndA ? 'B' : 'A';
  
  // 广播地址
  uint8_t broadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  espnowSend(broadcast, &pkt, sizeof(uint8_t) + sizeof(InvitePayload));
}

void sendAccept(const uint8_t* masterMAC, uint8_t coupleEnd) {
  EspNowPacket pkt;
  pkt.type = PKT_ACCEPT;
  AcceptPayload* p = (AcceptPayload*)pkt.payload;
  memcpy(p->slaveMAC, myMAC, 6);
  p->slaveCoupleEnd = coupleEnd;
  espnowSend(masterMAC, &pkt, sizeof(uint8_t) + sizeof(AcceptPayload));
}

void sendCmdToSlave() {
  if (roleState != ROLE_MASTER) return;
  
  // 计算补机方向
  uint8_t slaveDir = targetDir;
  // 补机连接端=A → 同向; =B → 反向
  if (slaveCoupleEnd == 'B' && slaveDir != 0) {
    slaveDir = (slaveDir == 1) ? 2 : 1;
  }
  
  // 计算补机PWM (乘以系数)
  uint16_t slavePWMraw = (uint16_t)(targetPWM * speedCoeff + 0.5f);
  if (slavePWMraw > 255) slavePWMraw = 255;
  uint8_t slavePWMbyte = (uint8_t)slavePWMraw;
  
  // 如果目标PWM>0但乘系数后<MIN_PWM, 钳位到MIN_PWM
  if (targetPWM > 0 && slavePWMbyte > 0 && slavePWMbyte < MIN_PWM) {
    slavePWMbyte = MIN_PWM;
  }
  if (targetPWM == 0) slavePWMbyte = 0;
  
  // 计算补机灯光
  uint8_t lA = 0, lB = 0;
  bool slaveHL = false;
  calcSlaveLights(&lA, &lB, &slaveHL);
  
  EspNowPacket pkt;
  pkt.type = PKT_CMD;
  CmdPayload* p = (CmdPayload*)pkt.payload;
  p->targetDir = slaveDir;
  p->targetPWM = slavePWMbyte;
  p->lightEndA = lA;
  p->lightEndB = lB;
  p->headlightOn = slaveHL ? 1 : 0;
  p->soundEnabled = soundEnabled ? 1 : 0;
  p->seqNum = cmdSeqNum++;
  
  espnowSend(peerMAC, &pkt, sizeof(uint8_t) + sizeof(CmdPayload));
}

void sendStatusToMaster() {
  if (roleState != ROLE_SLAVE) return;
  
  EspNowPacket pkt;
  pkt.type = PKT_STATUS;
  StatusPayload* p = (StatusPayload*)pkt.payload;
  p->actualPWM = (uint8_t)actualPWM;
  p->batteryPct = batteryPct;
  p->batteryMV = batteryMV;
  
  espnowSend(peerMAC, &pkt, sizeof(uint8_t) + sizeof(StatusPayload));
}

void sendUncouple() {
  EspNowPacket pkt;
  pkt.type = PKT_UNCOUPLE;
  espnowSend(peerMAC, &pkt, 1);
}

void sendUncoupleAck() {
  EspNowPacket pkt;
  pkt.type = PKT_UNCOUPLE_ACK;
  espnowSend(peerMAC, &pkt, 1);
}

// ==================== 重联管理 ====================

void enterMaster(const uint8_t* slaveMAC, uint8_t slvCoupleEnd) {
  roleState = ROLE_MASTER;
  memcpy(peerMAC, slaveMAC, 6);
  slaveCoupleEnd = slvCoupleEnd;
  masterCoupleEndStored = cabAtEndA ? 'B' : 'A';
  speedCoeff = 1.00f;
  slaveActualPWM = 0;
  slaveBatteryPct = 0;
  slaveBatteryMV = 0;
  slaveStatusValid = false;
  slaveStatusWarn = false;
  lastSlaveStatus = millis();
  lastCmdSendTime = millis();
  cmdSeqNum = 0;
  
  // 添加ESP-NOW peer
  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, peerMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  esp_now_add_peer(&peerInfo);
  
  // 更新灯光
  updateLightsMaster();
  
  Serial.println("Entered MASTER mode");
}

void enterSlave(const uint8_t* masterMAC) {
  roleState = ROLE_SLAVE;
  memcpy(peerMAC, masterMAC, 6);
  lastSlaveCmd = millis();
  lastStatusSendTime = millis();
  
  // 添加ESP-NOW peer
  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, peerMAC, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;
  esp_now_add_peer(&peerInfo);
  
  Serial.println("Entered SLAVE mode");
}

void exitCoupling() {
  if (roleState == ROLE_MASTER || roleState == ROLE_SLAVE) {
    esp_now_del_peer(peerMAC);
  }
  roleState = ROLE_STANDALONE;
  memset(peerMAC, 0, 6);
  slaveStatusValid = false;
  slaveStatusWarn = false;
  
  // 恢复独立灯光
  updateLightsStandalone();
  
  Serial.println("Exited coupling, back to STANDALONE");
}

// ==================== 状态上报 ====================

void sendStatus() {
  if (!deviceConnected) return;
  
  bool sndPlaying = soundEnabled && (actualPWM > 0);
  
  char buf[200];
  int pos = 0;
  
  // 基本字段
  pos += snprintf(buf + pos, sizeof(buf) - pos,
    "CAB:%c HL:%s DIR:%s LV:%d APWM:%d TPWM:%d SE:%s SND:%s DM:%s BAT:%d BATV:%d.%02d",
    cabAtEndA ? 'A' : 'B',
    headlightOn ? "ON" : "OFF",
    actualPWM == 0 ? "STOP" : (actualDir == 1 ? "FWD" : "REV"),
    targetLevel,
    actualPWM,
    targetPWM,
    soundEnabled ? "ON" : "OFF",
    sndPlaying ? "ON" : "OFF",
    isDemoActive() ? "ON" : "OFF",
    batteryPct,
    batteryMV / 1000, (batteryMV % 1000) / 10
  );
  
  // 重联字段
  switch (roleState) {
    case ROLE_STANDALONE:
      pos += snprintf(buf + pos, sizeof(buf) - pos, " CP:OFF");
      break;
    case ROLE_INVITING:
      pos += snprintf(buf + pos, sizeof(buf) - pos, " CP:INVITING");
      break;
    case ROLE_INVITED:
      pos += snprintf(buf + pos, sizeof(buf) - pos, " CP:INVITED INV:%02X:%02X:%02X:%02X:%02X:%02X",
        inviterMAC[0], inviterMAC[1], inviterMAC[2],
        inviterMAC[3], inviterMAC[4], inviterMAC[5]);
      break;
    case ROLE_MASTER:
      pos += snprintf(buf + pos, sizeof(buf) - pos, 
        " CP:MASTER SC:%c SAPWM:%d SBAT:%d SBATV:%d.%02d SK:%d.%02d",
        slaveCoupleEnd,
        slaveActualPWM,
        slaveBatteryPct,
        slaveBatteryMV / 1000, (slaveBatteryMV % 1000) / 10,
        (int)speedCoeff, (int)(speedCoeff * 100) % 100
      );
      if (slaveStatusWarn) {
        pos += snprintf(buf + pos, sizeof(buf) - pos, " SWARN:1");
      }
      break;
    case ROLE_SLAVE:
      pos += snprintf(buf + pos, sizeof(buf) - pos, " CP:SLAVE");
      break;
  }
  
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

// ==================== ESP-NOW 回调 ====================

void onEspNowRecv(const esp_now_recv_info_t* info, const uint8_t* data, int len) {
  if (len < 1) return;
  
  const uint8_t* senderMAC = info->src_addr;
  uint8_t type = data[0];
  const uint8_t* payload = data + 1;
  
  switch (type) {
    case PKT_INVITE: {
      if (roleState != ROLE_STANDALONE && roleState != ROLE_INVITED) return;
      if (len < 1 + (int)sizeof(InvitePayload)) return;
      const InvitePayload* inv = (const InvitePayload*)payload;
      
      // 演示模式中收到邀请: 退出演示, 自动接受
      if (demoState == DEMO_RUNNING) {
        // 退出演示
        demoState = DEMO_EXITING;
        soundEnabled = false;
        targetDir = 0;
        targetLevel = 0;
        targetPWM = 0;
        if (actualPWM > 0) {
          motorState = STATE_RAMPING;
          lastRampTime = millis();
        }
        updateSound();
        
        // 记录邀请者, 停稳后自动接受
        memcpy(inviterMAC, inv->masterMAC, 6);
        roleState = ROLE_INVITED;
        // slaveCoupleEnd默认车头端
        slaveCoupleEnd = cabAtEndA ? 'A' : 'B'; // 当前驾驶端=车头端
        return;
      }
      
      // 正常模式: 记录邀请, 通知App
      memcpy(inviterMAC, inv->masterMAC, 6);
      roleState = ROLE_INVITED;
      sendStatus(); // 通知App有邀请
      break;
    }
    
    case PKT_ACCEPT: {
      if (roleState != ROLE_INVITING) return;
      if (len < 1 + (int)sizeof(AcceptPayload)) return;
      const AcceptPayload* acc = (const AcceptPayload*)payload;
      
      enterMaster(acc->slaveMAC, acc->slaveCoupleEnd);
      sendStatus();
      break;
    }
    
    case PKT_CMD: {
      if (roleState != ROLE_SLAVE) return;
      if (len < 1 + (int)sizeof(CmdPayload)) return;
      const CmdPayload* cmd = (const CmdPayload*)payload;
      
      lastSlaveCmd = millis();
      
      // 更新补机目标
      slaveCmdDir = cmd->targetDir;
      slaveCmdPWM = cmd->targetPWM;
      slaveCmdLightA = cmd->lightEndA;
      slaveCmdLightB = cmd->lightEndB;
      slaveCmdHeadlight = cmd->headlightOn;
      slaveCmdSound = cmd->soundEnabled;
      
      // 应用灯光
      applySlaveLight(cmd->lightEndA, cmd->lightEndB, cmd->headlightOn);
      
      // 应用音效
      soundEnabled = cmd->soundEnabled;
      
      // 应用电机目标 (补机的状态机独立驱动)
      if (cmd->targetPWM == 0) {
        targetDir = 0;
        targetLevel = 0;
        targetPWM = 0;
      } else {
        // 检查方向变化
        if (actualPWM > 0 && actualDir != 0 && actualDir != cmd->targetDir) {
          // 需要先停车再换向 (由本务机保证不会在运行中换向)
          targetDir = 0;
          targetLevel = 0;
          targetPWM = 0;
        } else {
          targetDir = cmd->targetDir;
          targetPWM = cmd->targetPWM;
          // 从PWM反推档位(近似)
          targetLevel = 0;
          for (uint8_t l = 1; l <= THROTTLE_STEPS; l++) {
            if (levelToPWM(l) >= cmd->targetPWM) { targetLevel = l; break; }
          }
          
          if (actualPWM == 0) {
            actualDir = targetDir;
            actualPWM = KICK_PWM;
            applyMotorPWM(actualDir, actualPWM);
            kickStartTime = millis();
            motorState = STATE_KICK;
          } else if (motorState == STATE_RUNNING || motorState == STATE_RAMPING) {
            motorState = STATE_RAMPING;
          }
        }
      }
      break;
    }
    
    case PKT_STATUS: {
      if (roleState != ROLE_MASTER) return;
      if (len < 1 + (int)sizeof(StatusPayload)) return;
      const StatusPayload* st = (const StatusPayload*)payload;
      
      slaveActualPWM = st->actualPWM;
      slaveBatteryPct = st->batteryPct;
      slaveBatteryMV = st->batteryMV;
      slaveStatusValid = true;
      slaveStatusWarn = false;
      lastSlaveStatus = millis();
      break;
    }
    
    case PKT_UNCOUPLE: {
      if (roleState != ROLE_SLAVE) return;
      sendUncoupleAck();
      
      // 停车
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      if (actualPWM > 0) {
        motorState = STATE_RAMPING;
        lastRampTime = millis();
      }
      
      exitCoupling();
      sendStatus();
      break;
    }
    
    case PKT_UNCOUPLE_ACK: {
      if (roleState != ROLE_MASTER) return;
      exitCoupling();
      sendStatus();
      break;
    }
  }
}

void onEspNowSent(const uint8_t* mac_addr, esp_now_send_status_t status) {
  // 可用于记录发送成功/失败统计
}

// ==================== BLE 回调 ====================

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    
    if (demoState == DEMO_WAITING) {
      demoState = DEMO_OFF;
    } else if (demoState == DEMO_RUNNING) {
      // 演示中BLE连接, 退出演示
      demoState = DEMO_EXITING;
      soundEnabled = false;
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      if (actualPWM > 0) {
        motorState = STATE_RAMPING;
        lastRampTime = millis();
      }
      updateSound();
    }
  }
  
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
  }
};

class ControlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = String(pChar->getValue().c_str());
    val.trim();
    if (val.length() == 0) return;
    
    // 演示退出中拒绝操作
    if (demoState == DEMO_EXITING) {
      sendError("DEMO_STOPPING");
      return;
    }
    
    // 补机模式拒绝控制指令(灯光/音效也由本务机控制)
    if (roleState == ROLE_SLAVE) {
      sendError("SLAVE_MODE");
      return;
    }
    
    // ---- 灯光指令 ----
    if (val == "L") {
      headlightOn = !headlightOn;
      updateLights();
      sendStatus();
      return;
    }
    if (val == "L:0") { headlightOn = false; updateLights(); sendStatus(); return; }
    if (val == "L:1") { headlightOn = true;  updateLights(); sendStatus(); return; }
    
    // ---- 音效指令 (重联时同步两车) ----
    if (val == "M")   { soundEnabled = !soundEnabled; updateSound(); sendStatus(); return; }
    if (val == "M:0") { soundEnabled = false; updateSound(); sendStatus(); return; }
    if (val == "M:1") { soundEnabled = true;  updateSound(); sendStatus(); return; }
    
    // ---- 换端指令 ----
    if (val == "C") {
      if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
      // 重联中也要求补机停稳
      if (roleState == ROLE_MASTER && slaveActualPWM > 0) {
        sendError("STOP_FIRST"); return;
      }
      cabAtEndA = !cabAtEndA;
      headlightOn = false;
      updateLights();
      sendStatus();
      return;
    }
    
    // ---- 停车指令 ----
    if (val == "S") {
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      if (actualPWM == 0) { motorState = STATE_IDLE; actualDir = 0; }
      sendStatus();
      return;
    }
    
    // ---- 前进/后退指令 ----
    if ((val.startsWith("F:") || val.startsWith("R:")) && val.length() >= 3) {
      uint8_t newDir = (val.charAt(0) == 'F') ? 1 : 2;
      int level = val.substring(2).toInt();
      if (level < 1 || level > 8) return;
      
      if (actualPWM > 0 && actualDir != 0 && actualDir != newDir) {
        sendError("STOP_FIRST"); return;
      }
      
      targetDir = newDir;
      targetLevel = level;
      targetPWM = levelToPWM(level);
      
      if (actualPWM == 0) {
        actualDir = newDir;
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
    
    // ---- 重联邀请 ----
    if (val == "CP") {
      if (roleState != ROLE_STANDALONE) {
        sendError("ALREADY_COUPLED"); return;
      }
      if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
      roleState = ROLE_INVITING;
      inviteStartTime = millis();
      lastInviteTime = 0;
      
      // 添加广播peer
      esp_now_peer_info_t peerInfo = {};
      memset(peerInfo.peer_addr, 0xFF, 6);
      peerInfo.channel = 0;
      peerInfo.encrypt = false;
      if (!esp_now_is_peer_exist(peerInfo.peer_addr)) {
        esp_now_add_peer(&peerInfo);
      }
      
      sendStatus();
      return;
    }
    if (val == "CP:STOP") {
      if (roleState == ROLE_INVITING) {
        roleState = ROLE_STANDALONE;
        sendStatus();
      }
      return;
    }
    
    // ---- 接受邀请 ----
    if (val.startsWith("J:") && val.length() >= 3) {
      if (roleState != ROLE_INVITED) { sendError("NOT_INVITED"); return; }
      if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
      
      char end = val.charAt(2);
      if (end != 'A' && end != 'B') return;
      
      slaveCoupleEnd = end;
      sendAccept(inviterMAC, end);
      enterSlave(inviterMAC);
      sendStatus();
      return;
    }
    
    // ---- 解联 ----
    if (val == "U") {
      if (roleState != ROLE_MASTER) { sendError("NOT_COUPLED"); return; }
      if (!isFullyStopped()) { sendError("STOP_FIRST"); return; }
      if (slaveActualPWM > 0) { sendError("STOP_FIRST"); return; }
      sendUncouple();
      // 等ACK或超时后在loop中处理
      sendStatus();
      return;
    }
    
    // ---- 速度系数 ----
    if (val.startsWith("K:")) {
      if (roleState != ROLE_MASTER) { sendError("NOT_COUPLED"); return; }
      float k = val.substring(2).toFloat();
      if (k < 0.90f || k > 1.10f) { sendError("INVALID_COEFF"); return; }
      speedCoeff = k;
      sendStatus();
      return;
    }
  }
};

// ==================== 电机状态机 ====================

void motorStateMachine() {
  unsigned long now = millis();
  
  switch (motorState) {
    case STATE_IDLE:
      if (demoState == DEMO_EXITING && actualPWM == 0) {
        // 演示退出中, 检查是否需要自动接受邀请
        if (roleState == ROLE_INVITED) {
          // 停稳后自动接受邀请
          sendAccept(inviterMAC, slaveCoupleEnd);
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
          actualPWM = KICK_PWM;
          motorState = STATE_RAMPING;
        } else {
          actualPWM = targetPWM;
          applyMotorPWM(actualDir, actualPWM);
          motorState = STATE_RUNNING;
        }
        lastRampTime = now;
      }
      break;
      
    case STATE_RAMPING:
      if (now - lastRampTime >= RAMP_INTERVAL) {
        lastRampTime = now;
        
        if (actualPWM < targetPWM) {
          actualPWM += RAMP_STEP;
          if (actualPWM > targetPWM) actualPWM = targetPWM;
          applyMotorPWM(actualDir, actualPWM);
        } else if (actualPWM > targetPWM) {
          if (actualPWM <= RAMP_STEP) actualPWM = 0;
          else actualPWM -= RAMP_STEP;
          if (actualPWM > 0 && actualPWM < MIN_PWM) actualPWM = 0;
          
          if (actualPWM == 0) {
            applyMotorPWM(0, 0);
            actualDir = 0;
            motorState = STATE_IDLE;
          } else {
            applyMotorPWM(actualDir, actualPWM);
          }
        }
        
        if (actualPWM == targetPWM) {
          if (actualPWM == 0) { motorState = STATE_IDLE; actualDir = 0; }
          else motorState = STATE_RUNNING;
        }
        
        updateSound();
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

// ==================== 演示模式状态机 ====================

void demoStateMachine() {
  if (demoState != DEMO_WAITING) return;
  if (millis() - bootTime >= DEMO_WAIT_TIME && !deviceConnected) {
    // 启动演示
    demoState = DEMO_RUNNING;
    soundEnabled = true;
    targetDir = DEMO_DIR;
    targetLevel = DEMO_LEVEL;
    targetPWM = levelToPWM(DEMO_LEVEL);
    actualDir = DEMO_DIR;
    actualPWM = KICK_PWM;
    applyMotorPWM(actualDir, actualPWM);
    kickStartTime = millis();
    motorState = STATE_KICK;
    updateSound();
  } else if (deviceConnected) {
    demoState = DEMO_OFF;
  }
}

// ==================== 重联超时检测 ====================

void couplingTimeoutCheck() {
  unsigned long now = millis();
  
  // 邀请超时
  if (roleState == ROLE_INVITING) {
    if (now - inviteStartTime >= ESPNOW_INVITE_TIMEOUT) {
      roleState = ROLE_STANDALONE;
      sendStatus();
    } else if (now - lastInviteTime >= ESPNOW_INVITE_INTERVAL) {
      lastInviteTime = now;
      sendInviteBroadcast();
    }
  }
  
  // SLAVE: CMD超时
  if (roleState == ROLE_SLAVE) {
    if (now - lastSlaveCmd >= SLAVE_CMD_TIMEOUT) {
      // 超时, 自动停车并解联
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      if (actualPWM > 0) {
        motorState = STATE_RAMPING;
        lastRampTime = now;
      }
      exitCoupling();
      sendStatus();
    }
  }
  
  // MASTER: STATUS超时
  if (roleState == ROLE_MASTER) {
    unsigned long elapsed = now - lastSlaveStatus;
    if (elapsed >= MASTER_STATUS_TIMEOUT) {
      // 3秒超时, 解联
      targetDir = 0; targetLevel = 0; targetPWM = 0;
      if (actualPWM > 0) {
        motorState = STATE_RAMPING;
        lastRampTime = now;
      }
      exitCoupling();
      sendStatus();
    } else if (elapsed >= MASTER_STATUS_WARN) {
      slaveStatusWarn = true;
    }
  }
  
  // MASTER: 定期发CMD
  if (roleState == ROLE_MASTER) {
    if (now - lastCmdSendTime >= ESPNOW_CMD_INTERVAL) {
      lastCmdSendTime = now;
      sendCmdToSlave();
    }
  }
  
  // SLAVE: 定期发STATUS
  if (roleState == ROLE_SLAVE) {
    if (now - lastStatusSendTime >= ESPNOW_STATUS_INTERVAL) {
      lastStatusSendTime = now;
      sendStatusToMaster();
    }
  }
}

// ==================== 开机自检 ====================

void startupSelfTest() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_A_WHITE, HIGH); digitalWrite(LED_B_WHITE, HIGH);
    digitalWrite(LED_A_RED, HIGH);   digitalWrite(LED_B_RED, HIGH);
    delay(200);
    digitalWrite(LED_A_WHITE, LOW);  digitalWrite(LED_B_WHITE, LOW);
    digitalWrite(LED_A_RED, LOW);    digitalWrite(LED_B_RED, LOW);
    delay(200);
  }
  
  cabAtEndA = true; headlightOn = true; updateLightsStandalone(); delay(500);
  cabAtEndA = false; headlightOn = true; updateLightsStandalone(); delay(500);
  
  digitalWrite(SOUND_POWER, HIGH); delay(500); digitalWrite(SOUND_POWER, LOW);
  
  cabAtEndA = true; headlightOn = false; soundEnabled = false;
  updateLightsStandalone(); updateSound();
}

// ==================== setup ====================

void setup() {
  Serial.begin(115200);
  
  // GPIO
  pinMode(LED_A_WHITE, OUTPUT); pinMode(LED_B_WHITE, OUTPUT);
  pinMode(LED_A_RED, OUTPUT);   pinMode(LED_B_RED, OUTPUT);
  pinMode(SOUND_POWER, OUTPUT);
  digitalWrite(LED_A_WHITE, LOW); digitalWrite(LED_B_WHITE, LOW);
  digitalWrite(LED_A_RED, LOW);   digitalWrite(LED_B_RED, LOW);
  digitalWrite(SOUND_POWER, LOW);
  
  // ADC
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  
  // PWM
  ledcSetup(PWM_CHANNEL_IN1, PWM_FREQ, PWM_RESOLUTION);
  ledcSetup(PWM_CHANNEL_IN2, PWM_FREQ, PWM_RESOLUTION);
  ledcAttachPin(MOTOR_IN1, PWM_CHANNEL_IN1);
  ledcAttachPin(MOTOR_IN2, PWM_CHANNEL_IN2);
  ledcWrite(PWM_CHANNEL_IN1, 0); ledcWrite(PWM_CHANNEL_IN2, 0);
  
  // 初始电池采样
  for (int i = 0; i < BATT_AVG_COUNT; i++) {
    sampleBattery();
    delay(10);
  }
  
  // 自检
  startupSelfTest();
  
  // WiFi (ESP-NOW需要)
  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
  
  // 获取自身MAC
  esp_read_mac(myMAC, ESP_MAC_WIFI_STA);
  Serial.printf("My MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
    myMAC[0], myMAC[1], myMAC[2], myMAC[3], myMAC[4], myMAC[5]);
  
  // ESP-NOW初始化
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed!");
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_register_send_cb(onEspNowSent);
  
  // BLE
  BLEDevice::init("BLE_Train");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  BLEService* pService = pServer->createService(SERVICE_UUID);
  
  pControlChar = pService->createCharacteristic(
    CHAR_CONTROL_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pControlChar->setCallbacks(new ControlCallbacks());
  
  pStatusChar = pService->createCharacteristic(
    CHAR_STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusChar->addDescriptor(new BLE2902());
  
  pService->start();
  
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
  
  bootTime = millis();
  demoState = DEMO_WAITING;
  
  Serial.println("BLE_Train ready!");
}

// ==================== loop ====================

void loop() {
  unsigned long now = millis();
  
  // 演示模式
  demoStateMachine();
  
  // 电机状态机
  motorStateMachine();
  
  // 音效
  updateSound();
  
  // 电池采样
  if (now - lastBattSampleTime >= BATT_SAMPLE_INTERVAL) {
    lastBattSampleTime = now;
    sampleBattery();
  }
  
  // 重联超时检测
  couplingTimeoutCheck();
  
  // BLE断连
  if (wasConnected && !deviceConnected) {
    targetDir = 0; targetLevel = 0; targetPWM = 0;
    if (actualPWM > 0) {
      motorState = STATE_RAMPING;
      lastRampTime = now;
    }
    
    // 重联中BLE断连: 保持重联, 但停车
    // (ESP-NOW继续发停车CMD给补机)
    
    delay(500);
    pServer->startAdvertising();
    Serial.println("BLE disconnected, stopping...");
  }
  wasConnected = deviceConnected;
  
  // 周期上报
  if (deviceConnected && (now - lastBleStatusTime >= 200)) {
    lastBleStatusTime = now;
    sendStatus();
  }
}
```

---

## 十四、油门档位速查

```
档位:    0     1     2     3     4     5     6     7     8
PWM:     0    160   174   187   201   214   228   241   255

补机PWM (系数0.90):  0  144  157  168  181  193  205  217  230
补机PWM (系数0.95):  0  152  165  178  191  203  217  229  242
补机PWM (系数1.00):  0  160  174  187  201  214  228  241  255
补机PWM (系数1.05):  0  168  183  196  211  225  239  253  255
补机PWM (系数1.10):  0  176  191  206  221  235  251  255  255

注: 补机PWM乘系数后若>0且<MIN_PWM(160), 钳位到160
    补机PWM乘系数后若>255, 钳位到255

停车耗时 (全速→停): ≈480ms (24步×20ms)
```

---

## 十五、设计决策总结

| 维度 | 选型 | 理由 |
|------|------|------|
| **架构** | 非阻塞状态机 | BLE回调<1ms返回 |
| **换向策略** | 停车后才能换向 | 绝对保护齿轮 |
| **重联通信** | ESP-NOW | 低延迟(2~5ms)、免配对、与BLE共存 |
| **重联发现** | ESP-NOW广播邀请 | 不依赖BLE扫描 |
| **方向映射** | 本务机计算后下发 | 补机无需知道拓扑 |
| **灯光计算** | 本务机统一计算 | 保证整列一致性 |
| **音效同步** | 本务机M指令同步两车 | 统一体验 |
| **速度系数** | 0.90~1.10 | 覆盖电机/电量差异 |
| **超时保护** | 补机300ms/本务机3s | 防失控 |
| **BLE断连(重联中)** | 保持重联,双车停车 | 手机重连后可继续 |
| **演示+邀请** | 自动退出演示接受 | 流畅的用户体验 |
| **电量采样** | 5秒/10次平均 | 抗噪声 |
| **解联权限** | 仅本务机 | 避免误操作 |
| **换端(重联)** | 整列换端 | 模拟真实列车 |
| **补机App** | 只读 | 所有控制权归本务机 |

---

## 十六、修改点汇总（相对上一版）

| # | 修改内容 |
|---|----------|
| 1 | 新增GPIO0电池ADC + 分压电阻 |
| 2 | 新增电池采样与上报 (BAT/BATV) |
| 3 | UI改为横屏布局 |
| 4 | 新增ESP-NOW初始化与回调 |
| 5 | 新增角色状态机 (STANDALONE/INVITING/INVITED/MASTER/SLAVE) |
| 6 | 新增重联指令 (CP/J/U/K) |
| 7 | 新增重联灯光计算逻辑 |
| 8 | 新增重联方向映射 |
| 9 | 新增速度系数 |
| 10 | 新增超时保护 (补机300ms/本务机3s) |
| 11 | 新增MASTER/SLAVE ESP-NOW周期通信 |
| 12 | 新增补机只读BLE限制 |
| 13 | 新增重联状态回报字段 (CP/SC/SAPWM/SBAT等) |
| 14 | 新增本务机/补机横屏UI |
| 15 | 演示模式中收到邀请自动退出并接受(车头端) |
| 16 | 本务机BLE断连时保持重联但双车停车 |
| 17 | M指令在重联时同步两车音效 |
| 18 | C指令在重联时整列换端 |






# ESP32-C3 OTA 升级方案

## 一、OTA 方式对比

| 方式 | 原理 | 优点 | 缺点 | 适合场景 |
|------|------|------|------|----------|
| **BLE OTA** | 通过已有BLE连接传输固件 | 不需额外硬件，手机直接升级 | 传输慢（约2~5分钟），需开发App功能 | ✅ 最适合本项目 |
| **WiFi OTA** | 连接WiFi下载固件 | 传输快，Arduino原生支持 | 玩具火车没有WiFi环境 | ❌ 不适合 |
| **HTTP OTA** | 从服务器拉取固件 | 可批量升级 | 需要WiFi+服务器 | ❌ 不适合 |
| **SD卡OTA** | 从SD卡读取固件 | 离线升级 | 需要额外硬件 | ❌ 不适合 |
| **USB串口** | 物理连接刷写 | 最简单可靠 | 需要拆开外壳接线 | ⚠️ 作为兜底方案 |

**结论：采用 BLE OTA，手机App直接推送固件升级。**

---

## 二、实现原理

```
┌──────────────────────────────────────────────────────┐
│                 ESP32-C3 Flash 分区布局               │
│                                                      │
│  ┌──────────┐                                        │
│  │Bootloader│  0x0000  (不可覆盖)                    │
│  ├──────────┤                                        │
│  │ 分区表    │  0x8000                                │
│  ├──────────┤                                        │
│  │ OTA Data │  0xE000  (记录当前启动分区)              │
│  ├──────────┤                                        │
│  │  app0    │  0x10000  ← 当前运行的固件              │
│  │ (1.3MB)  │                                        │
│  ├──────────┤                                        │
│  │  app1    │  0x150000 ← BLE接收的新固件写入这里      │
│  │ (1.3MB)  │                                        │
│  ├──────────┤                                        │
│  │  spiffs  │  0x290000 (可选，本项目未使用)           │
│  └──────────┘                                        │
│                                                      │
│  升级流程:                                            │
│  1. 新固件通过BLE写入 app1 分区                        │
│  2. 写入完成后校验MD5                                  │
│  3. 标记 app1 为下次启动分区                           │
│  4. 重启 → 从 app1 启动                               │
│  5. 新固件运行正常 → 确认 app1 (否则回滚到 app0)       │
└──────────────────────────────────────────────────────┘
```

---

## 三、代码改动

### 3.1 分区表配置

在项目目录下创建 `partitions_ota.csv`：

```csv
# Name,   Type, SubType, Offset,   Size,     Flags
nvs,      data, nvs,     0x9000,   0x5000,
otadata,  data, ota,     0xE000,   0x2000,
app0,     app,  ota_0,   0x10000,  0x140000,
app1,     app,  ota_1,   0x150000, 0x140000,
```

### 3.2 Arduino IDE / PlatformIO 配置

**Arduino IDE：**
```
工具 → Partition Scheme → 选择 "Minimal SPIFFS (1.9MB APP with OTA)"
```

**PlatformIO (`platformio.ini`)：**
```ini
[env:esp32c3]
platform = espressif32
board = esp32-c3-devkitm-1
framework = arduino
board_build.partitions = partitions_ota.csv
```

### 3.3 新增 BLE OTA 代码

在现有代码基础上新增以下内容：

```cpp
// ============================================================================
// 在文件头部新增 #include
// ============================================================================
#include <Update.h>    // ESP32 OTA更新库

// ============================================================================
// 新增 BLE OTA UUID
// ============================================================================
#define CHAR_OTA_UUID       "8c224e70-1b0a-4f66-b4c3-16e4c2e70392"  // OTA数据特征
#define CHAR_OTA_CTRL_UUID  "8c224e70-1b0a-4f66-b4c3-16e4c2e70393"  // OTA控制特征

// ============================================================================
// OTA 状态变量
// ============================================================================
BLECharacteristic* pOtaDataChar = nullptr;    // OTA数据接收特征
BLECharacteristic* pOtaCtrlChar = nullptr;    // OTA控制/状态特征

bool otaInProgress = false;      // OTA是否正在进行
uint32_t otaTotalSize = 0;       // 固件总大小 (字节)
uint32_t otaReceived = 0;        // 已接收字节数
uint32_t otaLastProgressTime = 0; // 上次进度上报时间

// ============================================================================
// OTA 控制特征回调
// ============================================================================

/**
 * OTA 控制特征回调
 * 
 * App通过此特征发送OTA控制指令:
 *   "OTA:BEGIN:123456"  — 开始OTA，123456为固件大小(字节)
 *   "OTA:END"           — 传输完成，执行校验和重启
 *   "OTA:ABORT"         — 中止OTA
 * 
 * 固件通过此特征回复OTA状态:
 *   "OTA:READY"         — 已准备好接收
 *   "OTA:PROGRESS:50"   — 进度50%
 *   "OTA:OK"            — 升级成功，即将重启
 *   "OTA:FAIL:原因"     — 升级失败
 */
class OtaCtrlCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String val = String(pChar->getValue().c_str());
    val.trim();

    // ---- 开始OTA ----
    if (val.startsWith("OTA:BEGIN:")) {
      // 解析固件大小
      otaTotalSize = val.substring(10).toInt();
      if (otaTotalSize == 0 || otaTotalSize > 0x140000) {
        // 大小无效或超出分区容量 (1.3MB = 0x140000)
        pOtaCtrlChar->setValue("OTA:FAIL:INVALID_SIZE");
        pOtaCtrlChar->notify();
        return;
      }

      // 安全检查: OTA前必须停车
      if (actualPWM > 0) {
        pOtaCtrlChar->setValue("OTA:FAIL:STOP_FIRST");
        pOtaCtrlChar->notify();
        return;
      }

      // 停车并关闭所有输出 (OTA过程中不能控制电机)
      targetDir = 0;
      targetLevel = 0;
      targetPWM = 0;
      actualPWM = 0;
      actualDir = 0;
      motorState = STATE_IDLE;
      applyMotorPWM(0, 0);
      soundEnabled = false;
      updateSound();

      // 如果在重联中，通知补机停车 (但保持重联关系)
      // OTA完成重启后重联会自然断开

      // 开始OTA写入
      if (!Update.begin(otaTotalSize)) {
        pOtaCtrlChar->setValue("OTA:FAIL:BEGIN_FAILED");
        pOtaCtrlChar->notify();
        Serial.println("OTA begin failed!");
        return;
      }

      otaInProgress = true;
      otaReceived = 0;
      otaLastProgressTime = millis();

      pOtaCtrlChar->setValue("OTA:READY");
      pOtaCtrlChar->notify();
      Serial.printf("OTA started, expecting %d bytes\n", otaTotalSize);
      return;
    }

    // ---- 传输完成 ----
    if (val == "OTA:END") {
      if (!otaInProgress) return;

      if (Update.end(true)) {
        // 校验通过，标记新分区为启动分区
        otaInProgress = false;
        pOtaCtrlChar->setValue("OTA:OK");
        pOtaCtrlChar->notify();
        Serial.println("OTA success! Rebooting in 2 seconds...");

        // 延迟重启，确保BLE通知发送完成
        delay(2000);
        ESP.restart();
      } else {
        otaInProgress = false;
        char errBuf[40];
        snprintf(errBuf, sizeof(errBuf), "OTA:FAIL:VERIFY_%d", Update.getError());
        pOtaCtrlChar->setValue(errBuf);
        pOtaCtrlChar->notify();
        Serial.printf("OTA end failed: %d\n", Update.getError());
      }
      return;
    }

    // ---- 中止OTA ----
    if (val == "OTA:ABORT") {
      if (otaInProgress) {
        Update.abort();
        otaInProgress = false;
        pOtaCtrlChar->setValue("OTA:ABORTED");
        pOtaCtrlChar->notify();
        Serial.println("OTA aborted by user");
      }
      return;
    }
  }
};

// ============================================================================
// OTA 数据特征回调
// ============================================================================

/**
 * OTA 数据特征回调
 * 
 * App将固件二进制数据分包写入此特征
 * BLE MTU通常为512字节，每包实际有效载荷约509字节
 * App应使用 Write Without Response 以提高速度
 * 
 * 典型传输速度: 约 8~15 KB/s (取决于BLE连接参数)
 * 200KB固件: 约 15~25 秒
 */
class OtaDataCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    if (!otaInProgress) return;

    // 获取数据 (注意: getValue() 返回 std::string)
    std::string data = pChar->getValue();
    size_t len = data.length();

    if (len > 0) {
      // 写入Flash
      size_t written = Update.write((const uint8_t*)data.c_str(), len);
      if (written != len) {
        // 写入失败
        otaInProgress = false;
        Update.abort();
        pOtaCtrlChar->setValue("OTA:FAIL:WRITE_ERROR");
        pOtaCtrlChar->notify();
        Serial.println("OTA write error!");
        return;
      }

      otaReceived += len;

      // 每2秒上报一次进度 (避免频繁通知影响传输速度)
      if (millis() - otaLastProgressTime >= 2000) {
        otaLastProgressTime = millis();
        uint8_t pct = (uint8_t)((uint32_t)otaReceived * 100 / otaTotalSize);
        char progBuf[20];
        snprintf(progBuf, sizeof(progBuf), "OTA:PROGRESS:%d", pct);
        pOtaCtrlChar->setValue(progBuf);
        pOtaCtrlChar->notify();
        Serial.printf("OTA progress: %d%% (%d/%d)\n", pct, otaReceived, otaTotalSize);
      }
    }
  }
};
```

### 3.4 修改 setup() — 注册OTA特征

在 `setup()` 中现有的 `pStatusChar` 创建之后，`pService->start()` 之前，添加：

```cpp
    // ---- OTA数据特征 (App写入固件二进制数据) ----
    // 使用 Write Without Response 以获得最高传输速度
    pOtaDataChar = pService->createCharacteristic(
      CHAR_OTA_UUID,
      BLECharacteristic::PROPERTY_WRITE_NR   // 仅无响应写入 (高速)
    );
    pOtaDataChar->setCallbacks(new OtaDataCallbacks());

    // ---- OTA控制特征 (控制指令 + 状态回报) ----
    pOtaCtrlChar = pService->createCharacteristic(
      CHAR_OTA_CTRL_UUID,
      BLECharacteristic::PROPERTY_WRITE |      // App写入控制指令
      BLECharacteristic::PROPERTY_READ |        // App可读取状态
      BLECharacteristic::PROPERTY_NOTIFY        // 固件主动推送进度
    );
    pOtaCtrlChar->addDescriptor(new BLE2902());
    pOtaCtrlChar->setCallbacks(new OtaCtrlCallbacks());
```

### 3.5 修改 setup() — 新固件启动确认

在 `setup()` 最开头（`Serial.begin` 之后）添加：

```cpp
    // ---- OTA启动确认 ----
    // 如果本次启动是OTA更新后的首次启动，需要确认新固件正常
    // 如果不确认，下次重启会回滚到旧固件 (安全机制)
    const esp_partition_t* running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;
    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
      if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
        // 新固件首次启动，确认有效 (不回滚)
        esp_ota_mark_app_valid_cancel_rollback();
        Serial.println("OTA: New firmware confirmed!");
      }
    }
```

需要额外 include：
```cpp
#include <esp_ota_ops.h>   // OTA分区操作
```

### 3.6 修改 loop() — OTA期间跳过正常逻辑

在 `loop()` 最开头添加：

```cpp
void loop() {
  unsigned long now = millis();

  // ---- OTA进行中: 跳过所有正常控制逻辑 ----
  // OTA期间只处理BLE通信 (接收固件数据)
  // 电机/灯光/音效/重联全部冻结
  if (otaInProgress) {
    // 安全保障: 确保电机停止
    applyMotorPWM(0, 0);
    digitalWrite(SOUND_POWER, LOW);

    // OTA超时保护: 如果60秒没有新数据，自动中止
    // (防止App崩溃后ESP32一直等待)
    if (millis() - otaLastProgressTime >= 60000) {
      Update.abort();
      otaInProgress = false;
      Serial.println("OTA timeout, aborted");
      if (deviceConnected) {
        pOtaCtrlChar->setValue("OTA:FAIL:TIMEOUT");
        pOtaCtrlChar->notify();
      }
    }
    return;  // 跳过后续所有逻辑
  }

  // ---- 以下为原有的正常loop逻辑 ----
  // (演示模式 / 电机状态机 / 音效 / 电池 / 重联 / BLE断连 / 状态上报)
  // ...
```

---

## 四、App 端 OTA 流程

### 4.1 升级流程图

```
App操作界面                    BLE通信                    ESP32固件
    │                           │                           │
  [选择固件文件.bin]              │                           │
    │                           │                           │
  [点击"升级"]                  │                           │
    ├── 读取文件大小 ──────────→│                           │
    │   写入OTA控制特征:         │                           │
    │   "OTA:BEGIN:184320"      │──────────────────────────→│
    │                           │                           ├─ 停车
    │                           │                           ├─ Update.begin()
    │                           │←──────────────────────────┤
    │   收到通知: "OTA:READY"   │                           │
    │                           │                           │
  [开始分包发送固件数据]          │                           │
    ├── 每包约500字节 ─────────→│                           │
    │   写入OTA数据特征          │──────────────────────────→│
    │   (Write Without Response) │                          ├─ Update.write()
    ├── 第2包 ─────────────────→│                           │
    ├── 第3包 ─────────────────→│                           │
    │   ...                     │                           │
    │                           │←──────────────────────────┤
    │   收到通知: "OTA:PROGRESS:25"                         │
    │   [更新进度条 25%]         │                           │
    │   ...                     │                           │
    │   收到通知: "OTA:PROGRESS:50"                         │
    │   ...                     │                           │
    │   收到通知: "OTA:PROGRESS:100"                        │
    │                           │                           │
  [数据发送完毕]                 │                           │
    ├── 写入OTA控制特征:         │                           │
    │   "OTA:END"               │──────────────────────────→│
    │                           │                           ├─ Update.end()
    │                           │                           ├─ MD5校验
    │                           │←──────────────────────────┤
    │   收到通知: "OTA:OK"      │                           │
    │                           │                           │
    │   [显示"升级成功，设备重启中"] │                        │
    │                           │          2秒后            │
    │                           │                           ├─ ESP.restart()
    │   [BLE断连]               │                           │
    │                           │                           │
    │   [等待重新发现设备]        │                           │
    │   [自动重连]              │                           │
    │                           │                           ├─ 新固件启动
    │                           │                           ├─ 确认有效
```

### 4.2 App 端伪代码

```javascript
async function performOTA(firmwareFile) {
  // 1. 读取固件文件
  const firmwareData = await readFile(firmwareFile);
  const fileSize = firmwareData.length;
  
  // 2. 发送开始指令
  await writeCharacteristic(OTA_CTRL_UUID, `OTA:BEGIN:${fileSize}`);
  
  // 3. 等待 "OTA:READY" 通知
  const ready = await waitForNotification(OTA_CTRL_UUID, 5000);
  if (ready !== "OTA:READY") {
    showError(ready);  // 显示错误 (如 "OTA:FAIL:STOP_FIRST")
    return;
  }
  
  // 4. 请求最大MTU (提高传输速度)
  await requestMTU(512);
  
  // 5. 分包发送固件数据
  const CHUNK_SIZE = 500;  // 略小于MTU，留安全余量
  for (let offset = 0; offset < fileSize; offset += CHUNK_SIZE) {
    const chunk = firmwareData.slice(offset, offset + CHUNK_SIZE);
    // 使用 Write Without Response 以获得最高速度
    await writeCharacteristicNoResponse(OTA_DATA_UUID, chunk);
    
    // 更新本地进度条 (不等待固件通知，App自行计算)
    updateProgress(offset / fileSize * 100);
  }
  
  // 6. 发送完成指令
  await writeCharacteristic(OTA_CTRL_UUID, "OTA:END");
  
  // 7. 等待校验结果
  const result = await waitForNotification(OTA_CTRL_UUID, 30000);
  if (result === "OTA:OK") {
    showSuccess("升级成功！设备正在重启...");
    // 设备会在2秒后重启，BLE会断开
    // App等待重新发现设备后自动重连
  } else {
    showError(`升级失败: ${result}`);
  }
}
```

---

## 五、固件版本管理

### 5.1 添加版本号

在代码头部添加：

```cpp
// ============================================================================
// 固件版本号
// ============================================================================
#define FIRMWARE_VERSION  "1.0.0"   // 主版本.次版本.修订
#define FIRMWARE_DATE     __DATE__  // 编译日期 (自动填充)
```

### 5.2 版本查询特征

新增一个只读特征，App可随时查询当前固件版本：

```cpp
#define CHAR_VERSION_UUID  "8c224e70-1b0a-4f66-b4c3-16e4c2e70394"

// 在setup()中添加:
BLECharacteristic* pVersionChar = pService->createCharacteristic(
  CHAR_VERSION_UUID,
  BLECharacteristic::PROPERTY_READ
);
char verBuf[40];
snprintf(verBuf, sizeof(verBuf), "FW:%s %s", FIRMWARE_VERSION, FIRMWARE_DATE);
pVersionChar->setValue(verBuf);
```

### 5.3 状态回报中加入版本

在 `sendStatus()` 中追加：

```cpp
pos += snprintf(buf + pos, sizeof(buf) - pos, " FW:%s", FIRMWARE_VERSION);
```

---

## 六、安全与回滚机制

```
┌─────────────────────────────────────────────────────────────┐
│  OTA 安全保障措施                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 传输前校验                                               │
│     └─ App检查文件大小是否超出分区容量 (1.3MB)                │
│                                                             │
│  2. 传输中保护                                               │
│     ├─ OTA期间电机强制停止 (loop中保障)                      │
│     ├─ 60秒无数据自动中止 (超时保护)                         │
│     └─ App可随时发 "OTA:ABORT" 中止                         │
│                                                             │
│  3. 写入后校验                                               │
│     └─ Update.end(true) 自动校验MD5                          │
│        校验失败 → 不切换分区, 不重启, 返回错误                │
│                                                             │
│  4. 启动后回滚                                               │
│     ├─ 新固件启动后必须调用 esp_ota_mark_app_valid()         │
│     ├─ 如果新固件崩溃(无法调用确认) → 看门狗重启             │
│     └─ 重启后自动回滚到旧固件 (app0分区)                     │
│                                                             │
│  5. 升级前置条件                                             │
│     ├─ 必须停车 (actualPWM==0)                               │
│     └─ OTA期间拒绝所有控制指令                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 七、完整文件变动清单

| 文件 | 变动类型 | 说明 |
|------|---------|------|
| `partitions_ota.csv` | **新增** | OTA双分区表 |
| `platformio.ini` | **修改** | 指定分区表文件 |
| 主代码 `.ino` | **修改** | 新增以下内容: |
| | | `#include <Update.h>` |
| | | `#include <esp_ota_ops.h>` |
| | | OTA UUID 定义 |
| | | OTA 状态变量 |
| | | `OtaCtrlCallbacks` 类 |
| | | `OtaDataCallbacks` 类 |
| | | `setup()` 中注册OTA特征 |
| | | `setup()` 中OTA启动确认 |
| | | `loop()` 开头OTA跳过逻辑 |
| | | `FIRMWARE_VERSION` 定义 |
| | | 版本查询特征 |

**不影响现有功能**：所有OTA代码仅在收到 `OTA:BEGIN` 时激活，正常运行时零开销。




# 代码优化


我从**代码体积、运行效率、功能健壮性**三个维度逐一分析，给出具体改动。

---

## 一、优化总览

| 类别 | 优化点 | 效果 |
|------|--------|------|
| **体积** | 统一字符串构建、消除重复代码 | 预计减少 15~30KB |
| **体积** | 编译期调试开关 | 发布版减少 Serial 字符串占用 |
| **健壮性** | 状态回报缓冲区溢出保护 | 防崩溃 |
| **健壮性** | ESP-NOW 发送失败处理 | 防丢包后状态不一致 |
| **健壮性** | BLE 重连时状态同步 | App 重连后立刻拿到完整状态 |
| **体验** | kickstart 后平滑过渡（而非跳变） | 起步更丝滑 |
| **体验** | 电池低电量警告 | 提前提醒用户换电池 |
| **效率** | 减少 loop() 中的冗余计算 | 降低 CPU 开销 |
| **效率** | ADC 采样优化 | 更准确的电压读数 |

---

## 二、完整优化后代码

```cpp
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
```

---

## 三、优化点详细说明

### 1. 编译期调试开关

```cpp
// 发布时只需改一行:
#define DEBUG_ENABLED  0
// 所有 DBG() DBGF() 编译期消除，节省 Flash 中的字符串常量
```

**效果**：发布版预计减少 3~8KB Flash 占用。

### 2. kickstart 后平滑过渡

```
旧逻辑:  255(kick) ──→ 跳到214(目标)  ← 有感知的顿挫
新逻辑:  255(kick) ──→ 坡道 251→247→...→214  ← 丝滑过渡
```

### 3. 统一灯光入口

旧代码有 3 个独立的灯光函数 + 1 个补机灯光计算函数，存在重复逻辑。
新代码合并为 `updateLights()` + `setEndLight()`，一个入口处理所有角色。

### 4. 音效变化检测

```cpp
// 旧: 每次 loop 都 digitalWrite (即使值没变)
updateSound();

// 新: 仅在 PWM 变化时才写 GPIO
if (actualPWM != prevActualPWM) {
  updateSound();
  prevActualPWM = actualPWM;
}
```

### 5. ADC 中值滤波

```cpp
// 旧: 单次读取，容易受尖刺干扰
uint16_t raw = analogRead(BATT_ADC);

// 新: 读5次取中值，消除异常值
uint16_t raw = adcReadMedian(BATT_ADC, 5);
```

### 6. 解联重试机制

```
旧: 发一次解联包，如果补机没收到就卡住
新: 发送后启动重试 (3次×200ms)，超时后强制解联
```

### 7. BLE 重连立即推送

```cpp
// 旧: 重连后要等下一个200ms周期才能拿到状态
// 新: 检测到重连事件立即 sendStatus()
if (!wasConnected && deviceConnected) {
  sendStatus();  // 立即同步
}
```

### 8. 低电量警告

状态回报中新增 `BLOW:1` 字段（电量≤10%时出现），App 可弹窗提醒。

### 9. 指令解析优化

```cpp
// 旧: 多次 startsWith() 比较
if (val.startsWith("F:")) ...
if (val.startsWith("R:")) ...

// 新: 首字符快速分发
char c0 = v.charAt(0);
if ((c0 == 'F' || c0 == 'R') && v.charAt(1) == ':') ...
```




# App 开发提示词

你可以将以下提示词完整发给 AI 编程助手（如 Cursor / Claude），让它帮你从零开发。

---

## 提示词

```
你是一位资深 Flutter 开发工程师，精通 BLE 蓝牙通信、自定义绘制（CustomPainter）
和复杂动效开发。

请帮我开发一个 Flutter App，用于蓝牙遥控玩具火车。App 同时支持安卓和 iOS。

这个 App 的界面风格是【工业仪表盘】，模拟真实机车驾驶台的深色金属质感面板。
我会提供一份 HTML/CSS 参考设计稿，你需要用 Flutter 完整还原其视觉效果和交互逻辑，
并接入真实的 BLE 蓝牙通信。

==============================
一、项目概述
==============================

这是一个 BLE 蓝牙遥控火车的手机控制端。火车端使用 ESP32-C3，通过 BLE 与手机通信。
每台手机同一时间只连接一台火车。
一台火车可能是独立运行，也可能与另一台火车通过 ESP-NOW 重联运行（本务机+补机）。
手机端需要根据火车的角色状态（独立/本务机/补机）切换不同的 UI 界面。

==============================
二、技术要求
==============================

1. 框架: Flutter（最新稳定版）
2. BLE 库: flutter_blue_plus（最新版）
3. 状态管理: Riverpod
4. 屏幕方向: 强制横屏（landscape）
5. 最低支持: Android 6.0 / iOS 12
6. 权限: 蓝牙、定位（BLE扫描需要）
7. 字体: Google Fonts — Orbitron(数字/标题)、Rajdhani(副标题/单位)、Roboto(正文)
8. 自定义绘制: 速度表盘和方向拨盘必须使用 CustomPainter 实现

==============================
三、BLE 通信协议
==============================

3.1 连接参数:
- 设备名称过滤: "BLE_Train"
- 服务 UUID: "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
- 控制特征 UUID: "beb5483e-36e1-4688-b7f5-ea07361b26a8"
  （可写: Write + Write Without Response）
  （App 向火车发送指令）
- 状态特征 UUID: "8c224e70-1b0a-4f66-b4c3-16e4c2e70391"
  （可读 + 可通知 Notify）
  （火车向 App 上报状态，约每200ms一次）
- 版本特征 UUID: "8c224e70-1b0a-4f66-b4c3-16e4c2e70394"
  （只读，固件版本号）

3.2 App → 火车 指令格式（字符串）:

  F:1 ~ F:8    前进，档位1(最慢)~8(全速)
  R:1 ~ R:8    后退，档位1~8
  S            停车（平滑减速）
  L            车头灯切换（开↔关）
  L:0          车头灯关
  L:1          车头灯开
  M            音效总开关切换（开↔关）
  M:0          音效关
  M:1          音效开
  C            换端（整列换端，必须停车）
  CP           发起重联邀请（开始 ESP-NOW 广播）
  CP:STOP      取消重联邀请
  J:A          接受重联邀请，以A端连接
  J:B          接受重联邀请，以B端连接
  U            解除重联（仅本务机可执行，必须停车）
  K:0.95       设置补机速度系数（0.90~1.10）

3.3 火车 → App 状态格式（字符串，空格分隔的 key:value 对）:

  正常状态示例:
  "CAB:A HL:ON DIR:FWD LV:5 APWM:214 TPWM:228 SE:ON SND:ON DM:OFF BAT:78 BATV:4.12 CP:OFF FW:1.1.0"

  本务机重联示例:
  "CAB:A HL:ON DIR:FWD LV:5 APWM:214 TPWM:228 SE:ON SND:ON DM:OFF BAT:78 BATV:4.12 CP:MASTER SC:A SAPWM:210 SBAT:65 SBATV:3.89 SK:0.95 FW:1.1.0"

  补机示例:
  "CAB:A HL:OFF DIR:FWD LV:5 APWM:210 TPWM:214 SE:ON SND:ON BAT:65 BATV:3.89 CP:SLAVE FW:1.1.0"

  收到邀请示例:
  "... CP:INVITED INV:AA:BB:CC:DD:EE:FF ..."

  错误示例:
  "ERR:STOP_FIRST"
  "ERR:SLAVE_MODE"
  "ERR:DEMO_STOPPING"
  "ERR:ALREADY_COUPLED"
  "ERR:NOT_COUPLED"
  "ERR:INVALID_COEFF"

  字段说明:
    CAB:A/B          当前驾驶端
    HL:ON/OFF        车头灯状态
    DIR:STOP/FWD/REV 物理运行方向
    LV:0~8           目标档位
    APWM:0~255       实际PWM（实时变化，反映加减速过程）
    TPWM:0~255       目标PWM
    SE:ON/OFF        音效总开关
    SND:ON/OFF       音效实际播放状态
    DM:ON/OFF        演示模式
    BAT:0~100        电池百分比
    BATV:x.xx        电池电压(V)
    BLOW:1           低电量警告（电量≤10%时出现）
    CP:OFF           未重联
    CP:INVITING      正在广播邀请
    CP:INVITED       收到重联邀请
    CP:MASTER        本务机模式
    CP:SLAVE         补机模式
    INV:XX:XX:...    邀请来源MAC（仅INVITED状态）
    SC:A/B           补机连接端（仅MASTER）
    SAPWM:0~255      补机实际PWM（仅MASTER）
    SBAT:0~100       补机电量（仅MASTER）
    SBATV:x.xx       补机电压（仅MASTER）
    SK:0.90~1.10     速度系数（仅MASTER）
    SWARN:1          补机通信异常警告（仅MASTER）
    FW:x.x.x         固件版本号

==============================
四、UI 视觉参考（HTML设计稿）
==============================

以下是完整的 HTML/CSS/JS 设计稿。你需要用 Flutter 精确还原这个界面的视觉效果，
包括金属质感、发光效果、阴影层次、动效等。
但是需要把原设计中的模拟数据替换为真实的 BLE 数据驱动。

--- HTML 设计稿开始 ---

<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Train Control Panel - Dual Loco Simulator</title>
<style>
    @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@500;700;900&family=Rajdhani:wght@500;700;900&family=Roboto:wght@400;700&display=swap');

    :root {
        --bg-color: #1a1b1f;
        --panel-bg: #222429;
        --metal-dark: #111;
        --metal-light: #444;
        --text-dim: #4a505c;
        --glow-green: #2ecc71;
        --glow-red: #e74c3c;
        --glow-blue: #3498db;
        --glow-orange: #f39c12;
        --glow-cyan: #00bcd4;
        --mu-glow: #0fdb8a;
    }

    * { box-sizing: border-box; user-select: none; }

    body {
        background-color: #050505;
        background-image: radial-gradient(circle at 50% 50%, #1a1a24 0%, #000 100%);
        display: flex; flex-direction: column; justify-content: center; align-items: center;
        min-height: 100vh; margin: 0; font-family: 'Roboto', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        overflow: hidden; gap: 20px;
    }

    /* --- Top Status Bar --- */
    .top-status-bar {
        width: 1260px; height: 60px;
        background: linear-gradient(180deg, #1c1f24, #0a0b0d);
        border: 2px solid #111; border-radius: 8px;
        box-shadow: inset 0 2px 3px rgba(255,255,255,0.05), 0 10px 20px rgba(0,0,0,0.8);
        display: flex; justify-content: space-between; align-items: center; padding: 0 40px; position: relative;
    }
    
    .status-item { font-size: 15px; color: #7a8291; font-weight: bold; display: flex; align-items: center; gap: 10px; }

    .lcd-select {
        background-color: #0a0e14; color: #58a6ff; border: 1px solid #000;
        box-shadow: inset 0 3px 8px rgba(0,0,0,0.9), 0 1px 0 rgba(255,255,255,0.1);
        padding: 4px 25px 4px 10px; border-radius: 4px;
        font-family: 'Orbitron', 'Microsoft YaHei', sans-serif; font-size: 15px; font-weight: 700;
        text-shadow: 0 0 8px rgba(88, 166, 255, 0.5); letter-spacing: 1px; appearance: none; outline: none; cursor: pointer;
        background-image: url('data:image/svg+xml;utf8,<svg fill="%2358a6ff" height="20" viewBox="0 0 24 24" width="20" xmlns="http://www.w3.org/2000/svg"><path d="M7 10l5 5 5-5z"/><path d="M0 0h24v24H0z" fill="none"/></svg>');
        background-repeat: no-repeat; background-position: right 2px center;
    }
    .lcd-select option { background-color: #111; color: #58a6ff; font-family: 'Orbitron', sans-serif; }

    .lcd-display { background-color: #0a0e14; border: 1px solid #000; border-radius: 4px; box-shadow: inset 0 3px 8px rgba(0,0,0,0.9), 0 1px 0 rgba(255,255,255,0.1); padding: 4px 10px; display: flex; align-items: center; gap: 6px; font-family: 'Orbitron', sans-serif; font-size: 16px; font-weight: 700; }
    .text-cyan { color: var(--glow-cyan); text-shadow: 0 0 8px rgba(0, 188, 212, 0.6); }
    .text-green { color: var(--glow-green); text-shadow: 0 0 8px rgba(46, 204, 113, 0.6); }
    .unit-small { font-size: 10px; font-family: 'Rajdhani', sans-serif; opacity: 0.8; }
    
    .batt-icon { width: 24px; height: 12px; border: 1.5px solid var(--glow-green); border-radius: 2px; position: relative; padding: 1px; display: flex; align-items: stretch; box-shadow: 0 0 5px rgba(46, 204, 113, 0.4); }
    .batt-icon::after { content: ''; position: absolute; right: -4px; top: 2px; width: 2px; height: 4px; background: var(--glow-green); border-radius: 0 1px 1px 0; }
    .batt-fill { width: 98%; background: var(--glow-green); box-shadow: 0 0 5px var(--glow-green); }

    .status-val { font-family: 'Rajdhani', 'Microsoft YaHei', sans-serif; font-size: 15px; font-weight: 700; padding: 4px 10px; border-radius: 4px; background: #111; color: #555; box-shadow: inset 0 2px 5px #000; transition: all 0.3s ease; min-width: 90px; text-align: center; border-bottom: 2px solid #222; }
    .status-val.cab-a { color: #fff; background: rgba(46, 204, 113, 0.15); text-shadow: 0 0 8px var(--glow-green); border-bottom-color: var(--glow-green); }
    .status-val.cab-b { color: #fff; background: rgba(243, 156, 18, 0.15); text-shadow: 0 0 8px var(--glow-orange); border-bottom-color: var(--glow-orange); }
    .status-val.mu-indep { color: #aaa; background: #111; border-bottom-color: #444; }
    .status-val.mu-coupled { color: #fff; background: rgba(231, 76, 60, 0.15); text-shadow: 0 0 8px var(--glow-red); border-bottom-color: var(--glow-red); }

    /* --- Main Container --- */
    .dashboard { width: 1260px; height: 800px; background: linear-gradient(135deg, #2a2d34 0%, #15161a 100%); border-radius: 12px; padding: 20px; display: flex; gap: 20px; box-shadow: 0 20px 50px rgba(0,0,0,0.8), inset 0 2px 2px rgba(255,255,255,0.1); position: relative; }
    .screw { position: absolute; width: 16px; height: 16px; background: radial-gradient(circle at center, #555 0%, #222 70%, #111 100%); border-radius: 50%; box-shadow: inset 0 1px 1px rgba(255,255,255,0.3), 0 2px 4px rgba(0,0,0,0.8); }
    .screw::after { content: ''; position: absolute; top: 50%; left: 50%; width: 10px; height: 2px; background: #111; transform: translate(-50%, -50%) rotate(45deg); box-shadow: 0 1px 0 rgba(255,255,255,0.2); }
    .panel { background: linear-gradient(180deg, #25282e 0%, #1a1c20 100%); border-radius: 8px; border: 2px solid #111; box-shadow: inset 0 2px 3px rgba(255,255,255,0.05), inset 0 -2px 5px rgba(0,0,0,0.5), 0 10px 15px rgba(0,0,0,0.5); position: relative; display: flex; flex-direction: column; align-items: center; }

    .panel-left { flex: 1; padding: 40px 30px; justify-content: space-between; }
    .panel-center { flex: 1.3; padding: 40px 20px; justify-content: space-between; }
    .panel-right { flex: 1; padding: 30px; justify-content: space-between; gap: 20px; }

    /* --- Left Panel: Direction --- */
    .dir-display-board { width: 100%; background: #0a0b0d; border-radius: 6px; padding: 15px; display: flex; flex-direction: column; gap: 12px; border: 2px solid #111; box-shadow: inset 0 5px 15px rgba(0,0,0,0.9), 0 2px 5px rgba(255,255,255,0.05); }
    .dir-label { font-family: 'Rajdhani', 'Microsoft YaHei', sans-serif; font-size: 18px; font-weight: 700; color: var(--text-dim); display: flex; justify-content: space-between; align-items: center; padding: 6px 10px; border-radius: 4px; background: #111; transition: all 0.3s; border: 1px solid transparent; }
    .fsr-badge { width: 28px; height: 28px; background: #222; border-radius: 4px; border: 1px solid #000; display: flex; justify-content: center; align-items: center; font-family: 'Orbitron', sans-serif; font-weight: 900; font-size: 16px; color: #555; box-shadow: inset 0 1px 2px rgba(255,255,255,0.1), 0 2px 4px rgba(0,0,0,0.5); transition: all 0.3s; }
    .dir-label .text-group { display: flex; flex-direction: column; line-height: 1; flex: 1; margin-left: 15px; }
    .dir-label span.eng { font-size: 12px; opacity: 0.7; margin-top: 3px; }
    .dir-label .indicator { width: 12px; height: 12px; border-radius: 50%; background: #222; box-shadow: inset 0 1px 3px #000; transition: all 0.3s;}
    .dir-label.active-fwd { color: #fff; background: rgba(52, 152, 219, 0.1); border-color: rgba(52, 152, 219, 0.3); } .dir-label.active-fwd .indicator { background: var(--glow-blue); box-shadow: 0 0 12px var(--glow-blue); } .dir-label.active-fwd .fsr-badge { background: var(--glow-blue); color: #000; box-shadow: 0 0 10px var(--glow-blue), inset 0 1px 2px rgba(255,255,255,0.5); text-shadow: none; border-color: transparent; }
    .dir-label.active-neu { color: #fff; background: rgba(46, 204, 113, 0.1); border-color: rgba(46, 204, 113, 0.3); } .dir-label.active-neu .indicator { background: var(--glow-green); box-shadow: 0 0 12px var(--glow-green); } .dir-label.active-neu .fsr-badge { background: var(--glow-green); color: #000; box-shadow: 0 0 10px var(--glow-green), inset 0 1px 2px rgba(255,255,255,0.5); text-shadow: none; border-color: transparent; }
    .dir-label.active-rev { color: #fff; background: rgba(231, 76, 60, 0.1); border-color: rgba(231, 76, 60, 0.3); } .dir-label.active-rev .indicator { background: var(--glow-red); box-shadow: 0 0 12px var(--glow-red); } .dir-label.active-rev .fsr-badge { background: var(--glow-red); color: #000; box-shadow: 0 0 10px var(--glow-red), inset 0 1px 2px rgba(255,255,255,0.5); text-shadow: none; border-color: transparent; }

    .dial-container { display: flex; flex-direction: column; align-items: center; gap: 20px; }
    .dial-title { font-family: 'Orbitron', sans-serif; color: var(--text-dim); font-size: 14px; letter-spacing: 3px; }
    .dial-wrapper { width: 220px; height: 220px; border-radius: 50%; background: linear-gradient(145deg, #2a2d34, #1a1c20); box-shadow: inset 0 5px 15px rgba(0,0,0,0.8), 0 5px 10px rgba(0,0,0,0.5), 0 0 0 2px #000; display: flex; justify-content: center; align-items: center; position: relative; cursor: pointer; }
    .dial-wrapper::before { content: ''; position: absolute; width: 180px; height: 180px; border-radius: 50%; background: radial-gradient(#222, #111); box-shadow: inset 0 2px 10px #000; border: 1px solid #333; }
    .dial-mark { position: absolute; top: 12px; left: 50%; width: 20px; height: 98px; margin-left: -10px; transform-origin: bottom center; display: flex; flex-direction: column; align-items: center; z-index: 10; pointer-events: none; }
    .dial-mark span { font-family: 'Orbitron', sans-serif; font-size: 16px; font-weight: 900; color: #555; transition: all 0.3s; margin-bottom: 3px; }
    .dial-mark .tick-line { width: 3px; height: 12px; background: #333; border-radius: 2px; box-shadow: inset 0 1px 2px #000, 0 1px 0 rgba(255,255,255,0.1); transition: all 0.3s; }
    .mark-f { transform: rotate(-45deg); } .mark-f span { transform: rotate(45deg); }
    .mark-s { transform: rotate(0deg); } .mark-s span { transform: rotate(0deg); }
    .mark-r { transform: rotate(45deg); } .mark-r span { transform: rotate(-45deg); }
    .state-fwd .mark-f span { color: var(--glow-blue); text-shadow: 0 0 10px var(--glow-blue); } .state-fwd .mark-f .tick-line { background: var(--glow-blue); box-shadow: 0 0 10px var(--glow-blue); }
    .state-neu .mark-s span { color: var(--glow-green); text-shadow: 0 0 10px var(--glow-green); } .state-neu .mark-s .tick-line { background: var(--glow-green); box-shadow: 0 0 10px var(--glow-green); }
    .state-rev .mark-r span { color: var(--glow-red); text-shadow: 0 0 10px var(--glow-red); } .state-rev .mark-r .tick-line { background: var(--glow-red); box-shadow: 0 0 10px var(--glow-red); }
    .dial-knob { width: 100px; height: 100px; border-radius: 50%; background: linear-gradient(135deg, #444, #222); box-shadow: 0 10px 20px rgba(0,0,0,0.8), inset 0 2px 3px rgba(255,255,255,0.2), 0 0 0 4px #111; position: relative; z-index: 2; transition: transform 0.3s cubic-bezier(0.4, 0.0, 0.2, 1); transform: rotate(0deg); }
    .dial-knob::after { content: ''; position: absolute; bottom: 50%; left: 50%; transform: translateX(-50%); width: 24px; height: 75px; background: linear-gradient(90deg, #555, #888, #333); border-radius: 4px 4px 0 0; box-shadow: 3px 0 5px rgba(0,0,0,0.6), inset 0 1px 2px rgba(255,255,255,0.4), inset 0 0 0 1px #222; z-index: -1; }
    .dial-pointer-line { position: absolute; bottom: 85%; left: 50%; transform: translateX(-50%); width: 4px; height: 20px; background: #e74c3c; border-radius: 2px; z-index: 3; box-shadow: inset 0 1px 2px #000; }
    .dial-knob::before { content: ''; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); width: 60px; height: 60px; border-radius: 50%; background: radial-gradient(circle at top left, #555, #222); box-shadow: inset 0 2px 4px rgba(255,255,255,0.2), 0 4px 8px rgba(0,0,0,0.8); z-index: 5; }

    /* --- Center Panel: Speedometer --- */
    .speedo-container { width: 320px; height: 320px; border-radius: 50%; background: #111; box-shadow: inset 0 0 20px #000, 0 5px 15px rgba(0,0,0,0.5), 0 0 0 10px #2a2d34, 0 0 0 12px #111; position: relative; display: flex; justify-content: center; align-items: center; }
    .speedo-bg { width: 280px; height: 280px; border-radius: 50%; position: relative; background: radial-gradient(circle at center, #1a2a3a 0%, #0a1118 80%, #05080c 100%); }
    .speedo-ticks { position: absolute; width: 100%; height: 100%; top: 0; left: 0; }
    .tick { position: absolute; bottom: 50%; left: 50%; width: 2px; height: 12px; background: #fff; transform-origin: bottom center; }
    .tick.major { width: 3px; height: 18px; background: #88c0d0; }
    .tick-num { position: absolute; font-family: 'Rajdhani', sans-serif; color: #e5e9f0; font-weight: 700; font-size: 18px; transform: translate(-50%, -50%); }
    .digital-speed { position: absolute; top: 72%; left: 50%; transform: translate(-50%, 0); text-align: center; z-index: 5; background: rgba(0,0,0,0.6); padding: 5px 20px; border-radius: 6px; border: 1px solid #222; box-shadow: inset 0 2px 5px #000; }
    .digital-num { font-family: 'Orbitron', sans-serif; font-size: 45px; color: #fff; text-shadow: 0 0 10px rgba(255,255,255,0.5); line-height: 1; }
    .digital-unit { font-family: 'Rajdhani', sans-serif; font-size: 15px; color: #88c0d0; letter-spacing: 2px; margin-top: 2px;}
    .needle-container { position: absolute; top: 0; left: 0; width: 100%; height: 100%; transform: rotate(-130deg); transition: transform 0.1s linear; z-index: 10; }
    .needle { position: absolute; bottom: 50%; left: 50%; width: 4px; height: 120px; background: linear-gradient(to top, transparent 0%, var(--glow-red) 20%, #ff7675 100%); transform: translateX(-50%); transform-origin: bottom center; filter: drop-shadow(0 0 8px var(--glow-red)); }
    .needle-center { position: absolute; top: 50%; left: 50%; width: 35px; height: 35px; background: radial-gradient(circle, #555, #111); border-radius: 50%; transform: translate(-50%, -50%); box-shadow: 0 5px 10px rgba(0,0,0,0.8), inset 0 2px 2px rgba(255,255,255,0.3); }

    /* --- Center Panel: Button Grid --- */
    .btn-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; padding: 0 10px; width: 100%; }
    .grid-btn { width: 100%; height: 75px; background: linear-gradient(180deg, #35383f, #1e2025); border-radius: 8px; border: 2px solid #111; box-shadow: 0 6px 10px rgba(0,0,0,0.6), inset 0 2px 2px rgba(255,255,255,0.1); display: flex; flex-direction: column; justify-content: space-between; align-items: center; padding: 12px 0; cursor: pointer; position: relative; transition: transform 0.1s, box-shadow 0.1s; }
    .grid-btn:active { transform: translateY(3px); box-shadow: 0 2px 4px rgba(0,0,0,0.8), inset 0 2px 5px rgba(0,0,0,0.5); }
    .grid-btn span { font-size: 15px; font-weight: 700; color: #a0aabf; letter-spacing: 2px; text-shadow: 0 -1px 1px #000; }
    .btn-indicator { width: 28px; height: 5px; border-radius: 2px; background: #111; box-shadow: inset 0 1px 2px #000; transition: all 0.2s; }
    
    .grid-btn.active.color-orange .btn-indicator { background: var(--glow-orange); box-shadow: 0 0 10px var(--glow-orange); }
    .grid-btn.active.color-blue .btn-indicator { background: var(--glow-blue); box-shadow: 0 0 10px var(--glow-blue); }
    .grid-btn.active.color-green .btn-indicator { background: var(--glow-green); box-shadow: 0 0 10px var(--glow-green); }
    .grid-btn.active.color-red .btn-indicator { background: var(--glow-red); box-shadow: 0 0 10px var(--glow-red); }

    /* --- Center Panel: Emergency Stop --- */
    .estop-wrapper { position: relative; display: flex; align-items: center; justify-content: center; width: 180px; height: 120px; }
    .estop-guard { position: absolute; width: 140px; height: 90px; border: 8px solid #aab1bd; border-radius: 20px; box-shadow: inset 0 5px 5px rgba(255,255,255,0.2), inset 0 -5px 5px rgba(0,0,0,0.5), 0 10px 15px rgba(0,0,0,0.8); background: linear-gradient(180deg, rgba(255,255,255,0.1), transparent); z-index: 1; pointer-events: none; }
    .estop-btn { width: 100px; height: 100px; border-radius: 50%; background: radial-gradient(circle at center, #ff4757 0%, #c0392b 60%, #8b0000 100%); box-shadow: 0 10px 20px rgba(0,0,0,0.8), inset 0 5px 10px rgba(255,100,100,0.5), 0 0 0 5px #111; display: flex; flex-direction: column; justify-content: center; align-items: center; cursor: pointer; z-index: 2; transition: all 0.1s; }
    .estop-btn:active, .estop-btn.pressed { transform: scale(0.95) translateY(5px); box-shadow: 0 2px 5px rgba(0,0,0,0.8), inset 0 5px 15px rgba(0,0,0,0.8), 0 0 0 5px #111, 0 0 30px var(--glow-red); }
    .estop-btn span.small { font-size: 10px; color: #fff; opacity: 0.8; letter-spacing: 1px; }
    .estop-btn span.big { font-family: 'Orbitron', sans-serif; font-size: 24px; font-weight: 700; color: #fff; text-shadow: 0 2px 4px rgba(0,0,0,0.8); }

    /* --- Right Panel: M.U. Monitor --- */
    .mu-monitor {
        width: 100%; height: 150px; background: #070e14; border: 2px solid #111; border-radius: 8px;
        box-shadow: inset 0 3px 15px rgba(0,0,0,0.9), 0 5px 10px rgba(0,0,0,0.5); padding: 12px 15px;
        display: flex; flex-direction: column; justify-content: space-between;
        font-family: 'Orbitron', 'Microsoft YaHei', sans-serif; color: var(--mu-glow); text-shadow: 0 0 6px var(--mu-glow);
        position: relative; transition: all 0.4s ease; overflow: hidden;
    }
    .mu-monitor::before { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; background: repeating-linear-gradient(0deg, rgba(0,0,0,0.15), rgba(0,0,0,0.15) 1px, transparent 1px, transparent 2px); z-index: 2; }
    .mu-monitor.off { filter: grayscale(0.8) brightness(0.4); pointer-events: none; }

    .mu-row { display: flex; justify-content: space-between; align-items: center; position: relative; z-index: 3; }
    .mu-text { font-size: 13px; font-weight: 700; letter-spacing: 0.5px; }
    .mu-title { cursor: pointer; padding: 2px 5px; border-radius: 3px; transition: background 0.2s; font-size: 14px;}
    .mu-title:hover { background: rgba(15, 219, 138, 0.2); }
    
    .mu-speed-box { flex: 1; margin: 0 10px; height: 12px; background: #000; border: 1px solid #111; border-radius: 2px; box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); position: relative; }
    .mu-speed-fill { height: 100%; width: 0%; background: repeating-linear-gradient(45deg, var(--mu-glow), var(--mu-glow) 5px, #0a8a56 5px, #0a8a56 10px); box-shadow: 0 0 8px var(--mu-glow); transition: width 0.1s linear; }
    .mu-speed-val { font-size: 14px; min-width: 55px; text-align: right; }

    .mu-coef-wrap { display: flex; flex-direction: column; width: 100%; gap: 8px; margin-top: 5px; position: relative; z-index: 3;}
    .mu-coef-top { display: flex; justify-content: space-between; align-items: center; }
    .mu-slider-container { display: flex; align-items: center; gap: 8px; width: 100%; }
    .mu-slider-container input[type=range] { flex: 1; appearance: none; background: transparent; height: 20px; }
    .mu-slider-container input[type=range]::-webkit-slider-runnable-track { width: 100%; height: 4px; background: #111; border: 1px solid #000; border-radius: 2px; }
    .mu-slider-container input[type=range]::-webkit-slider-thumb { appearance: none; width: 14px; height: 14px; background: var(--mu-glow); border-radius: 50%; margin-top: -6px; cursor: pointer; box-shadow: 0 0 8px var(--mu-glow); }
    
    .mu-ctrl-btn { background: #000; border: 1px solid var(--mu-glow); color: var(--mu-glow); border-radius: 4px; padding: 2px 8px; font-family: inherit; font-size: 11px; font-weight: bold; cursor: pointer; box-shadow: inset 0 0 5px rgba(15, 219, 138, 0.2); transition: all 0.1s; }
    .mu-ctrl-btn:active { background: var(--mu-glow); color: #000; }

    .mu-warn-overlay { position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(20, 0, 0, 0.85); color: #ff3333; display: flex; justify-content: center; align-items: center; font-size: 18px; font-weight: 900; letter-spacing: 2px; text-shadow: 0 0 15px #ff3333; z-index: 10; animation: flashWarn 1s infinite alternate; border: 2px solid #ff3333; border-radius: 6px; }
    @keyframes flashWarn { 0% { opacity: 1; background: rgba(50, 0, 0, 0.9); } 100% { opacity: 0.6; background: rgba(20, 0, 0, 0.85); } }

    /* --- Right Panel: Throttle --- */
    .throttle-wrapper { display: flex; gap: 30px; height: 500px; align-items: center; justify-content: center; width: 100%; }
    .lever-container { width: 120px; height: 500px; background: #1e2126; border-radius: 10px; border: 2px solid #111; box-shadow: inset 0 0 20px #000, 0 10px 20px rgba(0,0,0,0.5); position: relative; display: flex; justify-content: center; }
    .lever-slot { width: 40px; height: 460px; background: #000; border-radius: 20px; margin-top: 20px; box-shadow: inset 0 5px 15px #000, 0 0 0 2px #333; position: relative; }
    .grooves { position: absolute; left: -20px; width: 20px; height: 100%; display: flex; flex-direction: column; justify-content: space-between; padding: 20px 0; }
    .groove { width: 15px; height: 8px; background: #111; border-radius: 4px 0 0 4px; box-shadow: inset 0 2px 2px rgba(255,255,255,0.1), 0 2px 2px #000; }
    .lever-handle { position: absolute; width: 160px; height: 40px; background: linear-gradient(180deg, #6c7a89, #34495e, #111); border-radius: 20px; left: -60px; bottom: 20px; box-shadow: 0 15px 25px rgba(0,0,0,0.9), inset 0 5px 10px rgba(255,255,255,0.4); cursor: grab; z-index: 10; display: flex; align-items: center; justify-content: space-between; padding: 0 5px; transition: bottom 0.1s; }
    .lever-handle:active { cursor: grabbing; }
    .handle-cap { width: 15px; height: 30px; background: linear-gradient(90deg, #888, #ccc, #555); border-radius: 5px; box-shadow: inset 0 0 5px #000; }
    .lever-stem { position: absolute; width: 20px; height: 40px; background: linear-gradient(90deg, #444, #777, #333); left: 50%; top: -20px; transform: translateX(-50%); z-index: -1; box-shadow: 0 5px 10px #000; }
    input[type=range].hidden-slider { position: absolute; writing-mode: bt-lr; -webkit-appearance: slider-vertical; width: 60px; height: 460px; opacity: 0; cursor: pointer; z-index: 20; margin: 0; top: 20px; left: -10px; }

    .led-system { display: flex; flex-direction: column; align-items: center; gap: 10px; height: 500px; }
    .led-bar { width: 30px; height: 460px; background: #111; border-radius: 10px; padding: 10px 5px; display: flex; flex-direction: column-reverse; justify-content: space-between; box-shadow: inset 0 0 10px #000, 0 0 0 2px #2a2d34; }
    .led-segment { width: 100%; height: 40px; background: #111; border-radius: 5px; box-shadow: inset 0 2px 5px #000; transition: background 0.1s, box-shadow 0.1s; }
    .led-labels { height: 460px; display: flex; flex-direction: column-reverse; justify-content: space-between; font-family: 'Rajdhani', sans-serif; font-weight: 700; color: #fff; padding: 10px 0; }
    .notch-label { font-size: 14px; line-height: 1; text-align: center; height: 40px; display: flex; flex-direction: column; justify-content: center; }
    .notch-label span { font-size: 20px; }
    .label-red { color: #ff4757; text-shadow: 0 0 5px #ff4757; }
    .label-yellow { color: #f1c40f; text-shadow: 0 0 5px #f1c40f; }
    .label-green { color: #2ecc71; text-shadow: 0 0 5px #2ecc71; }
</style>
</head>
<body>

<!-- TOP STATUS BAR -->
<div class="top-status-bar">
    <div class="status-item">车辆 
        <select class="lcd-select" id="train-selector">
            <option value="CR400AF">CR400AF-2046 复兴号</option>
        </select>
    </div>
    <div class="status-item">电压
        <div class="lcd-display text-cyan"><span id="lcd-volt">110.4</span><span class="unit-small">V</span></div>
    </div>
    <div class="status-item">电量
        <div class="lcd-display text-green">
            <div class="batt-icon"><div class="batt-fill"></div></div>
            <span id="lcd-batt">98</span><span class="unit-small">%</span>
        </div>
    </div>
    <div class="status-item">端位 <span class="status-val cab-a" id="top-status-cab">A端 CAB-A</span></div>
    <div class="status-item">编组 <span class="status-val mu-indep" id="top-status-mu">独立 INDEP</span></div>
</div>

<!-- MAIN DASHBOARD -->
<div class="dashboard">
    <div class="screw" style="top:10px; left:10px;"></div><div class="screw" style="top:10px; right:10px;"></div>
    <div class="screw" style="bottom:10px; left:10px;"></div><div class="screw" style="bottom:10px; right:10px;"></div>

    <!-- LEFT PANEL -->
    <div class="panel panel-left">
        <div class="screw" style="top:10px; left:10px;"></div><div class="screw" style="top:10px; right:10px;"></div>
        <div class="screw" style="bottom:10px; left:10px;"></div><div class="screw" style="bottom:10px; right:10px;"></div>

        <div class="dir-display-board">
            <div class="dir-label" id="lbl-fwd">
                <div class="fsr-badge">F</div>
                <div class="text-group"><div>前进</div><span class="eng">FORWARD</span></div>
                <div class="indicator"></div>
            </div>
            <div class="dir-label active-neu" id="lbl-neu">
                <div class="fsr-badge">S</div>
                <div class="text-group"><div>停车</div><span class="eng">STOP</span></div>
                <div class="indicator"></div>
            </div>
            <div class="dir-label" id="lbl-rev">
                <div class="fsr-badge">R</div>
                <div class="text-group"><div>后退</div><span class="eng">REVERSE</span></div>
                <div class="indicator"></div>
            </div>
        </div>

        <div class="dial-container">
            <div class="dial-wrapper state-neu" id="direction-dial">
                <div class="dial-mark mark-f"><span>F</span><div class="tick-line"></div></div>
                <div class="dial-mark mark-s"><span>S</span><div class="tick-line"></div></div>
                <div class="dial-mark mark-r"><span>R</span><div class="tick-line"></div></div>
                <div class="dial-knob" id="dial-knob"><div class="dial-pointer-line"></div></div>
            </div>
            <div class="dial-title">DIRECTION CONTROL</div>
        </div>
    </div>

    <!-- CENTER PANEL -->
    <div class="panel panel-center">
        <div class="screw" style="top:10px; left:10px;"></div><div class="screw" style="top:10px; right:10px;"></div>
        <div class="screw" style="bottom:10px; left:10px;"></div><div class="screw" style="bottom:10px; right:10px;"></div>

        <div class="speedo-container">
            <div class="speedo-bg"><div class="speedo-ticks" id="speedo-ticks"></div></div>
            <div class="needle-container" id="needle-container"><div class="needle"></div><div class="needle-center"></div></div>
            <div class="digital-speed">
                <div class="digital-num" id="digital-speed-num">0</div>
                <div class="digital-unit">KM/H</div>
            </div>
        </div>

        <div class="btn-grid">
            <div class="grid-btn color-orange" onclick="toggleBtn(this, 'light')"><span>照明</span><div class="btn-indicator"></div></div>
            <div class="grid-btn color-blue" onclick="toggleBtn(this, 'sound')"><span>音效</span><div class="btn-indicator"></div></div>
            <div class="grid-btn color-green" onclick="toggleBtn(this, 'cab')"><span>换端</span><div class="btn-indicator"></div></div>
            <div class="grid-btn color-red" onclick="toggleBtn(this, 'mu')" id="btn-mu"><span>重联</span><div class="btn-indicator"></div></div>
        </div>

        <div class="estop-wrapper">
            <div class="estop-guard"></div>
            <div class="estop-btn" id="estop">
                <span class="small">EMERGENCY</span>
                <span class="big">STOP</span>
            </div>
        </div>
    </div>

    <!-- RIGHT PANEL -->
    <div class="panel panel-right">
        <div class="screw" style="top:10px; left:10px;"></div><div class="screw" style="top:10px; right:10px;"></div>
        <div class="screw" style="bottom:10px; left:10px;"></div><div class="screw" style="bottom:10px; right:10px;"></div>

        <div class="mu-monitor off" id="mu-monitor">
            <div class="mu-warn-overlay" id="mu-warning" style="display:none;">⚠️ 补机通信异常</div>
            <div class="mu-row">
                <span class="mu-text mu-title" onclick="toggleMuWarning()" title="点击测试通信异常">🔗 补机: <span id="mu-link-status">未连接</span></span>
                <span class="mu-text">🔋 65% <span id="mu-batt-volt">3.89V</span></span>
            </div>
            <div class="mu-row" style="margin-top: 8px;">
                <span class="mu-text">速度:</span>
                <div class="mu-speed-box"><div class="mu-speed-fill" id="mu-speed-fill"></div></div>
                <span class="mu-speed-val" id="mu-speed-text">0/0</span>
            </div>
            <div class="mu-coef-wrap">
                <div class="mu-coef-top">
                    <span class="mu-text">系数: <span id="mu-coef-display">1.00</span></span>
                    <div style="display: flex; gap: 5px;">
                        <button class="mu-ctrl-btn" onclick="adjMuCoef(-0.01)">◀</button>
                        <button class="mu-ctrl-btn" onclick="adjMuCoef(0.01)">▶</button>
                    </div>
                </div>
                <div class="mu-slider-container">
                    <span class="mu-text" style="font-size:11px;">0.90</span>
                    <input type="range" id="mu-coef-slider" min="0.9" max="1.1" step="0.01" value="1.00">
                    <span class="mu-text" style="font-size:11px;">1.10</span>
                </div>
            </div>
        </div>

        <div class="throttle-wrapper">
            <div class="lever-container">
                <div class="lever-slot">
                    <div class="grooves" id="grooves"></div>
                    <input type="range" min="0" max="8" value="0" class="hidden-slider" id="throttle-slider" orient="vertical">
                    <div class="lever-handle" id="lever-handle"><div class="lever-stem"></div><div class="handle-cap"></div><div class="handle-cap"></div></div>
                </div>
            </div>
            <div class="led-system">
                <div class="led-bar" id="led-bar">
                    <div class="led-segment"></div><div class="led-segment"></div><div class="led-segment"></div>
                    <div class="led-segment"></div><div class="led-segment"></div><div class="led-segment"></div>
                    <div class="led-segment"></div><div class="led-segment"></div><div class="led-segment"></div>
                </div>
            </div>
            <div class="led-labels">
                <div class="notch-label label-green">NOTCH<br><span>0</span></div>
                <div class="notch-label"></div><div class="notch-label"></div><div class="notch-label"></div>
                <div class="notch-label label-yellow">NOTCH<br><span>4</span></div>
                <div class="notch-label"></div><div class="notch-label"></div><div class="notch-label"></div>
                <div class="notch-label label-red">NOTCH<br><span>8</span></div>
            </div>
        </div>
    </div>
</div>

<script>
    const dial = document.getElementById('direction-dial');
    const knob = document.getElementById('dial-knob');
    const lblFwd = document.getElementById('lbl-fwd');
    const lblNeu = document.getElementById('lbl-neu');
    const lblRev = document.getElementById('lbl-rev');
    let dialState = 0; 
    
    dial.addEventListener('click', () => {
        dialState = (dialState + 1) % 3;
        lblFwd.className = 'dir-label'; lblNeu.className = 'dir-label'; lblRev.className = 'dir-label';
        dial.classList.remove('state-neu', 'state-fwd', 'state-rev');
        if (dialState === 0) { knob.style.transform = 'rotate(0deg)'; lblNeu.classList.add('active-neu'); dial.classList.add('state-neu');}
        else if (dialState === 1) { knob.style.transform = 'rotate(-45deg)'; lblFwd.classList.add('active-fwd'); dial.classList.add('state-fwd');}
        else { knob.style.transform = 'rotate(45deg)'; lblRev.classList.add('active-rev'); dial.classList.add('state-rev');}
    });

    let isMuActive = false;
    let currentCab = 'A端';
    let muCoef = 1.00;
    let muWarning = false;

    const muMonitor = document.getElementById('mu-monitor');
    const muLinkStatus = document.getElementById('mu-link-status');
    const muCoefSlider = document.getElementById('mu-coef-slider');
    const muCoefDisplay = document.getElementById('mu-coef-display');
    const muSpeedFill = document.getElementById('mu-speed-fill');
    const muSpeedText = document.getElementById('mu-speed-text');
    const muBattVolt = document.getElementById('mu-batt-volt');

    function updateMuUI() {
        if(isMuActive) {
            muMonitor.classList.remove('off');
            muLinkStatus.innerText = `已连接 (${currentCab})`;
        } else {
            muMonitor.classList.add('off');
            muLinkStatus.innerText = '未连接';
            if(muWarning) toggleMuWarning();
        }
    }

    muCoefSlider.addEventListener('input', (e) => {
        muCoef = parseFloat(e.target.value);
        muCoefDisplay.innerText = muCoef.toFixed(2);
    });

    function adjMuCoef(val) {
        if(!isMuActive) return;
        muCoef = Math.min(1.10, Math.max(0.90, muCoef + val));
        muCoefSlider.value = muCoef;
        muCoefDisplay.innerText = muCoef.toFixed(2);
    }

    function toggleMuWarning() {
        if(!isMuActive) return;
        muWarning = !muWarning;
        document.getElementById('mu-warning').style.display = muWarning ? 'flex' : 'none';
    }

    function toggleBtn(element, type) {
        const isActive = element.classList.toggle('active');
        if (type === 'cab') {
            const el = document.getElementById('top-status-cab');
            currentCab = isActive ? 'B端' : 'A端';
            el.innerHTML = isActive ? 'B端 CAB-B' : 'A端 CAB-A';
            el.className = isActive ? 'status-val cab-b' : 'status-val cab-a';
            updateMuUI();
        } else if (type === 'mu') {
            const el = document.getElementById('top-status-mu');
            isMuActive = isActive;
            el.innerHTML = isActive ? '重联 M.U.' : '独立 INDEP';
            el.className = isActive ? 'status-val mu-coupled' : 'status-val mu-indep';
            updateMuUI();
        }
    }

    const estop = document.getElementById('estop');
    estop.addEventListener('mousedown', () => estop.classList.add('pressed'));
    estop.addEventListener('mouseup', () => estop.classList.remove('pressed'));
    estop.addEventListener('mouseleave', () => estop.classList.remove('pressed'));

    const slider = document.getElementById('throttle-slider');
    const handle = document.getElementById('lever-handle');
    const ledSegments = document.querySelectorAll('.led-segment');
    const digitalSpeed = document.getElementById('digital-speed-num');
    const needleContainer = document.getElementById('needle-container');
    const lcdVolt = document.getElementById('lcd-volt');
    
    let currentSpeed = 0, targetSpeed = 0; const maxSpeed = 160;
    const baseVoltage = 110.5;
    const muBaseVoltage = 3.89; 
    let currentNotch = 0;

    const getLedColor = (index) => {
        if(index <= 2) return '#2ecc71'; if(index <= 5) return '#f1c40f'; return '#e74c3c';
    };

    function updateThrottle() {
        currentNotch = parseInt(slider.value);
        const step = 420 / 8;
        handle.style.bottom = `${20 + (currentNotch * step)}px`;
        ledSegments.forEach((seg, idx) => {
            if (idx <= currentNotch) {
                const color = getLedColor(idx);
                seg.style.background = color;
                seg.style.boxShadow = `0 0 10px ${color}, inset 0 2px 5px rgba(255,255,255,0.5)`;
            } else {
                seg.style.background = '#111'; seg.style.boxShadow = 'inset 0 2px 5px #000';
            }
        });
        targetSpeed = (currentNotch / 8) * maxSpeed;
    }

    slider.addEventListener('input', updateThrottle);
    updateThrottle();

    const groovesContainer = document.getElementById('grooves');
    for(let i=0; i<9; i++) {
        const g = document.createElement('div'); g.className = 'groove'; groovesContainer.appendChild(g);
    }

    const ticksContainer = document.getElementById('speedo-ticks');
    const minAngle = -130; const maxAngle = 130; const totalRange = maxAngle - minAngle;
    for(let i=0; i<=160; i+=10) {
        const percent = i / 160; const angle = minAngle + (percent * totalRange); const rad = angle * (Math.PI / 180);
        const isMajor = i % 20 === 0;
        const tick = document.createElement('div'); tick.className = `tick ${isMajor ? 'major' : ''}`;
        tick.style.transform = `translateX(-50%) rotate(${angle}deg) translateY(-135px)`;
        ticksContainer.appendChild(tick);
        if (isMajor) {
            const num = document.createElement('div'); num.className = 'tick-num'; num.innerText = i;
            num.style.left = `calc(50% + ${Math.sin(rad) * 98}px)`; num.style.top = `calc(50% + ${-Math.cos(rad) * 98}px)`;
            ticksContainer.appendChild(num);
        }
    }

    setInterval(() => {
        const loadDrop = currentNotch * 0.18; 
        const noise = (Math.random() * 0.2) - 0.1;
        lcdVolt.innerText = (baseVoltage - loadDrop + noise).toFixed(1);
        if(isMuActive) {
            const muLoad = currentNotch * 0.008;
            const muNoise = (Math.random() * 0.02) - 0.01;
            muBattVolt.innerText = (muBaseVoltage - muLoad + muNoise).toFixed(2) + 'V';
        }
    }, 400);

    function animate() {
        currentSpeed += (targetSpeed - currentSpeed) * 0.05;
        digitalSpeed.innerText = Math.round(currentSpeed);
        const percent = currentSpeed / maxSpeed;
        needleContainer.style.transform = `rotate(${minAngle + (percent * totalRange)}deg)`;
        if(isMuActive) {
            let helperTarget = targetSpeed * muCoef;
            let helperCurrent = currentSpeed * muCoef;
            muSpeedText.innerText = `${Math.round(helperCurrent)}/${Math.round(helperTarget)}`;
            muSpeedFill.style.width = `${Math.min(100, (helperCurrent / 176) * 100)}%`;
        }
        requestAnimationFrame(animate);
    }
    animate();
</script>
</body>
</html>

--- HTML 设计稿结束 ---

==============================
五、HTML → Flutter 映射要求
==============================

请严格按照以下映射关系还原 UI：

5.1 整体布局:
- body → Scaffold(backgroundColor: #050505), 强制横屏
- top-status-bar → 顶部 Container, Row 排列
- dashboard → 主体 Container, Row 排列三个 panel
- panel-left / panel-center / panel-right → Expanded 子面板, flex 比例 1:1.3:1

5.2 顶部状态栏 (top-status-bar):
- 车辆选择: 不需要下拉选择，改为显示 BLE 设备名 "BLE_Train"
  和连接状态指示灯 (绿色=已连接, 红色=断开)
- 电压: 显示 BATV 字段值，单位 V
- 电量: 显示 BAT 字段值，带电池图标动画
  - >50%: 绿色 #2ecc71
  - 20~50%: 黄色 #f1c40f  
  - <20%: 红色 #e74c3c
  - BLOW:1 时电池图标闪烁
- 端位: 显示 CAB 字段，A端=绿色, B端=橙色
- 编组: 显示 CP 字段
  - OFF → "独立 INDEP" 灰色
  - MASTER → "本务 MASTER" 红色发光
  - SLAVE → "补机 SLAVE" 红色发光
  - INVITING → "邀请中..." 闪烁

5.3 左面板 — 方向控制 (panel-left):
- dir-display-board → 方向状态显示板
  - 三行: 前进(F)/停车(S)/后退(R)
  - 根据 DIR 字段高亮对应行
  - FWD → 蓝色高亮, STOP → 绿色高亮, REV → 红色高亮
  - 运行中(APWM>0): 非当前方向的行置灰不可点击
  
- direction-dial → 用 CustomPainter 绘制旋转拨盘
  - 三个位置: F(-45°) / S(0°) / R(45°)
  - 点击切换状态（不是拖动旋转）
  - 切换到 F: 发送 F:{当前档位} (如果档位=0则发 F:1)
  - 切换到 S: 发送 S
  - 切换到 R: 发送 R:{当前档位} (如果档位=0则发 R:1)
  - 运行中不允许直接从 F 切到 R (必须先经过 S)
  - 旋钮金属质感必须用 RadialGradient 还原

5.4 中面板 — 仪表与按钮 (panel-center):
- speedo-container → 用 CustomPainter 绘制完整的速度表盘
  - 表盘范围: 0~8 (对应 8 个档位, 不是 0~160)
  - 数字显示改为: 大字显示当前档位数字 (LV字段)
  - 单位显示: "NOTCH" (替代 KM/H)
  - 指针用 APWM 驱动 (0~255 映射到表盘角度)
  - 指针动画: 使用 AnimationController, 插值平滑
  - 表盘底色: radial-gradient 深蓝色调
  - 刻度: 主刻度带数字(0,1,2...8), 次刻度无数字
  - 指针发光效果: 红色 + Shadow

- btn-grid → 4个功能按钮, Row 排列
  - 照明: 发送 L, 根据 HL 字段高亮 (橙色)
  - 音效: 发送 M, 根据 SE 字段高亮 (蓝色)
  - 换端: 发送 C, 停车时可用/运行时置灰 (绿色)
  - 重联: 发送 CP, 根据 CP 字段变化 (红色)
    - CP:OFF → 可点击, 发送 CP
    - CP:INVITING → 显示"邀请中", 再点取消 CP:STOP
    - CP:MASTER → 显示"已连接", 不可点击
    - CP:SLAVE → 显示"补机", 不可点击
  
  按钮视觉:
  - 金属按钮质感 (gradient + shadow)
  - 底部指示灯条 (激活时对应颜色发光)
  - 按压动效 (translateY + shadow变化)

- estop → 紧急停车按钮
  - 红色圆形按钮 + 金属保护框
  - 点击发送 S, 并将油门归零
  - 按压动效: 缩放 + 阴影变化 + 红色外发光

5.5 右面板 — 油门与重联 (panel-right):
- mu-monitor → 重联监视器 (CRT屏幕风格)
  - 默认状态(CP:OFF): 灰暗关闭状态 (grayscale + 低亮度)
  - CP:MASTER 激活:
    - 绿色发光文字 (#0fdb8a)
    - CRT扫描线效果 (CustomPainter 半透明横线)
    - 显示: 补机连接端(SC), 补机电量(SBAT/SBATV), 补机速度(SAPWM)
    - 速度条: 斜条纹填充动画
    - 系数滑块: 0.90~1.10, 步进0.01
    - ◀▶ 微调按钮
    - SWARN:1 时显示红色警告覆盖层 (闪烁动画)
  - CP:SLAVE:
    - 显示"操控权已移交本务机"
    - 所有控制按钮禁用

- throttle-wrapper → 油门拉杆 + LED档位条
  - lever: 用 GestureDetector + 自定义绘制
    - 垂直拖动操作, 9个档位 (0~8)
    - 金属拉杆手柄质感
    - 档位凹槽 (左侧9个小凹痕)
    - 拖动时触感反馈 (HapticFeedback)
  - LED bar: 9个LED灯段
    - 0~2: 绿色 #2ecc71
    - 3~5: 黄色 #f1c40f
    - 6~8: 红色 #e74c3c
    - 激活时发光效果 (boxShadow)
  - 档位标签: NOTCH 0 / 4 / 8

  操控逻辑:
  - 拖动拉杆改变档位
  - 档位变化时根据当前方向发送:
    - 方向=F 且 档位>0: 发送 F:{档位}
    - 方向=R 且 档位>0: 发送 R:{档位}
    - 档位=0: 发送 S
  - 拖动中节流: 最多每150ms发一次
  - 松手时立即发送最终值

5.6 补机只读界面 (CP:SLAVE时):
  当收到 CP:SLAVE 状态时，整个界面切换为只读模式:
  - 所有按钮置灰不可操作
  - 方向拨盘锁定
  - 油门拉杆锁定
  - 速度表仍然正常显示 (APWM驱动)
  - 顶部状态栏正常显示
  - 中央区域叠加半透明提示: "🚂 重联运行中 — 本务机控制"
  - 重联监视器显示: 当前速度/档位/灯光/音效状态

5.7 重联邀请弹窗 (CP:INVITED时):
  当收到 CP:INVITED 状态时，弹出对话框:
  - 工业风格对话框 (深色 + 绿色发光边框)
  - 标题: "📡 收到重联邀请"
  - 内容: "来自: {INV字段MAC地址}"
  - 三个按钮:
    - "A端连接" → 发送 J:A
    - "B端连接" → 发送 J:B  
    - "拒绝" → 不发送任何指令 (等待邀请超时)

==============================
六、数据驱动关系
==============================

以下是 BLE 状态字段到 UI 元素的完整映射:

  APWM → 速度表指针角度 (0~255 → 表盘角度)
  TPWM → (可选) 速度表目标标记
  LV   → 数字速度显示 (大字)
  DIR  → 方向状态板高亮 + 拨盘位置
  CAB  → 顶部端位显示
  HL   → 照明按钮指示灯
  SE   → 音效按钮指示灯
  SND  → (可选) 音效实际播放状态指示
  BAT  → 顶部电量百分比 + 电池图标填充
  BATV → 顶部电压显示
  BLOW → 电池图标闪烁红色
  CP   → 编组状态 + 重联监视器开关 + 按钮状态
  SC   → 重联监视器: 补机连接端
  SAPWM→ 重联监视器: 补机速度条
  SBAT → 重联监视器: 补机电量
  SBATV→ 重联监视器: 补机电压
  SK   → 重联监视器: 系数滑块位置
  SWARN→ 重联监视器: 红色警告覆盖
  DM   → (可选) 顶部显示演示模式标记
  FW   → (可选) 设置页显示固件版本

==============================
七、交互逻辑细节
==============================

7.1 方向切换安全逻辑:
  - 停车状态 (APWM=0, DIR=STOP): F/S/R 自由切换
  - 运行中 (APWM>0):
    - 当前 F → 只能切到 S (不能直接到 R)
    - 当前 R → 只能切到 S (不能直接到 F)
    - 当前 S → 不应出现 (APWM>0时DIR不会是STOP)
  - 切到 S: 油门自动归零 + 发送 S
  - 切到 F/R: 如果当前油门=0，自动提升到1档

7.2 油门与方向联动:
  - 方向=S 时: 油门拉杆锁定在0档，不可拖动
  - 方向=F/R 时: 油门可拖动
  - 油门从 0 拖到 1: 自动设置方向为上次的 F 或 R (默认 F)

7.3 紧急停车:
  - 点击 ESTOP:
    a. 发送 S
    b. 油门归零
    c. 方向切到 S
    d. 按钮按压动效 + 红色闪光

7.4 状态同步 (BLE → UI):
  - 收到状态后，UI 仅在值变化时更新 (避免闪烁)
  - 速度表指针使用 AnimationController 平滑过渡
  - LED档位条根据 LV 字段更新 (不是根据本地拉杆位置)
  - 如果 BLE 下发的 LV 和本地拉杆不一致 → 以 BLE 为准，拉杆自动同步

7.5 BLE 断连处理:
  - 检测到断连 → 顶部连接指示灯变红
  - 弹出重连提示 (工业风格对话框)
  - 自动重连3次，间隔2秒
  - 重连失败 → 返回扫描页面
  - 重连成功 → 恢复上次界面

==============================
八、扫描连接页面
==============================

扫描页面也要保持工业仪表盘风格:
- 深色背景 + 金属面板
- 标题: "🚂 BLE TRAIN CONTROLLER" (Orbitron字体)
- 副标题: "SCANNING..." (带脉冲动画)
- 设备列表: 每个设备一行
  - 设备名 (Orbitron字体, 青色发光)
  - 信号强度图标 (RSSI)
  - 点击连接
- 底部: [SCAN] 按钮 (金属质感)
- 连接中: 圆形加载动画 (青色发光旋转)

==============================
九、项目结构
==============================

lib/
├── main.dart                         # 入口，强制横屏，主题
├── theme/
│   └── train_theme.dart              # 颜色/字体/阴影/样式常量
├── models/
│   └── train_state.dart              # 火车状态数据模型
├── services/
│   ├── ble_service.dart              # BLE 连接/扫描/读写/通知
│   └── state_parser.dart             # 状态字符串解析器
├── providers/
│   └── train_provider.dart           # Riverpod 状态管理
├── screens/
│   ├── scan_screen.dart              # BLE 扫描连接页面
│   └── dashboard_screen.dart         # 主控制页面 (包含所有面板)
├── widgets/
│   ├── top_status_bar.dart           # 顶部状态栏
│   ├── direction_panel.dart          # 左面板: 方向状态板 + 拨盘
│   ├── direction_dial_painter.dart   # CustomPainter: 方向拨盘
│   ├── speedometer.dart              # 中面板: 速度表盘
│   ├── speedometer_painter.dart      # CustomPainter: 表盘绘制
│   ├── control_buttons.dart          # 中面板: 功能按钮组
│   ├── emergency_stop.dart           # 中面板: 紧急停车按钮
│   ├── throttle_lever.dart           # 右面板: 油门拉杆
│   ├── led_bar.dart                  # 右面板: LED档位条
│   ├── mu_monitor.dart               # 右面板: 重联监视器
│   ├── metal_panel.dart              # 通用: 金属面板容器
│   ├── screw_widget.dart             # 通用: 螺丝装饰
│   ├── lcd_display.dart              # 通用: LCD显示框
│   └── couple_invite_dialog.dart     # 弹窗: 重联邀请
└── utils/
    └── constants.dart                # UUID、BLE参数常量

==============================
十、额外要求
==============================

1. 所有 CustomPainter 必须使用 shouldRepaint 优化，避免不必要的重绘
2. 动画使用 AnimationController + Tween，不要用 Timer
3. BLE 操作全部 try-catch，断连自动重连
4. 状态更新使用 Riverpod 的 StateNotifier，UI 用 Consumer 监听
5. 代码注释: 每个文件开头写功能说明，关键逻辑写中文注释
6. 金属质感的渐变和阴影参数要严格按照 HTML 设计稿还原
7. 速度表的指针颜色(红色)和底部数字颜色(白色)不能搞混
8. LED 灯条要有"从底部到顶部逐个点亮"的视觉效果
9. 首次使用自动请求蓝牙和定位权限
10. 平板和手机都要正常显示（使用 MediaQuery 适配）

请从 pubspec.yaml 开始，按项目结构顺序输出每个文件的完整代码。
每个文件输出完整代码，不要用省略号。
如果内容太长，告诉我"继续"，你再输出下一批文件。
```

---

## 补充说明

### 开发环境搭建

如果你之前没用过 Flutter，需要先安装：

```
1. 安装 Flutter SDK
   https://docs.flutter.dev/get-started/install

2. 安装 Android Studio（提供安卓模拟器和编译工具链）

3. 验证环境:
   flutter doctor

4. 创建项目:
   flutter create ble_train_controller
   cd ble_train_controller

5. 将 AI 生成的代码替换到对应文件

6. 运行:
   flutter run
```

### 调试建议

```
阶段1: 先跑通 BLE 连接 + 基本控制（F/R/S/L）
阶段2: 加入状态解析 + UI 实时刷新
阶段3: 加入重联邀请/接受/解联
阶段4: 加入补机只读界面
阶段5: UI 美化 + 动效
阶段6: OTA 升级（后期再加）
```

### 如果生成的代码有问题

把报错信息连同代码发给 AI，说：

```
运行时报错如下:
[粘贴错误信息]

请修复这个问题。
```



# 详细接线图

## 一、系统总接线图

```
                                    3×AA 电池盒 (4.5V)
                                    ┌─────────────┐
                                    │  +     -    │
                                    └──┬──────┬───┘
                                       │      │
                                 物理开关(ON)  │
                                       │      │
                              VCC ─────┘      └───── GND
                               │                      │
              ┌────────────────┼──────────────────────┤
              │                │                      │
              │    ┌───────────┼──────────┐           │
              │    │           │          │           │
              │    │   ESP32-C3 Super Mini│           │
              │    │                      │           │
              │    │  3V3/VCC ← VCC       │           │
              │    │  GND     ← GND       │           │
              │    │                      │           │
              │    │  GPIO0 → 电池ADC     │           │
              │    │  GPIO2 → DRV8833     │           │
              │    │  GPIO3 → DRV8833     │           │
              │    │  GPIO4 → Q1栅极      │           │
              │    │  GPIO5 → Q2栅极      │           │
              │    │  GPIO6 → Q3栅极      │           │
              │    │  GPIO7 → Q4栅极      │           │
              │    │  GPIO8 → Q5栅极      │           │
              │    │                      │           │
              │    └──────────────────────┘           │
              │                                       │
     VCC──────┼───────────────────────────────────────┤──GND
              │                                       │
    ┌─────────┼───────────┐                           │
    │  DRV8833│           │                           │
    │  VCC ←──┘           │                           │
    │  GND ←──────────────┼───────────────────────────┤
    │  AOUT1──→ 马达(+)   │                           │
    │  AOUT2──→ 马达(-)   │                           │
    └─────────────────────┘                           │
              │                                       │
    ┌─────────┼───────────┐                           │
    │ Q1~Q4   │(灯光MOS)  │                           │
    │ Drain ──→ LED(-)    │                           │
    │ Source ─────────────┼───────────────────────────┤
    └─────────────────────┘                           │
              │                                       │
    ┌─────────┼───────────┐                           │
    │ Q5      │(音效MOS)  │                           │
    │ Drain ──→ 原车PCB GND断口                       │
    │ Source ─────────────┼───────────────────────────┘
    └─────────────────────┘
```

---

## 二、各模块独立接线

### 模块1：电源系统

```
┌─────────────────────────────────────────────────────────────┐
│  电源系统                                                   │
│                                                             │
│  3×AA电池盒                                                 │
│  ┌──────────┐                                               │
│  │ (+) 4.5V │──→ 物理开关 ──→ VCC 总线                      │
│  │ (-) GND  │──→ GND 总线                                   │
│  └──────────┘                                               │
│                                                             │
│  VCC总线 分配到:                                            │
│  ├─ ESP32-C3 的 VCC (或3V3) 引脚                            │
│  ├─ DRV8833 的 VCC 引脚                                     │
│  ├─ 所有LED的正极 (通过限流电阻)                            │
│  ├─ 原车PCB的VCC (保持原有连接)                             │
│  └─ 电池分压器上臂                                          │
│                                                             │
│  GND总线 分配到:                                            │
│  ├─ ESP32-C3 的 GND 引脚                                    │
│  ├─ DRV8833 的 GND 引脚                                     │
│  ├─ 所有MOS管(Q1~Q5)的 Source 引脚                          │
│  ├─ 所有10kΩ下拉电阻的接地端                                │
│  ├─ 电池分压器下臂                                          │
│  └─ 100μF电解电容负极                                       │
│                                                             │
│  电源滤波:                                                  │
│  VCC ──┬── [100μF电解电容(+)] ──┬── GND                     │
│        │                        │                           │
│      (靠近DRV8833放置)         (-)                          │
│                                                             │
│  注意: 电解电容的长脚=正极接VCC, 短脚=负极接GND             │
└─────────────────────────────────────────────────────────────┘
```

### 模块2：ESP32-C3 Super Mini

```
┌─────────────────────────────────────────────────────────────┐
│  ESP32-C3 Super Mini 引脚连接                               │
│                                                             │
│          ┌──────────────────┐                               │
│          │   ESP32-C3       │                               │
│          │   Super Mini     │                               │
│          │                  │                               │
│ 电池VCC─→│ VCC          GND │←─ 电池GND                     │
│          │                  │                               │
│分压中点─→│ GPIO0            │  ← 电池电压ADC采样            │
│          │                  │                               │
│ DRV IN1─←│ GPIO2            │  → PWM信号到DRV8833           │
│ DRV IN2─←│ GPIO3            │  → PWM信号到DRV8833           │
│          │                  │                               │
│ Q1栅极──←│ GPIO4            │  → A端白灯MOS管               │
│ Q2栅极──←│ GPIO5            │  → B端白灯MOS管               │
│ Q3栅极──←│ GPIO6            │  → A端红灯MOS管               │
│ Q4栅极──←│ GPIO7            │  → B端红灯MOS管               │
│          │                  │                               │
│ Q5栅极──←│ GPIO8            │  → 音效PCB供电MOS管           │
│          │                  │                               │
│          └──────────────────┘                               │
│                                                             │
│  每个GPIO输出引脚的连接方式:                                │
│                                                             │
│  GPIO ──┬── 到目标设备 (MOS栅极 或 DRV8833输入)             │
│         │                                                   │
│         └── [10kΩ电阻] ── GND  (栅极下拉, 防止上电浮动)     │
│                                                             │
│  注意: GPIO2/GPIO3 连DRV8833不需要下拉电阻                  │
│        GPIO4~GPIO8 连MOS管栅极需要10kΩ下拉                  │
└─────────────────────────────────────────────────────────────┘
```

### 模块3：DRV8833 电机驱动

```
┌─────────────────────────────────────────────────────────────┐
│  DRV8833 电机驱动模块                                       │
│                                                             │
│          ┌──────────────────┐                               │
│          │     DRV8833      │                               │
│          │                  │                               │
│ 电池VCC─→│ VCC          GND │←─ 电池GND                     │
│          │                  │                               │
│  ESP32   │                  │                               │
│  GPIO2 ─→│ AIN1        AOUT1│──→ 马达(+)端子                │
│  GPIO3 ─→│ AIN2        AOUT2│──→ 马达(-)端子                │
│          │                  │                               │
│          │ BIN1       BOUT1 │  (未使用, 悬空)               │
│          │ BIN2       BOUT2 │  (未使用, 悬空)               │
│          │                  │                               │
│          │ SLP(SLEEP)       │←─ VCC (保持唤醒,拉高)         │
│          │                  │   或悬空(模块内部已上拉)      │
│          │                  │                               │
│          │ FLT(FAULT)       │  (未使用, 可悬空)             │
│          │                  │                               │
│          └──────────────────┘                               │
│                                                             │
│  电机端滤波电容 (2个0.1μF瓷片电容):                         │
│                                                             │
│     AOUT1 ──┤├── 马达(+)端子                                │
│              0.1μF                                          │
│     AOUT2 ──┤├── 马达(-)端子                                │
│              0.1μF                                          │
│                                                             │
│  ！ 安装位置: 电容直接焊在马达端子上, 引脚尽量短            │
│                                                             │
│  控制逻辑:                                                  │
│    AIN1=PWM, AIN2=0   → 马达正转                            │
│    AIN1=0,   AIN2=PWM → 马达反转                            │
│    AIN1=0,   AIN2=0   → 马达停止(coast/滑行)                │
│                                                             │
│  ！ 注意:                                                   │
│    - 断开原车PCB到马达的两根线, 改由DRV8833驱动             │
│    - VCC直接接电池(4.5V), 不经过ESP32                       │
│    - GND和ESP32共地                                         │
└─────────────────────────────────────────────────────────────┘
```

### 模块4：电池电压检测（分压器）

```
┌─────────────────────────────────────────────────────────────┐
│  电池电压分压检测电路                                       │
│                                                             │
│  原理: 电池电压4.5V超出ESP32 ADC量程(~2.5V)                 │
│        用两个等值电阻分压, ADC读到电池电压的一半            │
│                                                             │
│  电路:                                                      │
│                                                             │
│  VCC (电池+) ──── [R1 100kΩ] ──┬── [R2 100kΩ] ──── GND      │
│                                │                            │
│                                └──── ESP32 GPIO0 (ADC)      │
│                                                             │
│  电压计算:                                                  │
│    V_GPIO0 = V_BAT × R2/(R1+R2) = V_BAT × 100k/(100k+100k)  │
│    V_GPIO0 = V_BAT / 2                                      │
│                                                             │
│    电池4.5V → GPIO0读到2.25V                                │
│    电池3.0V → GPIO0读到1.50V                                │
│                                                             │
│  ！ 安装位置: 尽量靠近ESP32, 走线短                         │
│  ! 功耗: 100k+100k=200kΩ, 漏电流仅22μA, 可忽略              │
│                                                             │
│  实物接线示意:                                              │
│                                                             │
│    电池(+) ───[棕黑黄金]─── 中间节点 ───[棕黑黄金]─── GND   │
│              (100kΩ电阻)       │         (100kΩ电阻)        │
│                                │                            │
│                           细导线连到                        │
│                          ESP32 GPIO0                        │
└─────────────────────────────────────────────────────────────┘
```

### 模块5：A端灯组

```
┌─────────────────────────────────────────────────────────────┐
│  A端灯组 (车头/车尾端, 共3个LED)                            │
│                                                             │
│  组成:                                                      │
│    1× 5mm白色LED (车头灯)                                   │
│    2× 3mm红白共阳双色LED (信号灯, 共阳=正极公用)            │
│                                                             │
│  ═══════════════════════════════════════                    │
│  白灯电路 (Q1控制):                                         │
│  ═══════════════════════════════════════                    │
│                                                             │
│  VCC ── [100Ω] ── 5mm白LED(+) ── 白LED(-)   ──┐             │
│                                               │             │
│  VCC ── [100Ω] ── 双色LED①(共阳+) ── 白脚(-) ─┤             │
│                                               │             │
│  VCC ── [100Ω] ── 双色LED②(共阳+) ── 白脚(-) ─┤             │
│                                               │             │
│                      ┌────────────────────────┘             │
│                      │                                      │
│                      └──── Q1(Drain)                        │
│                            Q1(Source) ── GND                │
│                            Q1(Gate) ──┬── ESP32 GPIO4       │
│                                       └── [10kΩ] ── GND     │
│                                                             │
│  ═══════════════════════════════════════                    │
│  红灯电路 (Q3控制):                                         │
│  ═══════════════════════════════════════                    │
│                                                             │
│  VCC ── [150Ω] ── 双色LED①(共阳+) ── 红脚(-) ─┐             │
│                                               │             │
│  VCC ── [150Ω] ── 双色LED②(共阳+) ── 红脚(-) ─┤             │
│                                               │             │
│                      ┌────────────────────────┘             │
│                      │                                      │
│                      └──── Q3(Drain)                        │
│                            Q3(Source) ── GND                │
│                            Q3(Gate) ──┬── ESP32 GPIO6       │
│                                       └── [10kΩ] ── GND     │
│                                                             │
│  ═══════════════════════════════════════                    │
│  双色LED引脚识别 (3mm红白共阳):                             │
│  ═══════════════════════════════════════                    │
│                                                             │
│        最长脚                                               │
│          │                                                  │
│     短脚 │  短脚                                            │
│      │   │   │                                              │
│     红  共阳 白                                             │
│    (-)  (+)  (-)                                            │
│                                                             │
│  共阳(+) ← 通过限流电阻接VCC                                │
│  红(-) → 接Q3的Drain (红灯组)                               │
│  白(-) → 接Q1的Drain (白灯组)                               │
│                                                             │
│  ! 同一个双色LED的红脚和白脚分别接不同的MOS管               │
│  ! 每个LED的正极都需要独立的限流电阻                        │
│                                                             │
│  走线到车身: 3根线                                          │
│    线1: VCC (给LED正极供电)                                 │
│    线2: A_White (白灯负极公共线, 到Q1 Drain)                │
│    线3: A_Red (红灯负极公共线, 到Q3 Drain)                  │
└─────────────────────────────────────────────────────────────┘
```

### 模块6：B端灯组

```
┌─────────────────────────────────────────────────────────────┐
│  B端灯组 (与A端完全对称, 使用Q2和Q4)                        │
│                                                             │
│  ═══════════════════════════════════════                    │
│  白灯电路 (Q2控制):                                         │
│  ═══════════════════════════════════════                    │
│                                                             │
│  VCC ── [100Ω] ── 5mm白LED(+) ── 白LED(-)   ──┐             │
│                                               │             │
│  VCC ── [100Ω] ── 双色LED③(共阳+) ── 白脚(-) ─┤             │
│                                               │             │
│  VCC ── [100Ω] ── 双色LED④(共阳+) ── 白脚(-) ─┤             │
│                                               │             │
│                      ┌────────────────────────┘             │
│                      │                                      │
│                      └──── Q2(Drain)                        │
│                            Q2(Source) ── GND                │
│                            Q2(Gate) ──┬── ESP32 GPIO5       │
│                                       └── [10kΩ] ── GND     │
│                                                             │
│  ═══════════════════════════════════════                    │
│  红灯电路 (Q4控制):                                         │
│  ═══════════════════════════════════════                    │
│                                                             │
│  VCC ── [150Ω] ── 双色LED③(共阳+) ── 红脚(-) ─┐             │
│                                               │             │
│  VCC ── [150Ω] ── 双色LED④(共阳+) ── 红脚(-) ─┤             │
│                                               │             │
│                      ┌────────────────────────┘             │
│                      │                                      │
│                      └──── Q4(Drain)                        │
│                            Q4(Source) ── GND                │
│                            Q4(Gate) ──┬── ESP32 GPIO7       │
│                                       └── [10kΩ] ── GND     │
│                                                             │
│  走线到车身: 3根线                                          │
│    线1: VCC                                                 │
│    线2: B_White (到Q2 Drain)                                │
│    线3: B_Red (到Q4 Drain)                                  │
└─────────────────────────────────────────────────────────────┘
```

### 模块7：2N7002 MOS管接线详解

```
┌─────────────────────────────────────────────────────────────┐
│  2N7002 SOT-23 MOS管 — 通用接线模式 (Q1~Q5共5个)            │
│                                                             │
│  ═══════════════════════════════════════                    │
│  SOT-23 封装引脚识别 (正面朝上, 文字正读):                  │
│  ═══════════════════════════════════════                    │
│                                                             │
│           ┌─────────┐                                       │
│       1 ──┤         ├── 3                                   │
│     (Gate)│ 2N7002  │(Drain)                                │
│           │         │                                       │
│       2 ──┤         │                                       │
│   (Source)└─────────┘                                       │
│                                                             │
│  引脚1 (Gate)   = 栅极 ← 接ESP32 GPIO                       │
│  引脚2 (Source) = 源极 ← 接GND                              │
│  引脚3 (Drain)  = 漏极 ← 接负载(LED负极 或 PCB的GND断口)    │
│                                                             │
│  ═══════════════════════════════════════                    │
│  标准接线 (低侧开关模式):                                   │
│  ═══════════════════════════════════════                    │
│                                                             │
│                  负载 (LED / 原车PCB)                       │
│                         │                                   │
│  VCC ── [限流电阻] ── 负载(+)                               │
│                       负载(-) ── Q_Drain (引脚3)            │
│                                    │                        │
│                                  Q_Source (引脚2) ── GND    │
│                                    │                        │
│                 ESP32 GPIO ──┬── Q_Gate (引脚1)             │
│                              │                              │
│                              └── [10kΩ] ── GND              │
│                                (下拉电阻)                   │
│                                                             │
│  ═══════════════════════════════════════                    │
│  工作原理:                                                  │
│  ═══════════════════════════════════════                    │
│                                                             │
│  GPIO = HIGH (3.3V):                                        │
│    → Gate电压高 → MOS管导通                                 │
│    → Drain-Source短路 → 电流流过 → 负载通电(LED亮/PCB供电)  │
│                                                             │
│  GPIO = LOW (0V):                                           │
│    → Gate电压低 → MOS管截止                                 │
│    → Drain-Source断路 → 无电流 → 负载断电(LED灭/PCB断电)    │
│                                                             │
│  开机瞬间 (GPIO尚未初始化):                                 │
│    → 10kΩ下拉电阻将Gate拉到GND → MOS截止 → 负载默认关       │
│    → 防止上电瞬间LED闪烁或音效误触发                        │
│                                                             │
│  ═══════════════════════════════════════                    │
│  各MOS管分配表:                                             │
│  ═══════════════════════════════════════                    │
│                                                             │
│  Q1: Gate=GPIO4, Drain=A端白灯负极, Source=GND              │
│  Q2: Gate=GPIO5, Drain=B端白灯负极, Source=GND              │
│  Q3: Gate=GPIO6, Drain=A端红灯负极, Source=GND              │
│  Q4: Gate=GPIO7, Drain=B端红灯负极, Source=GND              │
│  Q5: Gate=GPIO8, Drain=原车PCB GND断口, Source=GND          │
│                                                             │
│  ! 所有5个MOS管的Source引脚都接公共GND                      │
│  ! 所有5个Gate都需要10kΩ下拉电阻                            │
│  ! 2N7002最大电流800mA, 本项目每路最大~60mA, 余量充足       │
└─────────────────────────────────────────────────────────────┘
```

### 模块8：音效PCB供电控制

```
┌─────────────────────────────────────────────────────────────┐
│  原车音效PCB供电控制 (Q5)                                   │
│                                                             │
│  ═══════════════════════════════════════                    │
│  改装前 (原车电路):                                         │
│  ═══════════════════════════════════════                    │
│                                                             │
│  电池 ── 开关 ── 原车PCB ── PCB ── 原车PCB(GND) ── 电池     │
│  (+)             (VCC)               │             (-)      │
│                                      ├── 喇叭               │
│                                      └── 马达 (原车驱动)    │
│                                                             │
│  ═══════════════════════════════════════                    │
│  改装后:                                                    │
│  ═══════════════════════════════════════                    │
│                                                             │
│  ①剪断: 原车PCB → 马达 的两根线 (ESP32+DRV8833接管)         │
│  ②剪断: 原车PCB(GND) → 电池(-) 的线                         │
│  ③保留: 开关 → 原车PCB(VCC) (不动)                          │
│  ④保留: 原车PCB → 喇叭 (不动)                               │
│  ⑤新增: Q5插入GND回路                                       │
│                                                             │
│  改装后电路:                                                │
│                                                             │
│  电池(+) ── 开关 ── 原车PCB(VCC)                            │
│                          │                                  │
│                     原车PCB(内部电路)                       │
│                          │                                  │
│                     原车PCB → 喇叭 (音频输出, 保留)         │
│                          │                                  │
│                     原车PCB(GND断口)                        │
│                          │                                  │
│                          └──→ Q5 Drain (引脚3)              │
│                                  │                          │
│                               Q5 Source (引脚2) ──→ 电池GND │
│                                  │                          │
│            ESP32 GPIO8 ──┬──→ Q5 Gate (引脚1)               │
│                          │                                  │
│                          └── [10kΩ] ──→ GND                 │
│                                                             │
│  ═══════════════════════════════════════                    │
│  工作原理:                                                  │
│  ═══════════════════════════════════════                    │
│                                                             │
│  GPIO8=HIGH → Q5导通 → PCB的GND接通 → PCB有电 → 喇叭播放    │
│  GPIO8=LOW  → Q5截止 → PCB的GND断开 → PCB无电 → 喇叭静音    │
│                                                             │
│  ！️ 重要:                                                   │
│    - 是切断GND回路, 不是切断VCC                             │
│    - 因为2N7002是N沟道MOS, 适合做低侧开关                   │
│    - PCB的VCC始终有电(只要物理开关ON), 只是GND被控制        │
│    - 开关拨到ON = 整个系统(ESP32+PCB)都上电                 │
│    - 开关拨到OFF = 整个系统断电                             │
└─────────────────────────────────────────────────────────────┘
```

### 模块9：马达接线

```
┌─────────────────────────────────────────────────────────────┐
│  130马达接线                                                │
│                                                             │
│  ═══════════════════════════════════════                    │
│  改装步骤:                                                  │
│  ═══════════════════════════════════════                    │
│                                                             │
│  1. 找到原车PCB连接到马达的两根线                           │
│  2. 从马达端子处剪断这两根线 (PCB侧悬空用绝缘胶带包好)      │
│  3. 马达两个端子现在是空的, 接上新的线:                     │
│                                                             │
│           ┌────────────────┐                                │
│           │    130马达     │                                │
│           │                │                                │
│  AOUT1 ──→│ (+)端子 (-)端子│←── AOUT2                       │
│           │                │                                │
│           │    ┤├    ┤├    │← 两个0.1μF瓷片电容             │
│           │                │    焊在端子上                  │
│           └────────────────┘                                │
│                                                             │
│  ═══════════════════════════════════════                    │
│  滤波电容焊接方法 (重要! 减少电机噪声干扰BLE):              │
│  ═══════════════════════════════════════                    │
│                                                             │
│  电容1: 焊在马达(+)端子和马达外壳之间                       │
│         马达(+) ──┤├── 马达外壳(金属壳)                     │
│                  0.1μF                                      │
│                                                             │
│  电容2: 焊在马达(-)端子和马达外壳之间                       │
│         马达(-) ──┤├── 马达外壳(金属壳)                     │
│                  0.1μF                                      │
│                                                             │
│  如果马达外壳是塑料的(无法焊接), 则:                        │
│  电容1: 焊在马达(+)和马达(-)之间                            │
│         马达(+) ──┤├── 马达(-)                              │
│                  0.1μF                                      │
│                                                             │
│  ！ 电容引脚尽量短, 直接焊在端子上                          │
│  ！ 瓷片电容无正负极之分                                    │
└─────────────────────────────────────────────────────────────┘
```

### 模块10：限流电阻选型说明

```
┌─────────────────────────────────────────────────────────────┐
│  限流电阻选型与计算                                         │
│                                                             │
│  ═══════════════════════════════════════                    │
│  白灯 (5mm白色LED + 双色LED白脚):                           │
│  ═══════════════════════════════════════                    │
│                                                             │
│  供电电压: 4.5V (电池)                                      │
│  白LED压降: ~3.0V                                           │
│  目标电流: ~15mA                                            │
│  R = (4.5 - 3.0) / 0.015 = 100Ω                             │
│                                                             │
│  使用: 100Ω电阻, 共6个                                      │
│    A端: 1个给5mm白LED + 2个给双色LED白脚 = 3个              │
│    B端: 1个给5mm白LED + 2个给双色LED白脚 = 3个              │
│                                                             │
│  ═══════════════════════════════════════                    │
│  红灯 (双色LED红脚):                                        │
│  ═══════════════════════════════════════                    │
│                                                             │
│  供电电压: 4.5V (电池)                                      │
│  红LED压降: ~2.0V                                           │
│  目标电流: ~15mA                                            │
│  R = (4.5 - 2.0) / 0.015 ≈ 167Ω → 取标准值 150Ω             │
│                                                             │
│  使用: 150Ω电阻, 共4个                                      │
│    A端: 2个给双色LED红脚 = 2个                              │
│    B端: 2个给双色LED红脚 = 2个                              │
│                                                             │
│  ！ 每个LED必须有自己独立的限流电阻                         │
│  ！ 不能多个LED共用一个电阻 (亮度不均且可能烧LED)           │
│                                                             │
│  ═══════════════════════════════════════                    │
│  电阻色环识别:                                              │
│  ═══════════════════════════════════════                    │
│                                                             │
│  100Ω: 棕-黑-棕-金 (±5%)                                    │
│  150Ω: 棕-绿-棕-金 (±5%)                                    │
│  10kΩ: 棕-黑-橙-金 (±5%)                                    │
│  100kΩ: 棕-黑-黄-金 (±5%)                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、完整元件清单与线材

```
┌─────────────────────────────────────────────────────────────┐
│  完整元件与连线清单                                         │
│                                                             │
│  焊接连线数量统计:                                          │
│                                                             │
│  ESP32-C3 引出线: 9根                                       │
│    VCC, GND, GPIO0, GPIO2, GPIO3, GPIO4, GPIO5, GPIO6,      │
│    GPIO7, GPIO8                                             │
│                                                             │
│  DRV8833 引出线: 6根                                        │
│    VCC, GND, AIN1(←GPIO2), AIN2(←GPIO3),                    │
│    AOUT1(→马达+), AOUT2(→马达-)                             │
│                                                             │
│  每个MOS管(Q1~Q5): 3根 × 5 = 15根                           │
│    Gate(←GPIO+10kΩ), Source(→GND), Drain(→负载)             │
│                                                             │
│  A端灯组到主板: 3根线                                       │
│    VCC, A_White(→Q1D), A_Red(→Q3D)                          │
│                                                             │
│  B端灯组到主板: 3根线                                       │
│    VCC, B_White(→Q2D), B_Red(→Q4D)                          │
│                                                             │
│  电池分压器: 3个焊点                                        │
│    VCC→R1→中间节点→R2→GND, 中间节点→GPIO0                   │
│                                                             │
│  音效PCB: 2根线                                             │
│    PCB原GND断口→Q5D, (Q5S已在公共GND)                       │
│                                                             │
│  马达: 2根线                                                │
│    AOUT1→马达(+), AOUT2→马达(-)                             │
│                                                             │
│  电源: 2根线                                                │
│    电池(+)→开关→VCC总线, 电池(-)→GND总线                    │
│                                                             │
│  总计焊点: 约45~50个                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 四、建议焊接顺序

```
步骤1: 电源系统
  → 电池盒接线 + 100μF电容 + VCC/GND总线
  → 用万用表确认VCC=4.5V, 极性正确

步骤2: ESP32-C3
  → 焊接VCC和GND
  → 上电测试: USB连电脑能识别

步骤3: 电池分压器
  → 焊接2个100kΩ + 连接GPIO0
  → 上传测试代码读ADC, 确认读数正确

步骤4: DRV8833 + 马达
  → 焊接VCC/GND/AIN1/AIN2
  → 马达端焊电容
  → 马达接AOUT1/AOUT2
  → 上传测试代码, 确认马达正反转正常

步骤5: Q5 + 音效PCB
  → 改装原车PCB(剪断GND线和马达线)
  → 焊接Q5三个引脚 + 10kΩ下拉
  → 测试: GPIO8拉高→喇叭响, 拉低→静音

步骤6: Q1~Q4 + 灯组
  → 先焊一端(如A端)测试
  → 确认白灯和红灯独立可控
  → 再焊另一端(B端)

步骤7: 上传完整固件
  → 运行开机自检
  → 全灯闪烁 → 换端演示 → 音效测试
  → 全部通过 = 硬件完成
```