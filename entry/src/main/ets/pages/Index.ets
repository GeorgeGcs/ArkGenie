/**
 * ArkGenie Demo 主页：
 * 默认使用 MockTransport（无需 API Key）；
 * 接入真实大模型时替换为 OpenAiCompatibleProvider。
 */

import { ChatController } from '@arkgenie/core';
import { ChatView } from '@arkgenie/chat-ui';
import { GenUiDemo } from '../components/GenUiDemo';
import { DemoRuntime } from '../config/DemoRuntime';

@Entry
@ComponentV2
struct Index {
  private controller: ChatController = DemoRuntime.getController();

  private prompts: string[] = [
    'ArkGenie 能做什么？',
    '如何接入真实的大模型？',
    '支持停止生成和重试吗？'
  ];

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('ArkGenie Demo')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')

      Divider()
        .strokeWidth(0.5)
        .color('#E4E7ED')

      ChatView({
        controller: this.controller,
        suggestedPrompts: this.prompts
      })
        .layoutWeight(1)

      GenUiDemo()
    }
    .width('100%')
    .height('100%')
  }
}
