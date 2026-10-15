ESP32 智能游戏竞技台
鸿蒙应用开发期末大作业 · 基于 OpenHarmony 的物联网项目实践
ESP32 开发板 与 HarmonyOS 手机 APP 通过 MQTT 协议实时双向通信，
手机端负责选游戏、看成就、管排行榜，手机还能远程给开发板上的 8×8 矩阵灯画像。
项目
信息
项目名称
ESP32 智能游戏竞技台
课程
鸿蒙应用开发 · 基于 OpenHarmony 的物联网项目实践
开发语言
ArkTS（APP 端） / C++（ESP32 端）
应用框架
HarmonyOS 6.0.2(22) · ArkUI 声明式 UI
通信协议
MQTT 3.1.1（TCP Socket 自研客户端）
Broker
broker.emqx.io:1883
成员
巫泉彬（25215150314）· 蓝钿玉
目录
- 一、项目简介
- 二、系统架构
- 三、硬件外设与接口
- 四、APP 功能说明
- 五、MQTT 通信协议
- 六、项目源码结构
- 七、核心实现
- 八、环境搭建与运行
- 九、已完成与后续规划
- 十、已知限制
一、项目简介
本项目设计并实现了一套「ESP32 + HarmonyOS 手机」的物联网游戏系统。
ESP32 开发板作为游戏主机，接入蜂鸣器、AD 五路按键、4 位数码管、8×8 LED 矩阵灯四个外设模块，承载四款经典小游戏（贪吃蛇、俄罗斯方块、小恐龙 Dino、飞机大战）的运行。
HarmonyOS APP 作为管理与竞技平台，负责游戏选择、得分记录、成就解锁，并在游戏结束后提供「看广告复活」机制，同时内置一个 8×8 点阵编辑器，可以直接用手指在手机上画画，图案实时下发到开发板的矩阵灯上显示。
整个系统走通了物联网的南向（开发板 ↔ 外设，GPIO / ADC / I2C）和北向（开发板 ↔ Broker ↔ APP，MQTT）两条链路。
二、系统架构
┌────────────────────────┐   ┌──────────────────────┐   ┌────────────────────────┐
│  外设模块（南向）        │   │      MQTT Broker     │   │   手机 APP（北向）        │
├────────────────────────┤   │  broker.emqx.io:1883 │   ├────────────────────────┤
│ 蜂鸣器    → GPIO / PWM  │   │                      │   │ HomeMenu    游戏菜单     │
│ AD 五路按键 → ADC 分压  │◄─►│ wuquanbin/game/cmd   │◄─►│ SelectGame  选游戏+排行  │
│ 4位数码管  → DIO / CLK  │   │   （APP → ESP32）     │   │ Achievement 成就徽章     │
│ 8×8 矩阵灯 → I2C         │   │ wuquanbin/game/event │   │ MatrixPage  矩阵灯画板    │
│                        │   │   （ESP32 → APP）     │   │ AdRevive    复活弹窗      │
└───────────▲────────────┘   └──────────────────────┘   └───────────▲────────────┘
            │                                                   │
      ┌─────┴──────┐                                     ┌──────┴──────┐
      │  ESP32 开发板│                                     │ HarmonyOS   │
      │ WiFi + MQTT  │                                     │ ArkTS · ArkUI │
      └────────────┘                                     └─────────────┘
