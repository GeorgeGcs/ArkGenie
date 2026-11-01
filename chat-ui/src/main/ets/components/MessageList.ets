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
  private following: boolean = true;
  private followTimer: number | null = null;

  @Monitor('controller.messages.length', 'controller.contentRevision')
  onMessageCountChange(): void {
    if (this.autoFollow && this.following && this.followTimer === null) {
      this.followTimer = setTimeout(() => {
        this.followTimer = null;
        if (this.autoFollow && this.following) { this.scrollToEnd(); }
      }, 0);
    }
  }

  @Monitor('controller.currentSessionId')
  onSessionChange(): void {
    this.following = true;
    this.onMessageCountChange();
  }

  aboutToDisappear(): void {
    if (this.followTimer !== null) {
      clearTimeout(this.followTimer);
      this.followTimer = null;
    }
  }

  build() {
    List({ scroller: this.scroller }) {
      Repeat<ChatMessage>(this.controller.messages).each((entry: RepeatItem<ChatMessage>) => {
        ListItem() {
          MessageBubble({
            message: entry.item,
            theme: this.theme,
            references: this.referencesFor(entry.item),
            toolCalls: this.toolCallsFor(entry.item),
            thinking: this.thinkingFor(entry.item),
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
      }).key((item: ChatMessage) => item.id).virtualScroll()
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .onScrollFrameBegin((offset: number) => {
      if (offset < 0) { this.following = false; }
      return { offsetRemain: offset };
    })
    .onReachEnd(() => { this.following = true; })
  }

  /** 供父组件在新消息到达时调用 */
  scrollToEnd(): void {
    this.following = true;
    this.scroller.scrollEdge(Edge.Bottom);
  }

}
