# 在 HarmonyOS 上做一套真正能接入应用的 AI 对话组件：ArkGenie 项目介绍

很多 AI 对话 Demo 的代码并不长。一个输入框、一个消息列表，再调用一次大模型接口，页面就能把回复显示出来。

真正把它放进应用之后，问题会很快出现：用户点击停止时，网络回调还在继续；上一轮请求晚到的内容混进了新消息；失败消息没有办法重试；切换会话之后，旧会话的内容还在刷新；流式文本每来一个字符就刷新一次页面，列表开始抖动。

ArkGenie 处理的就是这部分工作。它不是一个只负责画气泡的 UI 组件，而是一套面向 HarmonyOS ArkUI 的 AI 对话与生成式 UI 组件套件。项目把消息状态、传输层、会话管理、聊天界面和 A2UI 渲染拆成了几个独立模块，宿主应用可以按需要使用。

## 先跑起来：不用 API Key 的演示工程

仓库里的 `entry` 是完整的应用入口。打开仓库根目录，在 DevEco Studio 中同步依赖，运行 `entry` 模块即可看到聊天页面。

演示工程默认使用 `MockTransport`，所以不需要填写 API Key，也不需要先准备一个后端服务。它会把固定回复按词切开，间隔一小段时间交给上层，表现出和真实流式回复相同的 UI 行为。

最小用法大致是这样：

```ts
import { ChatController, MockTransport } from '@arkgenie/core';
import { ChatView } from '@arkgenie/chat-ui';

@Entry
@ComponentV2
struct Index {
  private controller: ChatController = new ChatController(
    new MockTransport(),
    '你是一个简洁、友善的助手。'
  );

  build() {
    ChatView({
      controller: this.controller,
      suggestedPrompts: [
        'ArkGenie 能做什么？',
        '如何接入真实的大模型？'
      ]
    })
  }
}
```

这个例子里没有把消息数组复制到页面组件中。`ChatView` 直接观察 `ChatController`，输入、停止、重试和滚动都由组件内部完成。宿主只需要决定使用哪个 Transport，以及是否接入自己的主题、会话存储和业务事件。

## 仓库里有哪些模块

ArkGenie 目前由三个 HAR 模块和一个可运行的示例入口组成。

### `@arkgenie/core`

这是不依赖具体 UI 的核心层，负责：

- `ChatMessage` 消息模型和消息状态；
- `ChatController` 对话状态机；
- `ChatTransport` 传输抽象；
- `SseTransport`、`MockTransport` 和 OpenAI 兼容 Provider；
- `SessionManager` 多会话管理和持久化接口；
- `ChatEventBus` 对外发布消息发送、增量、完成、取消、错误和工具调用事件。

核心层只要求 Transport 实现 `send` 方法，并返回一个带 `cancel()` 的任务对象。这样，真实网络、Mock 数据、测试替身甚至 WebSocket 实现都可以放进同一套状态机。

### `@arkgenie/chat-ui`

这个模块提供可以直接放进页面的聊天 UI：

- `ChatView` 整页聊天组件；
- `MessageList` 和 `MessageBubble` 消息列表与气泡；
- `Composer` 多行输入区，支持发送和停止切换；
- `SuggestedPrompts` 建议问题；
- `ChatTheme` 主题 Token；
- 一个不依赖第三方库的 Markdown 降级渲染器。

`ChatView` 的参数刻意保留了几个应用层出口，例如语音、附件、引用、反馈、工具操作和复制事件。组件负责显示和交互，文件选择、语音服务、埋点和业务处理仍由宿主应用决定。

### `@arkgenie/genui`

`genui` 用来处理 A2UI 风格的声明式界面。它包含：

- JSON 解析器；
- 操作、组件类型和属性白名单校验；
- `Surface` 增量状态容器；
- 内置组件目录；
- ArkUI 渲染器和按钮、输入框、确认操作的事件回传。

远端消息只描述“显示什么”和“发生了什么操作”，不会把 ArkTS 代码传到客户端执行。未知组件会显示降级提示，不会通过 `eval` 或脚本执行的方式绕过目录限制。

### `entry`

`entry` 是根工程的启动模块，主要用于演示和验收。它把三个库装配成一个可运行应用，也给出了 MockTransport 的默认配置。发布组件包时，宿主应用可以只依赖 `core`，也可以按页面需要引入 `chat-ui` 和 `genui`。

