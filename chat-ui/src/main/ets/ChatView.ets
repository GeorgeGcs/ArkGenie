/**
 * ChatView：开箱即用的整页对话组件。
 * 用法：ChatView({ controller, theme? , suggestedPrompts? })
 */

import { ChatController, ChatMessage } from '@arkgenie/core';
import { ChatTheme } from './theme/ChatTheme';
import { MessageList } from './components/MessageList';
import { Composer } from './components/Composer';
import { SuggestedPrompts } from './components/SuggestedPrompts';
import { MessageReference, ToolCallItem } from './components/MessageBubble';

@ComponentV2
export struct ChatView {
  @Require @Param controller: ChatController;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param suggestedPrompts: string[] = [];
  @Param enableVoice: boolean = false;
  @Param enableAttachment: boolean = false;
  @Param autoFollow: boolean = true;
  @Param showFeedback: boolean = true;
  @Param referencesFor: (message: ChatMessage) => MessageReference[] =
    (_message: ChatMessage) => [];
  @Param toolCallsFor: (message: ChatMessage) => ToolCallItem[] =
    (_message: ChatMessage) => [];
  @Param thinkingFor: (message: ChatMessage) => string =
    (_message: ChatMessage) => '';
  @Event onVoice: () => void = () => {
  };
  @Event onAttachment: () => void = () => {
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

  build() {
    Column() {
      if (this.controller.messages.length === 0 && this.suggestedPrompts.length > 0) {
        Blank()
        SuggestedPrompts({
          prompts: this.suggestedPrompts,
          theme: this.theme,
          onPick: (text: string) => {
            this.controller.send(text);
          }
        })
      } else {
        MessageList({
          controller: this.controller,
          theme: this.theme,
          referencesFor: this.referencesFor,
          toolCallsFor: this.toolCallsFor,
          thinkingFor: this.thinkingFor,
          autoFollow: this.autoFollow,
          showFeedback: this.showFeedback,
          onQuote: this.onQuote,
          onFeedback: this.onFeedback,
          onToolAction: this.onToolAction,
          onCopy: this.onCopy,
          onForward: this.onForward,
          onDelete: this.onDelete
        })
      }

      Composer({
        isGenerating: this.controller.isGenerating,
        theme: this.theme,
        enableVoice: this.enableVoice,
        enableAttachment: this.enableAttachment,
        onSend: (text: string) => {
          this.controller.send(text);
        },
        onStop: () => {
          this.controller.stop();
        },
        onVoice: () => {
          this.onVoice();
        },
        onAttachment: () => {
          this.onAttachment();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.backgroundColor)
  }
}
