/**
 * 轻量 Markdown 渲染器。
 *
 * 这是一个面向流式输出的降级实现：它不依赖第三方 Markdown 引擎，
 * 对标题、段落、列表、引用和 fenced code block 提供稳定的基础渲染。
 * 未闭合的代码围栏也会立即显示，适合逐 token 更新的消息。
 */

import { ChatTheme } from '../theme/ChatTheme';

import { MarkdownBlock, StreamingMarkdownParser } from './StreamingMarkdownParser';
export { MarkdownBlock } from './StreamingMarkdownParser';

@ComponentV2
export struct MarkdownRenderer {
  @Require @Param content: string;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param renderMarkdown: boolean = true;

  private parser: StreamingMarkdownParser = new StreamingMarkdownParser();

  build() {
    Column({ space: 5 }) {
      if (this.renderMarkdown) {
        Repeat<MarkdownBlock>(this.parser.update(this.content)).each((entry: RepeatItem<MarkdownBlock>) => {
          if (entry.item.kind === 'code') {
            Text(entry.item.text)
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.codeTextColor)
              .fontFamily('monospace')
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.theme.codeBlockBackground)
              .borderRadius(6)
          } else if (entry.item.kind === 'heading') {
            Text(this.inlineText(entry.item.text))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
          } else if (entry.item.kind === 'list') {
            Row({ space: 6 }) {
              Text(entry.item.level > 0 ? `${entry.item.level}.` : '•')
                .fontSize(this.theme.fontSize)
                .fontColor(this.theme.hintTextColor)
              Text(this.inlineText(entry.item.text))
                .fontSize(this.theme.fontSize)
                .fontColor(this.theme.assistantTextColor)
                .textAlign(TextAlign.Start)
                .layoutWeight(1)
            }
            .width('100%')
          } else if (entry.item.kind === 'quote') {
            Text(this.inlineText(entry.item.text))
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding({ left: 10, right: 8, top: 5, bottom: 5 })
              .border({ width: { left: 3 }, color: this.theme.quoteBorderColor })
              .backgroundColor(this.theme.quoteBackground)
          } else {
            Text(this.inlineText(entry.item.text))
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
          }
        }).key((block: MarkdownBlock) => block.id)
      } else {
        Text(this.content)
          .fontSize(this.theme.fontSize)
          .fontColor(this.theme.assistantTextColor)
          .textAlign(TextAlign.Start)
          .width('100%')
      }
    }
    .width('100%')
  }

  private inlineText(value: string): string {
    // 保留代码内容原样；普通文本去除最常见的强调和链接标记。
    return value
      .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
      .replace(/\*\*([^*]+)\*\*/g, '$1')
      .replace(/__([^_]+)__/g, '$1')
      .replace(/`([^`]+)`/g, '$1');
  }
}
