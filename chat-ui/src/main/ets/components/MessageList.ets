/**
 * 消息列表：List 渲染并自动跟随滚动到底部。
 *
 * 直接读取 ChatController 的消息数组，避免复制消息对象，也让流式更新
 * 继续由 ChatMessage 的 @Trace 字段驱动气泡刷新。
 */

import { ChatController, ChatMessage } from '@arkgenie/core';
import { ChatTheme } from '../theme/ChatTheme';
import { MessageBubble, MessageReference, ToolCallItem } from './MessageBubble';

@ComponentV2
export struct MessageList {
  @Require @Param controller: ChatController;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param referencesFor: (message: ChatMessage) => MessageReference[] = (_message: ChatMessage) => [];
  @Param toolCallsFor: (message: ChatMessage) => ToolCallItem[] = (_message: ChatMessage) => [];
  @Param thinkingFor: (message: ChatMessage) => string = (_message: ChatMessage) => '';
  @Param showFeedback: boolean = true;
  @Param autoFollow: boolean = true;
  @Event onQuote: (messageId: string, reference: MessageReference) => void = () => {
  };
  @Event onFeedback: (messageId: string, value: string) => void = () => {
  };
  @Event onToolAction: (messageId: string, tool: ToolCallItem) => void = () => {
  };
  @Event onCopy: (messageId: string, content: string) => void = () => {
  };
  @Event onForward: (messageId: string) => void = () => {
  };
  @Event onDelete: (messageId: string) => void = () => {
  };
  private scroller: Scroller = new Scroller();

  @Monitor('controller.messages.length')
  onMessageCountChange(): void {
    if (this.autoFollow) {
      this.scrollToEnd();
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      ForEach(this.controller.messages, (item: ChatMessage) => {
        ListItem() {
          MessageBubble({
            message: item,
            theme: this.theme,
            references: this.referencesFor(item),
            toolCalls: this.toolCallsFor(item),
            thinking: this.thinkingFor(item),
            showFeedback: this.showFeedback,
            onRetry: (messageId: string) => {
              this.controller.retry(messageId);
            },
            onQuote: (messageId: string, reference: MessageReference) => {
              this.onQuote(messageId, reference);
            },
            onFeedback: (messageId: string, value: string) => {
              this.onFeedback(messageId, value);
            },
            onToolAction: (messageId: string, tool: ToolCallItem) => {
              this.onToolAction(messageId, tool);
            },
            onCopy: (messageId: string, content: string) => {
              this.onCopy(messageId, content);
            },
            onForward: (messageId: string) => {
              this.onForward(messageId);
            },
            onDelete: (messageId: string) => {
              this.onDelete(messageId);
            }
          })
        }
      }, (item: ChatMessage) => item.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onScrollFrameBegin((offset: number) => {
      return { offsetRemain: offset };
    })
  }

  /** 供父组件在新消息到达时调用 */
  scrollToEnd(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

}
