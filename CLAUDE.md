# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

仿「悟空遥控」的局域网手机遥控器。手机装客户端（`app`），TV 装服务端（`server`），二者在同一局域网内通过 **UDP 自定义二进制协议**通信，由服务端注入按键事件实现遥控。

这是一个单 Gradle 工程下的**两个 Android 应用模块**：

| 模块 | 角色 | 包名 | 语言 |
| --- | --- | --- | --- |
| `app` | 手机客户端 | `com.minsheng.controller` | Kotlin + Java 混合 |
| `server` | TV 服务端 | `com.minsheng.controller.server` | Kotlin |

构建环境：Gradle 6.5 / AGP 4.1.0 / Kotlin 1.3.72 / compileSdk 30 / minSdk 16 / JDK 1.8。两个模块都启用了 **DataBinding**。

## 常用命令

```bash
# 构建（Windows 下用 gradlew.bat）
./gradlew assembleDebug                 # 构建两个模块
./gradlew :app:assembleDebug            # 只构建客户端
./gradlew :server:assembleDebug         # 只构建服务端

# 安装到已连接设备
./gradlew :app:installDebug
./gradlew :server:installDebug

# 单元测试
./gradlew test                          # 全部
./gradlew :app:testDebugUnitTest        # 客户端
./gradlew :app:testDebugUnitTest --tests "com.minsheng.controller.ExampleUnitTest"

# 清理
./gradlew clean
```

**注意**：`build.gradle` 中仓库用的是已停服的 `jcenter()`。若依赖拉取失败，需将 `jcenter()` 替换为 `mavenCentral()`。此外 `app/src/test/` 下的 `UdpClient.java` / `UdpServer.java` 是早期调试用的手写 UDP 收发样例，不是有效的单元测试。

## 通信架构（核心）

### 协议格式

所有数据包使用 `DatagramSocket`，**定长 1400 字节**缓冲，10 字节包头（`DATA_PACKET_TITLE_SIZE = 10`），数据体从下标 10 开始。

| 字节 | 含义 |
| --- | --- |
| `[0]` | 高 2 位 version（固定 `1<<6`），低 6 位 deviceId：**55=手机、56=AndroidTV、57=LinuxTV**（标识**发送方**） |
| `[1]` | 低 7 位 load_type，最高位 receive_flag（1=需要应答 `NEED_REPLY`） |
| `[2..3]` | SN 传输序列，小端 |
| `[4]` | UUID/循环计数器 0~255，用于应答匹配与重传 |
| `[8..9]` | 包总长度 packetLength，小端 |
| `[10..]` | 数据体 |

### load_type 常量

两端的常量表需**保持同步**：`app/.../util/NetConst.java`、`app/.../util/NetUtil.kt`、`server/.../util/NetUtil.kt`。

- `51` IR_KEY 按键、`52` BROADCAST 发现广播、`53` INPUT_TEXT 文本输入
- `55` VIRTUAL_MOUSE、`56` FILE、`59/60` 键盘文本/功能键
- `120` REQUEST_CONNECTION、`121` DISCONNECTION、`122` CONNECTSTATUS（心跳）

### 端口分配

| 端口 | 用途 |
| --- | --- |
| 5555 | 手机广播发现 / 服务端接收；按键与命令双向主通道 |
| 5556 | 服务端 → 手机的应答与连接请求 |
| 5557 / 5558 | 文件传输发送 / 接收（`SendFileRunnale`，尚未接线） |

### 连接建立流程

1. 手机端 `NetUtils.InitGetClient` 每 2.5s 向 `255.255.255.255:5555` 广播（`STTP_LOAD_TYPE_BROADCAST`），包体为 `Build.PRODUCT` 设备名。
2. 服务端 `NetUtil.ReceiverRunnable` 在 5555 收到广播，解析出手机 IP 后，回发 `REQUEST_CONNECTION`（携带 TV 的 `Build.PRODUCT`）到该 IP。
3. 手机端 `NetUtils.ReceiveRunnale` 在 5556 收到应答，把 TV 加入设备列表（`MSG_FIND_OUT_DEVICE`），并将首个设备设为 `ipClient`。
4. 之后手机向已知 `ipClient:5555` 单播按键数据；服务端解析后注入按键。

### 按键注入（仅服务端）

服务端用 `android.app.Instrumentation.sendKeyDownUpSync(keyCode)` 注入按键，需要系统级权限：

```xml
<uses-permission android:name="android.permission.INJECT_EVENTS" />
```

因此 **server 必须以系统签名（或 root）安装**才能实际生效。

长按由 `LongKeyRunnable` 模拟：收到 `LONG_KEY_START` 后每隔 100ms 注入一次按下/松开，直到收到 `LONG_KEY_END` 才停止。注意 README 中提到的风险——若客户端在长按期间崩溃/退出，`ACTION_UP` 丢失会导致服务端无限注入，需靠超时机制兜底。

### 服务端保活

`RemoteService` 是**前台服务**（`startForeground`），`RemoteReceiver` 监听 `BOOT_COMPLETED` 与自定义 `com.minsheng.controller.server.destroy` 广播用于拉起服务。`ServerActivity` 启动时调用 `NetUtil.init()` 开始监听。

## 客户端 UI

- `MainActivity`：遥控主界面，通过 DataBinding 绑定各按键回调，按键码直接取 `KeyEvent.KEYCODE_*`。
- `DeviceListActivity`：设备搜索列表（RecyclerView + `DevicesAdapter` + `DeviceInfo`），15s 连接超时。
- `DirectionDpadView`：自定义 View，手绘 5 向方向盘。触摸点按**极坐标**判定扇区——以 View 中心为原点，`mOkRadius`（直径 2/5 宽）内为确定键，否则按 `|x|/|y|` 大小与正负判定上/下/左/右。`GestureDetector` 负责长按识别，`onLongPress`/`ACTION_UP` 回调上下行事件。
- 自定义 BindingAdapter `setDirectionKeyListener` 定义在 `util/DbTool.kt`，供 XML 的 `app:setDirectionKeyListener` 使用。

## 需要注意的代码现状

- **客户端存在两份网络实现**：实际生效的是 `app/.../util/NetUtils.java`（单例、继承 `Handler`、静态工厂 `getInstance()`）。而 `app/.../util/NetUtil.kt` 是**未被引用的重复实现**（其 `getByteBuffer` 里 deviceId 写成 56，是 TV 的值，进一步说明是遗留死代码）。修改客户端网络逻辑时应改 `NetUtils.java`。
- `app/.../util/NetUtil.kt` 的 `injectKeyEvent` 为空实现（注释掉了 `InputManager`），客户端本就不应注入按键。
- 心跳（`CONNECTSTATUS`）相关逻辑在客户端 `NetUtils` 中已被注释停用，`sendFile` 未完成。
- 代码中的类注释模板（ClassName/Author/Date/Description）风格统一，新增文件应保持一致。
