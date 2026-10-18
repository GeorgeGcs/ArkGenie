# 快速开始

在 DevEco Studio 中打开仓库根目录，同步依赖后直接运行 `entry` 模块即可体验 MockTransport。签名配置位于根目录 `build-profile.json5`。

```ts
import { ChatController, MockTransport } from '@arkgenie/core'
import { ChatView } from '@arkgenie/chat-ui'

private controller = new ChatController(new MockTransport())

build() {
  ChatView({ controller: this.controller, suggestedPrompts: ['ArkGenie 能做什么？'] })
}
```

接入真实服务时，将 `MockTransport` 替换为 `OpenAiCompatibleProvider`，并为宿主模块声明 `ohos.permission.INTERNET`。
