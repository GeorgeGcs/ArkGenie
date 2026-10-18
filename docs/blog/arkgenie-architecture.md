# 从一段 SSE 到一个可交互 Surface：ArkGenie 的技术原理

ArkGenie 的关键代码不在某个按钮的样式，而在几条边界：网络回调不能直接改 UI，旧请求不能污染新请求，流式文本不能每个字符都触发一次完整刷新，远端生成的界面不能变成一段可执行脚本。

这篇文章沿着一条消息的生命周期看代码：用户点击发送之后，数据如何进入 Transport，如何经过 `ChatController` 变成消息状态，如何被 `ChatView` 观察；接着再看 A2UI 消息如何从 JSON 变成一个可渲染、可回传动作的 Surface。

## 1. 先把传输层关在接口后面

核心层没有把 HTTP 客户端写进 `ChatController`。它只依赖一个很小的接口：

```ts
export interface ChatTransport {
  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask;
}

export interface ChatTask {
  cancel(): void;
}
```

回调有四种：

```ts
export interface StreamCallbacks {
  onChunk: (delta: string) => void;
  onComplete: (fullText: string) => void;
  onError: (err: Error) => void;
  onToolCall?: (tool: ToolCall) => void;
}
```

这几个方法对应的是一次请求的生命周期，而不是某一种网络协议。`MockTransport` 用定时器实现它，`SseTransport` 用 `requestInStream` 实现它，应用也可以自行写 WebSocket 或本地推理 Transport。

这样设计的直接收益是测试简单。测试控制器时不需要真的访问网络，传入一个按顺序调用 `onChunk` 和 `onComplete` 的假 Transport 就行。演示工程里的 Mock 也因此不是一套特殊 UI，而是正式接口的一种实现。

## 2. SSE 客户端做的事情其实很具体

`SseTransport` 没有试图理解所有模型厂商的协议，它只负责 SSE 的公共部分，具体 payload 由配置传入的解析函数处理。

一条事件到达时，代码会经历下面这几步：

1. 用 UTF-8 解码收到的 `ArrayBuffer`；
2. 把文本追加到 `lineBuffer`；
3. 按换行切出完整行，保留最后一段不完整内容；
4. 只处理 `data:` 开头的行；
5. 遇到 `[DONE]` 结束请求；
6. 其余内容交给 `parsePayload`，得到文本增量后调用 `onChunk`。

保留行缓冲很重要。网络分片和 SSE 的换行没有一一对应关系，一次 `dataReceive` 可能只收到半行，也可能收到多行。如果直接对每个网络回调做 `JSON.parse`，偶发的半包就会变成解析错误。

代码里的核心处理可以概括成这样：

```ts
client.on('dataReceive', (data: ArrayBuffer) => {
  const text = decoder.decodeToString(new Uint8Array(data), { stream: true });
  lineBuffer += text;

  let index = lineBuffer.indexOf('\n');
  while (index >= 0) {
    const line = lineBuffer.substring(0, index);
    lineBuffer = lineBuffer.substring(index + 1);
    handleLine(line);
    index = lineBuffer.indexOf('\n');
  }
});
```

`handleLine` 还会更新最后活动时间。开启 `heartbeatTimeoutMs` 后，如果一段时间没有收到数据或注释行，Transport 会销毁当前客户端并按配置重连。连接失败和流提前结束也可以重试；达到次数之后才回调 `onError`。

单条事件解析失败不会立刻掐断整个流。这是一个有意的取舍：有些服务会在流里夹带不含文本的事件，例如角色信息或工具调用片段。解析器应该记录或忽略这类事件，而不是让已经收到的正文全部变成错误状态。

## 3. OpenAI 兼容 Provider 只是协议适配器

`OpenAiCompatibleProvider` 把配置转换成 `SseTransport` 所需的几项函数：

- 请求地址和 `Authorization` 请求头；
- 请求体，包含 `model`、`stream: true` 和消息数组；
- 从 `choices[0].delta.content` 取正文；
- 从 `delta.tool_calls` 取工具调用片段。

它没有维护消息数组，也没有决定失败之后气泡显示什么。Provider 的职责越窄，换成 DeepSeek、Qwen、智谱或自建网关时，其他层越不需要修改。只要服务能返回接近 OpenAI Chat Completions 的 SSE 数据，就可以复用这一层。

## 4. `ChatController` 是真正的状态机

