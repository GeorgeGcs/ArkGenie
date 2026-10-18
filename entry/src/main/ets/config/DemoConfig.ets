import { ChatTransport, MockTransport, OpenAiCompatibleProvider } from '@arkgenie/core';

/** Demo 运行配置。默认 Mock，宿主只需修改这一处即可切换真实服务。 */
export class DemoConfig {
  static useMock: boolean = true;
  static baseUrl: string = 'https://api.deepseek.com/v1/chat/completions';
  static apiKey: string = '';
  static model: string = 'deepseek-chat';

  static createTransport(): ChatTransport {
    if (DemoConfig.useMock || DemoConfig.apiKey.trim().length === 0) {
      return new MockTransport();
    }
    return new OpenAiCompatibleProvider({
      baseUrl: DemoConfig.baseUrl,
      apiKey: DemoConfig.apiKey,
      model: DemoConfig.model
    });
  }
}
