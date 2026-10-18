/**
 * 消息气泡：用户/AI 双样式、流式光标、Markdown、引用、工具调用和反馈区域。
 *
 * 引用与工具调用是 UI 层的可选扩展，不要求 core 改变 ChatMessage 模型；
 * 宿主可以按消息 ID 传入对应数据并接收操作事件。
 */

import { Attachment, ChatMessage, MessageStatus } from '@arkgenie/core';
import { ChatTheme } from '../theme/ChatTheme';
import { MarkdownRenderer } from './MarkdownRenderer';

export interface MessageReference {
  title: string;
  uri?: string;
  excerpt?: string;
}

export interface ToolCallItem {
  name: string;
  status?: string;
  detail?: string;
}

@ComponentV2
export struct MessageBubble {
  @Require @Param message: ChatMessage;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param references: MessageReference[] = [];
  @Param toolCalls: ToolCallItem[] = [];
  @Param thinking: string = '';
  @Param showFeedback: boolean = true;
  @Param feedback: string = '';
  @Event onRetry: (messageId: string) => void = () => {
  };
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
  @Local private showThinking: boolean = false;

  build() {
    Row() {
      if (this.message.isUser) {
        Blank()
      }
      Column({ space: 4 }) {
        if (this.message.isUser) {
          Text(this.displayText())
            .fontSize(this.theme.fontSize)
            .fontColor(this.theme.userTextColor)
            .textAlign(TextAlign.Start)
            .width('100%')
        } else {
          MarkdownRenderer({
            content: this.displayText(),
            theme: this.theme,
            renderMarkdown: true
          })
          if (this.message.status === MessageStatus.STREAMING) {
            Text('▍')
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.cursorColor)
              .margin({ left: 2 })
          }
        }

        if (this.message.attachments.length > 0) {
          Column({ space: 3 }) {
            ForEach(this.message.attachments, (attachment: Attachment) => {
              Row({ space: 5 }) {
                Text(attachment.kind === 'image' ? '图片' : '附件')
                  .fontSize(11)
                  .fontColor(this.theme.controlColor)
                Text(attachment.name)
                  .fontSize(12)
                  .fontColor(this.message.isUser ? this.theme.userTextColor : this.theme.assistantTextColor)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
            }, (attachment: Attachment) => `${attachment.kind}-${attachment.uri}-${attachment.name}`)
          }
          .width('100%')
          .padding({ top: 4 })
        }

        if (!this.message.isUser && this.references.length > 0) {
          Column({ space: 3 }) {
            Text('参考来源')
              .fontSize(11)
              .fontColor(this.theme.hintTextColor)
            ForEach(this.references, (reference: MessageReference) => {
              Row({ space: 5 }) {
                Text('引用')
                  .fontSize(11)
                  .fontColor(this.theme.controlColor)
                Text(reference.title)
                  .fontSize(12)
                  .fontColor(this.theme.userBubbleColor)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .onClick(() => {
                this.onQuote(this.message.id, reference);
              })
            }, (reference: MessageReference) => `${reference.title}-${reference.uri ?? ''}`)
          }
          .width('100%')
          .padding({ top: 4 })
        }

        if (!this.message.isUser && this.toolCalls.length > 0) {
          Column({ space: 4 }) {
            ForEach(this.toolCalls, (tool: ToolCallItem) => {
              Row({ space: 7 }) {
                Text('⚙')
                  .fontSize(12)
                  .fontColor(this.theme.controlColor)
                Column({ space: 2 }) {
                  Text(tool.name)
                    .fontSize(12)
                    .fontColor(this.theme.assistantTextColor)
                  if (tool.status !== undefined && tool.status.length > 0) {
                    Text(tool.status)
                      .fontSize(11)
                      .fontColor(this.theme.hintTextColor)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('查看')
                  .fontSize(11)
                  .fontColor(this.theme.userBubbleColor)
                  .onClick(() => {
                    this.onToolAction(this.message.id, tool);
                  })
              }
              .width('100%')
            }, (tool: ToolCallItem) => `${tool.name}-${tool.status ?? ''}`)
          }
          .width('100%')
          .padding({ top: 4 })
        }

        if (!this.message.isUser && this.thinking.length > 0) {
          Text(this.showThinking ? '收起思考过程' : '查看思考过程')
            .fontSize(11)
            .fontColor(this.theme.controlColor)
            .onClick(() => {
              this.showThinking = !this.showThinking;
            })
          if (this.showThinking) {
            Text(this.thinking)
              .fontSize(12)
              .fontColor(this.theme.hintTextColor)
              .padding(8)
              .backgroundColor(this.theme.composerBackground)
          }
        }

        if (this.message.status === MessageStatus.ERROR) {
          Row({ space: 8 }) {
            Text(`发送失败：${this.message.errorText}`)
              .fontSize(12)
              .fontColor(this.theme.errorColor)
            Text('重试')
              .fontSize(12)
              .fontColor(this.theme.userBubbleColor)
              .onClick(() => {
                this.onRetry(this.message.id);
              })
          }
          .margin({ top: 6 })
        }
        if (this.message.status === MessageStatus.CANCELLED) {
          Text('已停止生成')
            .fontSize(12)
            .fontColor(this.theme.hintTextColor)
            .margin({ top: 6 })
        }
        if (!this.message.isUser && this.message.status === MessageStatus.DONE && this.showFeedback) {
          Row({ space: 14 }) {
            Text(this.feedback === 'up' ? '已赞' : '赞')
              .fontSize(11)
              .fontColor(this.feedback === 'up' ? this.theme.userBubbleColor : this.theme.hintTextColor)
              .onClick(() => {
                this.onFeedback(this.message.id, 'up');
              })
            Text(this.feedback === 'down' ? '已踩' : '踩')
              .fontSize(11)
              .fontColor(this.feedback === 'down' ? this.theme.errorColor : this.theme.hintTextColor)
              .onClick(() => {
                this.onFeedback(this.message.id, 'down');
              })
          }
          .margin({ top: 3 })
        }
        if (this.message.status === MessageStatus.DONE) {
          Row({ space: 12 }) {
            Text('复制')
              .fontSize(11)
              .fontColor(this.theme.hintTextColor)
              .onClick(() => this.onCopy(this.message.id, this.message.content))
            Text('转发')
              .fontSize(11)
              .fontColor(this.theme.hintTextColor)
              .onClick(() => this.onForward(this.message.id))
            Text('删除')
              .fontSize(11)
              .fontColor(this.theme.errorColor)
              .onClick(() => this.onDelete(this.message.id))
          }
          .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.message.isUser ? this.theme.userBubbleColor : this.theme.assistantBubbleColor)
      .borderRadius(this.theme.bubbleRadius)
      .constraintSize({ maxWidth: this.theme.bubbleMaxWidthPercent })

      if (!this.message.isUser) {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  private displayText(): string {
    if (this.message.status === MessageStatus.SENDING) {
      return '正在思考…';
    }
    return this.message.content;
  }
}
