/** Incrementally parse appended Markdown; completed prefix blocks keep stable identities. */
export interface MarkdownBlock {
  id: string;
  offset: number;
  kind: string;
  text: string;
  level: number;
  language: string;
}

export class StreamingMarkdownParser {
  private previous: string = '';
  private committed: MarkdownBlock[] = [];
  private tailStart: number = 0;
  private cached: MarkdownBlock[] = [];

  update(content: string): MarkdownBlock[] {
    const normalized = content.replace(/\r/g, '');
    if (normalized === this.previous) { return this.cached; }
    if (!normalized.startsWith(this.previous)) {
      this.committed = [];
      this.tailStart = 0;
    }
    const tail = this.parse(normalized.substring(this.tailStart), this.tailStart);
    this.cached = this.committed.concat(tail);
    // Keep the last block mutable: an unfinished paragraph/fence may grow next time.
    if (tail.length > 1) {
      this.committed = this.committed.concat(tail.slice(0, -1));
      this.tailStart = tail[tail.length - 1].offset;
    }
    this.previous = normalized;
    return this.cached;
  }

  private parse(content: string, base: number): MarkdownBlock[] {
    const result: MarkdownBlock[] = [];
    const lines: string[] = content.replace(/\r/g, '').split('\n');
    let inCode = false;
    let codeLanguage = '';
    let codeLines: string[] = [];
    let paragraph: string[] = [];
    let offset = base;
    let paragraphStart = base;
    let codeStart = base;

    const flushParagraph = (): void => {
      if (paragraph.length > 0) {
        result.push({ id: String(paragraphStart), offset: paragraphStart, kind: 'paragraph', text: paragraph.join('\n'), level: 0, language: '' });
        paragraph = [];
      }
    };
    const flushCode = (): void => {
      result.push({ id: String(codeStart), offset: codeStart, kind: 'code', text: codeLines.join('\n'), level: 0, language: codeLanguage });
      codeLines = [];
      codeLanguage = '';
    };

    for (const line of lines) {
      const lineStart = offset;
      offset += line.length + 1;
      const trimmed: string = line.trim();
      if (trimmed.startsWith('```')) {
        if (inCode) {
          flushCode();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
          codeStart = lineStart;
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
        result.push({ id: String(lineStart), offset: lineStart, kind: 'heading', text: headingMatch[2], level: headingMatch[1].length, language: '' });
        continue;
      }
      const quoteMatch: RegExpMatchArray | null = trimmed.match(/^>\s?(.*)$/);
      if (quoteMatch !== null) {
        flushParagraph();
        result.push({ id: String(lineStart), offset: lineStart, kind: 'quote', text: quoteMatch[1], level: 0, language: '' });
        continue;
      }
      const unorderedMatch: RegExpMatchArray | null = trimmed.match(/^[-*+]\s+(.+)$/);
      if (unorderedMatch !== null) {
        flushParagraph();
        result.push({ id: String(lineStart), offset: lineStart, kind: 'list', text: unorderedMatch[1], level: 0, language: '' });
        continue;
      }
      const orderedMatch: RegExpMatchArray | null = trimmed.match(/^(\d+)[.)]\s+(.+)$/);
      if (orderedMatch !== null) {
        flushParagraph();
        result.push({ id: String(lineStart), offset: lineStart, kind: 'list', text: orderedMatch[2], level: Number(orderedMatch[1]), language: '' });
        continue;
      }
      if (paragraph.length === 0) { paragraphStart = lineStart; }
      paragraph.push(line);
    }
    if (inCode) {
      flushCode();
    } else {
      flushParagraph();
    }
    return result;
  }

}
