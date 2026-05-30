# Privacy Policy / 隐私政策

**Last updated: 2026-05-30**

## English

open-maestri ("the App") is an open-source multi-agent orchestration canvas for macOS. We are committed to protecting your privacy.

### Data Collection

The App does **not** collect, store, or transmit any personal data to external servers.

### How It Works

- The App communicates exclusively over **local IPC** (Unix Socket and TCP on `127.0.0.1`) between itself and AI agent terminals running on your Mac.
- All data (agent sessions, canvas state, terminal output, sticky notes) is stored locally on your device and never transmitted to any external server.
- No analytics, telemetry, or crash reporting services are used.
- No third-party SDKs or tracking frameworks are included.

### Local Storage

The App stores workspace data, preferences, and terminal scrollback locally under `~/.open-maestri/`. This data never leaves your device.

### Contact

If you have any questions about this privacy policy, please open an issue at:  
https://github.com/zlh-428/open-maestri/issues

---

## 中文

open-maestri（"本应用"）是一款 macOS 上的开源多智能体编排画布。我们致力于保护您的隐私。

### 数据收集

本应用**不会**收集、存储或向外部服务器传输任何个人数据。

### 工作原理

- 本应用仅通过**本地 IPC**（Unix Socket 及 `127.0.0.1` 上的 TCP 端口）与运行在您 Mac 上的 AI 智能体终端通信。
- 所有数据（智能体会话、画布状态、终端输出、便签内容）均存储在本地设备上，不会传输至任何外部服务器。
- 不使用任何分析、遥测或崩溃报告服务。
- 不包含任何第三方 SDK 或追踪框架。

### 本地存储

本应用将工作区数据、偏好设置及终端滚动缓冲存储在 `~/.open-maestri/` 目录下。这些数据不会离开您的设备。

### 联系方式

如果您对本隐私政策有任何疑问，请在以下地址提交 issue：  
https://github.com/zlh-428/open-maestri/issues