数据流向：
- APP → ESP32：矩阵灯控制、复活、退出指令，走 wuquanbin/game/cmd
- ESP32 → APP：游戏结束事件、退出菜单事件，走 wuquanbin/game/event
三、硬件外设与接口
外设模块
接口协议
开发板侧引脚
在本项目中的用途
蜂鸣器 A-Buzzer
GPIO + LEDC PWM
GPIO 输出
得分、碰撞、结束时的音效提示
AD 五路按键
ADC 电阻分压
1 个 ADC 引脚
上 / 下 / 左 / 右 / 确认，5 键共用 1 脚
4 位数码管
DIO / CLK（类 SPI，板载 TM1637）
2 根 GPIO
实时显示当前分数（0–9999）
8×8 LED 矩阵灯
I2C（SDA / SCL）
I2C 总线
游戏画面 + APP 远程下发的图案
AD 五路按键为什么只用 1 个 ADC 脚：5 个按键通过内部电阻分压网络接到同一个 ADC 引脚，按下不同按键时 Signal 输出不同电压（ESP32 内置 12 位 ADC，量程 0–4095），代码里按阈值分段判断即可区分是哪个键，省下 4 个 GPIO。
矩阵灯的数据模型：每帧 8 个字节，每字节控制一行 8 个 LED 的亮灭。APP 端用 number[8] 表示一帧，按位运算（1 << col）做单点翻转，8 个字节 JSON 序列化后随 MQTT 下发。
四、APP 功能说明
APP 采用 ArkTS 声明式 UI 开发，页面通过 Index.ets 中的路由状态切换，Stack 布局管理页面层级与弹窗覆盖。
4.1 首页菜单 HomeMenu
三段式布局：顶部浅蓝通栏（标题 + 图标组）、中部白色功能区、底部浅灰辅助栏。
- 主按钮 选择游戏（深蓝底 + 投影，按下有缩放回弹）
- 次按钮 游戏成就、其他玩法（描边样式）
- 底部：客服中心 / 隐私协议 / 清除缓存 / 版本号
4.2 选择游戏 SelectGamePage
- 顶部 Swiper 左右滑动切换四款游戏卡片，每张卡片带独立主题背景 SVG、名称、成就进度
- 中部「最新对局」卡片，60 号字橙色展示刚结束的分数
- 底部排行榜：随选中游戏联动过滤，按分数降序取 Top 10，同分按时间倒序，前三名橙色高亮
4.3 游戏成就 AchievementPage
- 顶部游戏主题 banner + 解锁进度
- 游戏 Tab 栏快速切换
- 成就列表：已解锁显示绿色「✓ 已解锁」，未解锁显示所需分数
四款游戏各 3 级成就，共 12 个：
游戏
成就
分数门槛
贪吃蛇
第一颗果实 / 灵活转向 / 蛇王挑战
50 / 100 / 120
俄罗斯方块
落块入门 / 消行节奏 / 八格大师
100 / 300 / 600
小恐龙 Dino
起跳成功 / 荒野长跑 / 极限反应
40 / 100 / 180
飞机大战
命中目标 / 王牌飞行 / 空域守护者
60 / 160 / 300
4.4 其他玩法 MatrixPage
- 8×8 可点击点阵网格，点亮态绿色，未点亮深色
- 预设图案：爱心、笑脸、云朵、哭脸、星星、箭头，支持「随机」
- 快捷操作：清空 / 全部点亮 / 发送当前画面
- 底部 MQTT 连接面板：连接 / 重连按钮 + 实时连接状态文案
4.5 复活弹窗 AdReviveDialog
收到 game_over 事件后弹出：
1. 展示游戏名与本局得分，两个按钮：结束 / 看广告复活
2. 点「看广告复活」进入 5 秒倒计时动画
3. 倒计时结束出现「继续游戏」，点击后向开发板发送 revive 指令
五、MQTT 通信协议
配置项
值
Broker
broker.emqx.io
端口
1883（明文 TCP）
事件主题（APP 订阅）
wuquanbin/game/event
命令主题（APP 发布）
wuquanbin/game/cmd
Keep Alive
60 秒
认证
用户名 / 密码（见 entry/src/main/ets/common/AppConstants.ets）
消息格式
ESP32 → APP · 游戏结束
{"type":"game_over","game":"snake","score":85}
ESP32 → APP · 退出菜单
{"type":"game_exit","game":"tetris","score":240}
APP → ESP32 · 矩阵灯控制
{
  "type": "matrix",
  "action": "pixel | pattern | clear | fill | frame",
  "name": "heart",
  "x": 3,
  "y": 5,
  "on": 1,
  "rows": [0, 102, 255, 255, 126, 60, 24, 0]
}
action 语义：pixel 单点开关、pattern 应用预设图案、clear 清空、fill 全部点亮、frame 整帧下发。rows 始终携带完整 8 字节帧，保证开发板侧状态与 APP 端一致。
APP → ESP32 · 复活 / 退出
{"type":"revive","game":"snake"}
{"type":"exit","game":"snake"}
六、项目源码结构
esp32_games/
├── AppScope/                     # 应用级配置
│   ├── app.json5                 # bundleName、版本、图标
│   └── resources/base/media/     # 分层图标（前景 + 背景）
├── entry/                        # 主模块
│   ├── build-profile.json5
│   └── src/main/
│       ├── module.json5          # 模块声明、权限、能力配置
│       ├── ets/
│       │   ├── entryability/
│       │   │   ├── EntryAbility.ets          # UIAbility 生命周期，加载 pages/Index
│       │   │   └── EntryBackupAbility.ets    # 数据备份扩展
│       │   ├── pages/
│       │   │   └── Index.ets                  # 应用入口：路由 + 全局状态 + MQTT + 数据库
│       │   ├── components/                   # UI 组件（按页面拆分）
│       │   │   ├── PageShell.ets             # 子页通用导航条（返回 / 标题 / 在线状态）
│       │   │   ├── HomeMenu.ets              # 首页菜单
│       │   │   ├── SelectGamePage.ets        # 选择游戏 + 最新对局 + 排行榜
│       │   │   ├── AchievementPage.ets       # 成就页
│       │   │   ├── MatrixPage.ets            # 矩阵灯控制页
│       │   │   └── AdReviveDialog.ets        # 复活弹窗
│       │   └── common/
│       │       ├── AppConstants.ets          # 主题色、MQTT 配置、菜单、矩阵灯预设图案
│       │       ├── GameDataModel.ets         # 游戏 / 成就 / 得分数据模型与事件解析
│       │       ├── MqttClient.ets            # 自研 MQTT 3.1.1 客户端
│       │       └── DatabaseHelper.ets        # preferences 本地存储封装
│       └── resources/base/media/             # 四款游戏主题 SVG、启动图标
├── build-profile.json5           # 工程级构建配置（product、签名、SDK 版本）
├── oh-package.json5              # 依赖声明（无第三方运行时依赖）
├── hvigor/                       # 构建脚本配置
└── code-linter.json5             # 代码检查规则（含 @security 系列）
代码量：APP 端 14 个 .ets 文件，约 2800 行 ArkTS。
关于 ESP32 端固件：本仓库收录的是 HarmonyOS APP 端工程。ESP32 侧的 GPIO / ADC / I2C 驱动与 MQTT 客户端代码在开发板上单独维护，可参考《鸿蒙应用开发实践报告》第 4.2 / 4.3 节中给出的关键片段（蜂鸣器 PWM、AD 按键阈值判断、TM1637 数码管、矩阵灯帧数据）。
仓库里有什么
路径
说明
entry/src/、AppScope/、各 *.json5
鸿蒙工程源码，clone 后用 DevEco Studio 直接打开编译
esp32_games_source.zip
同一份源码的打包版（0.24MB），不想用 IDE 时可直接解压
25215150314_巫泉彬_鸿蒙应用开发期末大作业.docx
实践报告正文
ESP32智能游戏竞技台期末汇报.pptx
期末汇报 PPT
由于 GitHub 单文件硬限制 100MB，有两个文件未包含在本仓库，需要时从别处获取：
- esp32_games.zip（118MB）— 原始提交包。里面约 90% 是 build/、oh_modules/、.hvigor/outputs/ 等编译产物与依赖缓存，真正的源码就是上面 entry/src/ 那 2800 行。清理后的版本请用 esp32_games_source.zip。
- MQTTX-Setup-1.13.0-x64.exe（103MB）— 第三方工具安装器，MQTTX 官网 可直接下载。
七、核心实现
7.1 自研 MQTT 客户端（MqttClient.ets，555 行）
HarmonyOS 侧没有内置 MQTT 库，本项目基于 @kit.NetworkKit 的 socket.TCPSocket 从零实现了 MQTT 3.1.1 客户端，不依赖任何第三方 MQTT 依赖包。实现要点：
能力
实现方式
DNS 解析
connection.getAddressesByName()，过滤出 IPv4 地址，逐个尝试连接直到成功
CONNECT / CONNACK
手工拼装报文，按位设置 username / password 标志位；等待 CONNACK 用 Promise + 5 秒超时
SUBSCRIBE / SUBACK
同上，PendingWaiter 统一管理回调、超时与清理
PUBLISH
支持双向发布与接收，解析 topic 长度 + payload
PINGREQ / PINGRESP
keepAlive / 2 定时心跳
粘包拆包
pendingBuffer 缓存 + 变长整数（Remaining Length）解析循环，TCP 分片不会丢包
报文构建方法：buildConnectPacket() / buildSubscribePacket() / buildPublishPacket() / encodeRemainingLength()。
7.2 状态管理（Index.ets）
页面级状态用 @State，跨组件单向传递用 @Prop，事件回调用函数属性。全局状态集中在 Index：选中游戏、成绩列表、已解锁成就、最新对局、MQTT 连接状态、矩阵灯当前帧。
7.3 本地存储（DatabaseHelper.ets）
基于 @kit.ArkData 的 preferences，以 JSON 字符串存储两个键：
- scores：成绩数组，读取时逐条做类型校验，脏数据直接丢弃
- unlockedAchievements：已解锁成就 ID 数组
所有读写都包了 try/catch 并打日志，存储不可用时降级为空数组，不影响主流程。
7.4 事件处理链路
ESP32 发 game_over
  → parseGameOverEvent() 校验 JSON 与字段类型
  → 更新最新对局状态
  → database.addScore() 写入成绩
  → newlyUnlockedAchievementIds() 比对门槛，命中则解锁并写库
  → 弹出复活弹窗
