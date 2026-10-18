/**
 * 主题 Token：颜色/圆角/字号集中可配，支持深色模式由调用方切换。
 */
export class ChatTheme {
  userBubbleColor: ResourceColor = '#0A59F7';
  userTextColor: ResourceColor = '#FFFFFF';
  assistantBubbleColor: ResourceColor = '#F1F3F5';
  assistantTextColor: ResourceColor = '#182431';
  backgroundColor: ResourceColor = '#FFFFFF';
  composerBackground: ResourceColor = '#F7F8FA';
  errorColor: ResourceColor = '#FA2A2D';
  hintTextColor: ResourceColor = '#99182431';
  bubbleRadius: Length = 12;
  bubbleMaxWidthPercent: string = '78%';
  fontSize: Length = 15;
  cursorColor: ResourceColor = '#0A59F7';
  codeBlockBackground: ResourceColor = '#E9EDF2';
  codeTextColor: ResourceColor = '#263238';
  quoteBackground: ResourceColor = '#F7F8FA';
  quoteBorderColor: ResourceColor = '#0A59F7';
  controlColor: ResourceColor = '#5F6368';

  static default(): ChatTheme {
    return new ChatTheme();
  }

  static dark(): ChatTheme {
    const theme = new ChatTheme();
    theme.assistantBubbleColor = '#2E3133';
    theme.assistantTextColor = '#E8EAED';
    theme.backgroundColor = '#121212';
    theme.composerBackground = '#1E1F20';
    theme.hintTextColor = '#99E8EAED';
    theme.codeBlockBackground = '#25282A';
    theme.codeTextColor = '#E8EAED';
    theme.quoteBackground = '#202224';
    theme.quoteBorderColor = '#8AB4F8';
    theme.controlColor = '#AEB4BE';
    return theme;
  }
}