发送一条消息时，控制器会先做三件事：

1. 把用户输入加入当前会话；
2. 创建一个空的 assistant 消息，状态设为 `sending`；
3. 生成本次请求的 `requestId`，再调用 Transport。

消息状态定义在 `ChatMessage` 中：

```ts
export enum MessageStatus {
  IDLE = 'idle',
  SENDING = 'sending',
  STREAMING = 'streaming',
  DONE = 'done',
  ERROR = 'error',
  CANCELLED = 'cancelled'
}
```

第一段文本到来时，消息从 `sending` 进入 `streaming`。正常结束后保存完整文本并进入 `done`；Transport 出错进入 `error`；用户点停止则进入 `cancelled`。

### 为什么要有 requestId

只保存一个 `currentTask` 不够。取消网络请求是异步的，某些实现可能在 `cancel()` 之后仍然触发一个已经排队的回调；用户快速重试时，旧回调甚至可能和新请求交错到达。

ArkGenie 为每次请求递增一个序号，同时保存目标消息 ID。所有回调进入控制器后，先检查：

```ts
private isActive(requestId: number, targetId: string): boolean {
  return this.activeRequestId === requestId &&
    this.activeTargetId === targetId &&
    this.isGenerating;
}
```

不匹配就直接丢弃。停止操作也遵循同一个顺序：先把 `activeRequestId` 置零，让后续回调失效，再调用 Transport 的 `cancel()`。这比先 cancel、再修改状态更可靠，因为某些取消实现可能同步触发回调。

### 为什么不是每个 chunk 都写入消息

网络层可能很快，ArkUI 的渲染和布局不应该跟着每个 token 运行。控制器收到 chunk 后先放入 `pendingDelta`，然后安排一个 50 毫秒后的刷新任务。刷新时把这段内容一次性追加到消息里，再交给 `@Trace` 驱动 UI 更新。

这不是为了制造延迟，而是把网络事件频率和 UI 刷新频率分开。回复仍然是流式的，但页面不会因为一秒几十次的字符串写入而反复做完整布局。

## 5. UI 层只观察控制器

`ChatView` 接收一个 `ChatController`，消息列表直接读取 `controller.messages`。`MessageList` 用消息 ID 作为 `ForEach` 的 key，气泡组件接收具体的 `ChatMessage` 对象。

```ts
List({ scroller: this.scroller }) {
  ForEach(this.controller.messages, (item: ChatMessage) => {
    ListItem() {
      MessageBubble({
        message: item,
        theme: this.theme,
        onRetry: (messageId: string) => {
          this.controller.retry(messageId);
        }
      })
    }
  }, (item: ChatMessage) => item.id)
}
```

`ChatMessage` 是 `@ObservedV2` 对象，内容和状态字段使用 `@Trace`。因此流式文本追加时，气泡可以更新，而不需要在页面层复制一份消息数组再做手工同步。

组件只保留显示相关的出口。停止按钮调用 `controller.stop()`，重试按钮调用 `controller.retry(id)`，语音、附件、复制和反馈则通过事件交给宿主应用。页面不会因为接入一个新的文件选择器而修改核心状态机。

## 6. 事件总线用于观察，不替代状态机

`ChatEventBus` 发布这些事件：

```text
message.sent
message.chunk
message.received
message.completed
message.cancelled
message.retry
tool.call
error
```

事件里带有 `sessionId`、`messageId`、时间戳和普通 JSON payload。埋点、日志、工具调用卡片都可以订阅这些事件，但它们不应该反过来修改消息状态。

事件总线通知监听器时会复制监听器数组，并隔离每个监听器的异常。一个埋点回调写错，不能把正在进行的对话请求一起打断。这种处理在开发环境看起来有些保守，但对宿主应用很有用：业务层的观察逻辑永远不是主链路的一部分。

## 7. A2UI 的处理链路：解析、校验、存储、渲染

生成式 UI 的难点不在于把 JSON 转成几个 `Button`，而在于定义远端数据的边界。ArkGenie 把这条链路拆成四步：

```text
JSON
  │
  ▼
A2uiParser
  │  结构解析
  ▼
A2uiValidator + ComponentCatalog
  │  类型和属性白名单
  ▼
A2uiSurfaceStore
  │  增量应用操作
  ▼
A2uiSurfaceView
  │  映射到 ArkUI
  ▼
用户操作 → A2uiAction
```

