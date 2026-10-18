/**
 * 轻量 Markdown 渲染器。
 *
 * 这是一个面向流式输出的降级实现：它不依赖第三方 Markdown 引擎，
 * 对标题、段落、列表、引用和 fenced code block 提供稳定的基础渲染。
 * 未闭合的代码围栏也会立即显示，适合逐 token 更新的消息。
 */

import { ChatTheme } from '../theme/ChatTheme';

export interface MarkdownBlock {
  kind: string;
  text: string;
  level: number;
  language: string;
}

@ComponentV2
export struct MarkdownRenderer {
  @Require @Param content: string;
  @Param theme: ChatTheme = ChatTheme.default();
  @Param renderMarkdown: boolean = true;

  build() {
    Column({ space: 5 }) {
      if (this.renderMarkdown) {
        ForEach(this.parseBlocks(), (block: MarkdownBlock) => {
          if (block.kind === 'code') {
            Text(block.text)
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.codeTextColor)
              .fontFamily('monospace')
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.theme.codeBlockBackground)
              .borderRadius(6)
          } else if (block.kind === 'heading') {
            Text(this.inlineText(block.text))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
          } else if (block.kind === 'list') {
            Row({ space: 6 }) {
              Text(block.level > 0 ? `${block.level}.` : '•')
                .fontSize(this.theme.fontSize)
                .fontColor(this.theme.hintTextColor)
              Text(this.inlineText(block.text))
                .fontSize(this.theme.fontSize)
                .fontColor(this.theme.assistantTextColor)
                .textAlign(TextAlign.Start)
                .layoutWeight(1)
            }
            .width('100%')
          } else if (block.kind === 'quote') {
            Text(this.inlineText(block.text))
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding({ left: 10, right: 8, top: 5, bottom: 5 })
              .border({ width: { left: 3 }, color: this.theme.quoteBorderColor })
              .backgroundColor(this.theme.quoteBackground)
          } else {
            Text(this.inlineText(block.text))
              .fontSize(this.theme.fontSize)
              .fontColor(this.theme.assistantTextColor)
              .textAlign(TextAlign.Start)
              .width('100%')
          }
        }, (block: MarkdownBlock) => `${block.kind}-${block.level}-${block.text}`)
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

  private parseBlocks(): MarkdownBlock[] {
    const result: MarkdownBlock[] = [];
    const lines: string[] = this.content.replace(/\r/g, '').split('\n');
    let inCode = false;
    let codeLanguage = '';
    let codeLines: string[] = [];
    let paragraph: string[] = [];

    const flushParagraph = (): void => {
      if (paragraph.length > 0) {
        result.push({ kind: 'paragraph', text: paragraph.join('\n'), level: 0, language: '' });
        paragraph = [];
      }
    };
    const flushCode = (): void => {
      result.push({ kind: 'code', text: codeLines.join('\n'), level: 0, language: codeLanguage });
      codeLines = [];
      codeLanguage = '';
    };

    for (const line of lines) {
      const trimmed: string = line.trim();
      if (trimmed.startsWith('```')) {
        if (inCode) {
          flushCode();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
          codeLanguage = trimmed.substring(3).trim();
        }
        continue;
      }
      if (inCode) {
        codeLines.push(line);
        continue;
      }
      if (trimmed.length === 0) {
        flushParagraph();
        continue;
      }
      const headingMatch: RegExpMatchArray | null = trimmed.match(/^(#{1,6})\s+(.+)$/);
      if (headingMatch !== null) {
        flushParagraph();
        result.push({ kind: 'heading', text: headingMatch[2], level: headingMatch[1].length, language: '' });
        continue;
      }
      const quoteMatch: RegExpMatchArray | null = trimmed.match(/^>\s?(.*)$/);
      if (quoteMatch !== null) {
        flushParagraph();
        result.push({ kind: 'quote', text: quoteMatch[1], level: 0, language: '' });
        continue;
      }
      const unorderedMatch: RegExpMatchArray | null = trimmed.match(/^[-*+]\s+(.+)$/);
      if (unorderedMatch !== null) {
        flushParagraph();
        result.push({ kind: 'list', text: unorderedMatch[1], level: 0, language: '' });
        continue;
      }
      const orderedMatch: RegExpMatchArray | null = trimmed.match(/^(\d+)[.)]\s+(.+)$/);
      if (orderedMatch !== null) {
        flushParagraph();
        result.push({ kind: 'list', text: orderedMatch[2], level: Number(orderedMatch[1]), language: '' });
        continue;
      }
      paragraph.push(line);
    }
    if (inCode) {
      flushCode();
    } else {
      flushParagraph();
    }
    return result;
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
