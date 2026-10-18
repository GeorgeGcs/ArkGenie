/**
 * 建议问题：空会话时展示的可点击问题卡片。
 */

import { ChatTheme } from '../theme/ChatTheme';

@ComponentV2
export struct SuggestedPrompts {
  @Param prompts: string[] = [];
  @Param theme: ChatTheme = ChatTheme.default();
  @Event onPick: (text: string) => void = () => {
  };

  build() {
    Column({ space: 10 }) {
      ForEach(this.prompts, (item: string) => {
        Text(item)
          .fontSize(14)
          .fontColor(this.theme.assistantTextColor)
          .padding({
            left: 14,
            right: 14,
            top: 10,
            bottom: 10
          })
          .backgroundColor(this.theme.assistantBubbleColor)
          .borderRadius(10)
          .onClick(() => {
            this.onPick(item);
          })
      }, (item: string) => item)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
  }
}