game_exit 事件只更新状态、不弹窗，用于玩家主动退出菜单时同步分数。
八、环境搭建与运行
8.1 软件环境
工具
版本 / 说明
DevEco Studio
6.0 或更高（需支持 API 22）
HarmonyOS SDK
targetSdkVersion 6.0.2(22)，compatibleSdkVersion 6.0.2(22)
runtimeOS
HarmonyOS
构建工具
Hvigor（工程自带 hvigor/ 配置）
代码检查
ESLint + @performance/recommended，code-linter.json5
工程零第三方运行时依赖，oh-package.json5 的 dependencies 为空，仅 devDependencies 有 hypium / hamock 两个测试库。
8.2 运行步骤
1. 用 DevEco Studio 打开工程根目录，等待 Hvigor 同步完成
2. 连接鸿蒙手机，开启「开发者选项 → USB 调试」
3. Build > Build Hap(s)/APP(s) > Build Hap(s)，产物在
entry/build/default/outputs/default/entry-default-unsigned.hap（约 565 KB）
4. 配置签名：File > Project Structure > Signing Configs 勾选自动签名并登录华为开发者账号
5. 点击 Run 部署到真机
8.3 真机联调前提
- 手机与 ESP32 不需要在同一局域网，两者都直连公网 Broker
- 手机需要网络权限：module.json5 已声明 ohos.permission.INTERNET
- Broker 端口 1883 为明文 TCP，若改用自建 Broker 且启用 TLS（8883），需要扩展 MqttClient 的 CONNECT 逻辑
- ESP32 与 APP 的用户名密码、主题名需两侧一致，都在 AppConstants.ets 里配置
8.4 验证与调试
- 用 MQTTX（安装包见同级目录 MQTTX-Setup-1.13.0-x64.exe）连接 broker.emqx.io:1883 订阅 wuquanbin/game/#，可以实时看到两侧的收发报文
- 真机上通过「其他玩法」页底部的状态面板查看当前 MQTT 连接状态
九、已完成与后续规划
已完成
- ESP32 侧四个外设驱动与四款游戏逻辑
- MQTT 双向通信链路，APP 端零依赖自研客户端
- 四个页面 + 复活弹窗的完整 UI
- 12 个成就体系与分数门槛自动判定
- 成绩落库、排行榜 Top 10
- 8×8 矩阵灯远程绘制与预设图案
- 代码检查规则配置（安全类规则设为 error）
后续可扩展
- 增加更多游戏类型
- 优化矩阵灯刷新帧率，实现更流畅的动画效果
- 增加蓝牙通信作为 MQTT 的备用通道，提升系统鲁棒性
- 接入广告 SDK，把当前的模拟广告倒计时替换为真实广告位
十、已知限制
1. 凭证明文写在源码里：AppConstants.ets 中的 Broker 用户名 / 密码为公开测试 Broker 的凭据，换成自建 Broker 时应改为线上拉取（如华为云 APIG 的设备级鉴权），不要硬编码。
2. 公共 Broker 无隔离：主题名带学号前缀做隔离，多人同时使用同一 Broker 时要避免主题冲突。
3. ESP32 固件未包含在本仓库：本工程只包含 APP 端，硬件侧代码需单独维护。
4. 仅适配 phone 设备：module.json5 的 deviceTypes 只声明了 phone，平板 / 车机需要额外适配布局。
5. 矩阵灯为整帧下发：每次操作都推完整 8 字节，帧数少时没问题，做连续动画时流量和刷新率都需要优化。
6. 无重连机制：MqttClient 在 TCP 断开后不会自动重连，需要用户手动点「连接 MQTT」。
