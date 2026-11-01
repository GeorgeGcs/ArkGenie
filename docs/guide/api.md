# API 概览

## Core

- `ChatController`：发送、停止、重试、重新生成和会话切换。
- `ChatTransport`：统一传输接口，内置 `MockTransport`、`SseTransport` 和 `OpenAiCompatibleProvider`。
- `SessionManager`：多会话生命周期管理，使用 `SessionStore` 或 `JsonSessionStore` 接入宿主持久化。
- `PreferencesSessionStore`：HarmonyOS Preferences 适配，支持合并写入、显式 `flush()`、分块快照及失败重试。参见 [持久化指南](./storage.md)。
- `ChatEventBus`：发送、增量、完成、取消、错误和工具调用事件。

### 上下文和历史重试

默认发送最近 20 轮、历史正文约 32000 字符的上下文，可通过以下接口调整：

```ts
controller.setContextPolicy({ maxRounds: 10, maxCharacters: 16000 });
```

轮次从用户消息开始，裁剪保留完整轮次，不会删除本地历史。字符数不是 token 数；最新一轮和 system prompt 始终保留，因此这不是请求总长度的硬上限。

`retry(id)` 重试历史回复时只使用该回复之前的上下文。后续消息保留在本地，不会自动重算，也不会参与本次重试。

### SSE 和工具调用

`reconnectAttempts` 只对尚未输出文本或工具调用的请求生效。已有输出后断线会报错并保留部分回复，由用户重试；不会重新提交 POST 后把两次生成拼接起来。HTTP 408、429 和 5xx 可重试，其他 HTTP 错误直接失败。

OpenAI 兼容 Provider 按工具调用 `index` 聚合交错分片。`streaming` 事件的 `arguments` 是累计 JSON 字符串；正常收尾后，`done` 事件的 `arguments` 为解析后的 JSON 值。参数 JSON 不完整时发出错误，不发送工具完成事件。宿主应只在 `done` 后校验参数并决定是否执行工具。

## Chat UI

- `ChatView`：整页对话组件。
- `MarkdownRenderer`：流式友好的降级 Markdown 渲染器。
- `Composer`：多行输入，支持语音和附件事件扩展。

消息列表使用 ArkUI `Repeat.virtualScroll()`，流式内容变化时跟随底部；用户向上滚动后暂停跟随，到达底部或切换会话后恢复。Markdown 使用稳定块标识，缓存已完成前缀，仅重新解析尾部；未闭合的大段落或代码块仍需重新解析。

## GenUI

- `A2uiParser` / `A2uiValidator`：解析并校验声明式消息。
- `A2uiSurfaceStore`：应用 Surface 增量操作。
- `A2uiRendererController` / `A2uiSurfaceView`：安全渲染并回传动作。