一条最小消息可以这样写：

```json
[
  { "op": "createSurface", "surfaceId": "main" },
  {
    "op": "upsertComponent",
    "surfaceId": "main",
    "component": {
      "id": "hello",
      "type": "text",
      "props": { "text": "Hello ArkGenie" },
      "children": []
    }
  }
]
```

`A2uiParser` 只负责把 JSON 变成显式模型。它检查 `op`、`surfaceId`、组件 ID 和组件类型字段是否存在，但不会因为字段存在就认为消息安全。

`A2uiValidator` 再使用 `ComponentCatalog` 做两层检查：组件类型是否在目录中，属性是否属于该类型的允许列表。比如 `button` 可以有 `text`、`label`、`action` 和 `enabled`，未知属性会被拒绝。

`A2uiSurfaceStore` 保存每个 Surface 的组件 Map、根节点 ID 和数据模型。收到 `createSurface`、`upsertComponent`、`updateData` 或 `removeComponent` 时，它只修改受影响的部分，然后重新计算没有被其他组件引用的根节点。

这里没有把组件树直接存成一棵深层嵌套对象，而是用 ID 引用子组件。这样做更适合流式增量消息：父组件先到、子组件后到，或者某个子组件单独更新，都不需要重新发送整棵树。

## 8. 为什么组件属性使用 `Map` 封装

ArkTS 对匿名对象和任意索引访问有更严格的限制。A2UI 的属性来自 JSON，直接写成 `node.props[key]` 会让模型类型变得模糊，也容易把不受控的对象访问带进渲染层。

项目使用 `A2uiProps` 封装属性：

```ts
export class A2uiProps {
  private values: Map<string, Object> = new Map();

  set(key: string, value: Object): void {
    this.values.set(key, value);
  }

  get(key: string): Object | undefined {
    return this.values.get(key);
  }
}
```

渲染器再按需要取值，并做局部转换：数字属性用 `Number` 解析，布尔属性使用默认值兜底，列表属性必须是数组。这样，协议数据的宽松性被限制在模型边界内，ArkUI Builder 内部拿到的是可预测的类型。

## 9. 渲染器不会执行远端代码

`A2uiSurfaceView` 根据节点类型映射到固定的 ArkUI 组件：

- `text`、`markdown` 映射为 `Text`；
- `button` 映射为 `Button`；
- `row`、`column`、`card`、`confirm` 映射为布局容器；
- `input` 映射为 `TextInput`；
- `list` 映射为 `List`；
- `image`、`progress`、`badge`、`divider` 等使用对应的内置组件。

未知类型只显示“不支持的组件”提示。组件目录里即使注册了自定义类型，也必须由宿主提供对应的目录和属性规则。远端消息只能选择已经批准的类型，不能把一段 ArkTS、JavaScript 或函数塞进 `props` 后让客户端执行。

## 10. 动作怎么回到 Agent

渲染器不会直接发网络请求。按钮点击、输入变化、确认和拒绝操作会构造成 `A2uiAction`，交给 `A2uiRendererController` 的 `actionListener`：

```ts
controller.setActionListener((action: A2uiAction) => {
  // 由宿主决定如何发给 Agent 或业务后端
  console.info(JSON.stringify(action));
});
```

例如确认按钮产生的动作包含 `type: confirm`、组件 ID 和动作名称。宿主可以把它接入已有的 ChatTransport，也可以直接调用业务 API。渲染器只负责把用户操作标准化，不假设 Agent 一定使用哪种传输协议。

## 11. 这套设计留下了哪些边界

ArkGenie 当前更像一个基础设施层，而不是完整的 Agent 平台。它不替应用解决这些问题：

- API Key 和用户身份的安全管理；
- 服务端工具执行和权限审计；
- 语音识别、文件上传和图片压缩；
- 具体业务的消息数据库；
- A2UI 之外的厂商协议适配。

这些边界是有意留下的。组件库可以定义稳定的输入输出，但不应把宿主应用的账号、网络、存储和业务权限一起接管。

从代码结构看，ArkGenie 的主线很清楚：Transport 产生事件，Controller 维护状态，UI 观察状态；A2UI 则把远端声明式数据经过目录校验后变成 Surface，再把用户操作沿着监听器交还给宿主。每一层都做自己擅长的事，换掉其中一层时，其他层不必跟着重写。
