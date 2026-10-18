# Changelog

## [0.2.0] - 2026-10 (完整代码版)

### Added
- `@arkgenie/core`
  - `SessionManager`、可插拔 `SessionStore` 和消息快照恢复
  - `ChatEventBus` 全链路事件：发送、增量、完成、取消、重试、错误、工具调用
  - 请求代次隔离，取消/迟到回调不会污染新请求
- `@arkgenie/chat-ui`
  - 流式友好的 Markdown 降级渲染器（标题、列表、引用、代码块）
  - `LazyForEach` 虚拟化消息列表
  - 多行 Composer、语音/附件可插拔入口
  - 引用来源、工具调用、赞/踩反馈事件
- `@arkgenie/genui`
  - A2UI JSON 解析、操作校验、属性白名单和 Surface 增量状态管理
  - 16 类内置安全组件及 `A2uiSurfaceView` ArkUI 渲染器
  - 生成式 UI 动作回传 Agent
- `demo`
  - A2UI 本地预览
  - `DemoConfig` 支持 Mock 与 OpenAI 兼容 Provider 切换

### Notes
- 本版本完成目标代码范围；DevEco 构建、设备运行、签名和 OHPM 发布仍需在 HarmonyOS 开发环境执行。

## [0.1.0] - 2026-10 (M1)

### Added
- `@arkgenie/core`
  - 消息模型 `ChatMessage`（role/content/status/attachments）
  - 消息状态机：`sending → streaming → done / error / cancelled`
  - 传输抽象 `ChatTransport` + 通用 SSE 客户端 `SseTransport`
  - `MockTransport` 本地演示数据源（无需 API Key 体验全部 UI）
  - `OpenAiCompatibleProvider`：DeepSeek/Qwen/智谱等 OpenAI 兼容协议
  - `ChatController`：send / stop / retry / regenerate / clear，50ms 流式节流刷写
- `@arkgenie/chat-ui`
  - `ChatView` 整页对话组件
  - `MessageList` / `MessageBubble`（流式光标、失败重试、停止标记）
  - `Composer`（发送/停止切换）
  - `SuggestedPrompts` 建议问题
  - `ChatTheme` 主题 Token（default / dark）
- `@arkgenie/genui`
  - A2UI 消息类型与 `ComponentCatalog` 注册表骨架（渲染器 M3 实现）
- `demo` 示例应用：MockTransport 开箱即用

### Notes
- 会话持久化、LazyForEach 长列表优化、语音输入、FluidMarkdown 流式渲染列入 M2
