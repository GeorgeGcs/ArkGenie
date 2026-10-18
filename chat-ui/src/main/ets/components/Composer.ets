/**
 * 输入区：多行输入 + 发送/停止切换，并提供可插拔的语音与附件入口。
 * 入口默认关闭，宿主通过 enableVoice/enableAttachment 和对应事件接入能力。
 */

import { ChatTheme } from '../theme/ChatTheme';

@ComponentV2
export struct Composer {
  @Param isGenerating: boolean = false;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param placeholder: string = '给 ArkGenie 发送消息…';
  @Param enableVoice: boolean = false;
  @Param enableAttachment: boolean = false;
  @Param submitOnEnter: boolean = true;
  @Event onSend: (text: string) => void = () => {
  };
  @Event onStop: () => void = () => {
  };
  @Event onVoice: () => void = () => {
  };
  @Event onAttachment: () => void = () => {
  };
  @Local private inputText: string = '';

  build() {
    Row({ space: 8 }) {
      if (this.enableVoice) {
        Text('🎙')
          .fontSize(20)
          .fontColor(this.theme.controlColor)
          .width(32)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onVoice();
          })
      }
      if (this.enableAttachment) {
        Text('📎')
          .fontSize(20)
          .fontColor(this.theme.controlColor)
          .width(32)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onAttachment();
          })
      }
      TextArea({ text: $$this.inputText, placeholder: this.placeholder })
        .layoutWeight(1)
        .height(76)
        .fontSize(this.theme.fontSize)
        .backgroundColor(this.theme.assistantBubbleColor)
        .borderRadius(14)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .maxLength(20000)
        .onSubmit(() => {
          if (this.submitOnEnter) {
            this.handleSend();
          }
        })

      if (this.isGenerating) {
        Button('停止')
          .height(42)
          .fontSize(14)
          .backgroundColor(this.theme.errorColor)
          .onClick(() => {
            this.onStop();
          })
      } else {
        Button('发送')
          .height(42)
          .fontSize(14)
          .backgroundColor(this.inputText.trim().length > 0 ? this.theme.userBubbleColor : '#C0C4CC')
          .enabled(this.inputText.trim().length > 0)
          .onClick(() => {
            this.handleSend();
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.theme.composerBackground)
  }

  private handleSend(): void {
    const text = this.inputText.trim();
    if (text.length === 0) {
      return;
    }
    this.inputText = '';
    this.onSend(text);
  }
}
