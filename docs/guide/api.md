# API 概览

## Core

- `ChatController`：发送、停止、重试、重新生成和会话切换。
- `ChatTransport`：统一传输接口，内置 `MockTransport`、`SseTransport` 和 `OpenAiCompatibleProvider`。
- `SessionManager`：多会话生命周期管理，使用 `SessionStore` 或 `JsonSessionStore` 接入宿主持久化。
- `PreferencesSessionStore`：HarmonyOS Preferences 适配，支持合并写入、显式 `flush()`、分块快照及失败重试。参见 [持久化指南](./storage.md)。
- `ChatEventBus`：发送、增量、完成、取消、错误和工具调用事件。

## Chat UI

- `ChatView`：整页对话组件。
- `MarkdownRenderer`：流式友好的降级 Markdown 渲染器。
- `Composer`：多行输入，支持语音和附件事件扩展。

## GenUI

- `A2uiParser` / `A2uiValidator`：解析并校验声明式消息。
- `A2uiSurfaceStore`：应用 Surface 增量操作。
- `A2uiRendererController` / `A2uiSurfaceView`：安全渲染并回传动作。