## 从 Mock 切换到真实模型

当页面和交互确认没有问题后，可以把 Transport 换成 `OpenAiCompatibleProvider`。它接收一个 OpenAI Chat Completions 风格的配置：

```ts
import {
  ChatController,
  OpenAiCompatibleProvider
} from '@arkgenie/core';

const provider = new OpenAiCompatibleProvider({
  baseUrl: 'https://api.example.com/v1/chat/completions',
  apiKey: 'YOUR_API_KEY',
  model: 'your-model',
  reconnectAttempts: 2,
  reconnectDelayMs: 500,
  heartbeatTimeoutMs: 30000
});

const controller = new ChatController(
  provider,
  '你是一个简洁、友善的助手。'
);
```

Provider 只做协议适配：把消息转换成请求体，添加 `Authorization` 请求头，解析 SSE 中的增量内容和工具调用。真正的消息生命周期仍由 `ChatController` 管理。这样做的好处是，换模型服务不会影响聊天界面，换界面也不会影响网络层。

生产应用里不建议把长期有效的 API Key 硬编码进客户端。更稳妥的方式是由应用后端提供短期凭据或统一代理，再让 ArkGenie 连接业务网关。示例工程只为了说明接口形态，默认仍然走本地 Mock。

## 会话和持久化不是写死的

`ChatController` 默认创建 `SessionManager`，而 `SessionManager` 默认使用内存存储。这对 Demo 足够，但应用退出后数据不会保留。

如果宿主已经有 Preferences 或数据库封装，只需实现 `SessionStore`，或者实现更小的 `SessionValueStore` 后使用 `JsonSessionStore`：

```ts
import {
  JsonSessionStore,
  SessionValueStore,
  SessionManager,
  ChatController
} from '@arkgenie/core';

class PreferencesValueStore implements SessionValueStore {
  get(key: string): string | null {
    // 从宿主的 Preferences 读取字符串
    return null;
  }

  set(key: string, value: string): void {
    // 写入宿主的 Preferences
  }

  remove(key: string): void {
    // 删除宿主的 Preferences 键
  }
}

const store = new JsonSessionStore(new PreferencesValueStore());
const sessions = new SessionManager(store);
const controller = new ChatController(new MockTransport(), '', sessions);
```

消息落盘时保存的是快照，不包含函数和运行时代码。宿主可以把快照写入自己的存储，也可以在退出前选择只保留最近几轮消息。

## 一套组件，几种使用方式

如果只需要调用模型并自己画 UI，可以只引入 `@arkgenie/core`：

```ts
const controller = new ChatController(new MockTransport());
controller.send('你好');
```

如果想快速搭一个聊天页面，使用 `ChatView`：

```ts
ChatView({
  controller: this.controller,
  theme: ChatTheme.dark(),
  suggestedPrompts: ['帮我整理一份会议纪要']
})
```

如果应用需要让 Agent 动态生成卡片、表单或确认框，再把 `genui` 接上。三层并不是一整块不可替换的页面模板，而是从核心状态机向上逐层增加能力。

## 这个项目适合解决什么问题

ArkGenie 适合已经有 HarmonyOS 应用、但不想从头重复实现 AI 对话基础设施的团队。它把最容易互相缠绕的几部分拆开：网络层处理流，控制器处理状态，组件处理显示，宿主处理业务服务和数据存储。

这种拆分也意味着它不会替宿主应用决定所有事情。账号体系、API Key 的保管、语音服务、文件上传、消息审核和业务数据库，都应该留在应用自己的边界内。

如果你的需求只是一个静态问答页，直接写一个页面可能更快。如果需要停止、重试、多会话、流式输出、工具调用和生成式 UI，这些边界会让后续迭代轻松很多。

## 当前状态

仓库已经包含可运行的 `entry` 示例、三个 HAR 模块、中文文档和 Apache License 2.0。当前版本的重点是把核心链路跑通：Mock 流式回复、SSE、OpenAI 兼容协议、聊天 UI、会话抽象和 A2UI 渲染器。

下一步更值得投入的地方，是把宿主存储适配、真实设备上的性能数据和 OHPM 发布流程补齐，而不是继续把所有功能塞进 Demo 页面。
