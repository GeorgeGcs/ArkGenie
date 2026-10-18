# ArkGenie

> HarmonyOS 上兼容 A2UI 协议的「AI 对话 + 生成式 UI」开源组件套件。
> Flutter 有 GenUI，鸿蒙有 ArkGenie。

ArkGenie 让鸿蒙开发者用十几行代码，把"接大模型的智能对话界面"完整装进自己的应用：流式渲染、发送/停止/重试、多会话、建议问题、深色模式，以及 A2UI 协议驱动的生成式 UI。

## 模块组成

| 包名 | 说明 | 状态 |
|---|---|---|
| `@arkgenie/core` | 消息模型、流式状态机、传输抽象、SSE 客户端、OpenAI 兼容 Provider | M1 ✅ |
| `@arkgenie/chat-ui` | 消息列表、气泡、输入区、建议问题、主题系统 | M1 ✅ |
| `@arkgenie/genui` | A2UI 解析/校验、Surface 状态管理、预批准组件目录和 ArkUI 渲染器 | M3 ✅ |

## 环境要求

- HarmonyOS 5.0+（compatibleSdkVersion 6.0.0(20)，targetSdkVersion 26）
- DevEco Studio 6.x（modelVersion 26.0.0）

## 安装

当前以源码/本地 HAR 方式集成（OHPM 发布包可在此基础上生成）：

```json5
// oh-package.json5
{
  "dependencies": {
    "@arkgenie/core": "file:../core",
    "@arkgenie/chat-ui": "file:../chat-ui",
    "@arkgenie/genui": "file:../genui"
  }
}
```

## 快速开始

### 1. 零配置体验（无需 API Key）

`MockTransport` 提供本地演示数据源，评审者可直接体验全部 UI：

```typescript
import { ChatController, MockTransport } from '@arkgenie/core';
import { ChatView } from '@arkgenie/chat-ui';

@Entry
@ComponentV2
struct Index {
  private controller: ChatController = new ChatController(new MockTransport());

  build() {
    ChatView({
      controller: this.controller,
      suggestedPrompts: ['ArkGenie 能做什么？']
    })
  }
}
```

### 2. 接入真实大模型（OpenAI 兼容协议）

DeepSeek / Qwen / 智谱 / 自建网关均可：

```typescript
import { ChatController, OpenAiCompatibleProvider } from '@arkgenie/core';

const provider = new OpenAiCompatibleProvider({
  baseUrl: 'https://api.deepseek.com/v1/chat/completions',
  apiKey: 'YOUR_API_KEY',
  model: 'deepseek-chat'
});
const controller = new ChatController(provider, '你是一个简洁的助手。');
```

> 模块需声明 `ohos.permission.INTERNET` 权限。

### 3. 自定义主题 / 深色模式

```typescript
import { ChatTheme } from '@arkgenie/chat-ui';

ChatView({ controller: this.controller, theme: ChatTheme.dark() })
```

## API 概览

### `@arkgenie/core`

| 导出 | 说明 |
|---|---|
| `ChatController` | 对话状态机：`send(text)` / `sendWithAttachments()` / `stop()` / `regenerate()` / `retry(id)` / `clear()`，支持切换 Provider |
| `SessionManager` | 多会话创建、切换、重命名、删除，以及可插拔 `SessionStore` / `JsonSessionStore` 持久化 |
| `ChatEventBus` | 消息发送、流式增量、完成、取消、错误、工具调用事件 |
| `ChatMessage` | 消息模型：role、content、status、contentType、attachments、metadata |
| `MessageStatus` | `sending → streaming → done / error / cancelled` |
| `ChatTransport` | 传输抽象接口，SSE/WebSocket/Mock 均可实现 |
| `SseTransport` | 通用 SSE 客户端（行缓冲、[DONE] 收尾、取消、心跳超时和可选重连） |
| `MockTransport` | 本地演示数据源（逐词吐字） |
| `OpenAiCompatibleProvider` | OpenAI Chat Completions 协议适配，含工具调用事件 |

### `@arkgenie/chat-ui`

| 导出 | 说明 |
|---|---|
| `ChatView` | 开箱即用的整页对话组件 |
| `MessageList` / `MessageBubble` | 消息列表与气泡（可单独使用） |
| `Composer` | 输入区（发送/停止切换） |
| `SuggestedPrompts` | 建议问题卡片 |
| `ChatTheme` | 主题 Token（颜色/圆角/字号），含 `default()` / `dark()` |
| `MarkdownRenderer` | 流式友好的标题、列表、引用和代码块降级渲染器 |

### `@arkgenie/genui`

| 导出 | 说明 |
|---|---|
| `A2uiParser` / `A2uiValidator` | 严格解析 A2UI 消息并校验操作、组件类型和属性白名单 |
| `A2uiSurfaceStore` | 对 surface 创建、组件 upsert、数据更新和删除操作做增量状态管理 |
| `ComponentCatalog` | 16 类内置安全组件与自定义目录注册 |
| `A2uiRendererController` / `A2uiSurfaceView` | 将声明式组件映射到 ArkUI，并通过动作事件回传 Agent |

## 示例工程

`entry/` 目录是根工程的可运行示例应用模块：DevEco Studio 打开本仓库根目录，同步后直接运行 `entry` 模块即可（默认 MockTransport，无需任何 API 配置）。公开仓库不包含证书、私钥或签名密码；需要安装到设备时，在 DevEco Studio 的项目签名配置中选择本机签名材料。签名配置只保存在本地 `build-profile.json5`，不要提交到仓库。

`docs/` 是 VitePress 中文文档站源码，可在该目录执行 `npm install` 后运行 `npm run docs:dev`。

## 开源与安全

- 本项目采用 Apache License 2.0，详见 `LICENSE`。
- `build-profile.json5` 是可公开构建配置，不包含签名材料；本地签名信息请保存在未跟踪的 `build-profile.local.json5` 或由 DevEco Studio 管理。
- 不要把 API Key、证书、私钥、`.p12`、`.p7b` 或 `.cer` 文件提交到仓库。

## 路线图

- **M1**：core 状态机 + SSE + Mock；chat-ui 基础对话 UI ✅
- **M2**：流式 Markdown 降级渲染、LazyForEach、可插拔语音/附件入口、多会话与事件总线 ✅
- **M3**：genui —— A2UI 解析/校验/渲染、16 类内置组件、动作回传、工具调用/引用/反馈 UI ✅
- **M4**：文档站与真实宿主存储适配器持续增强；DevEco 构建、设备运行和 OHPM 发布需在目标环境执行

## License

Apache-2.0
