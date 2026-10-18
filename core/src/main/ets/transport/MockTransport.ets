/**
 * Mock 传输：本地演示数据源，逐词吐字模拟流式回复。
 * 评审/体验者无需 API Key 即可体验全部 UI；也可用于单元测试。
 */

import { ChatRequest, ChatTask, ChatTransport, StreamCallbacks } from './ChatTransport';

const DEMO_REPLY: string =
  '你好，我是 **ArkGenie** 演示助手。这条回复来自本地 `MockTransport`，' +
  '用于在没有 API Key 的情况下体验流式对话。\n\n' +
  '当前消息支持：\n\n' +
  '- 逐词流式渲染\n' +
  '- 发送 / 停止切换\n' +
  '- 失败重试与重新生成\n\n' +
  '接入真实大模型时，只需把 transport 换成 `OpenAiCompatibleProvider`，' +
  '指向任意 OpenAI 兼容服务（DeepSeek、Qwen、智谱等）即可。';

class MockChatTask implements ChatTask {
  private cancelAction: () => void;

  constructor(cancelAction: () => void) {
    this.cancelAction = cancelAction;
  }

  cancel(): void {
    this.cancelAction();
  }
}

export class MockTransport implements ChatTransport {
  private intervalMs: number;

  constructor(intervalMs: number = 60) {
    this.intervalMs = intervalMs;
  }

  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask {
    // 按词切分并保留空白分隔符，模拟逐词输出
    const tokens = DEMO_REPLY.split(/(\s+)/);
    let index = 0;
    let fullText = '';
    let cancelled = false;

    const timer = setInterval(() => {
      if (cancelled) {
        clearInterval(timer);
        return;
      }
      if (index >= tokens.length) {
        clearInterval(timer);
        callbacks.onComplete(fullText);
        return;
      }
      const delta = tokens[index];
      index++;
      fullText += delta;
      callbacks.onChunk(delta);
    }, this.intervalMs);

    const task: ChatTask = new MockChatTask((): void => {
        cancelled = true;
        clearInterval(timer);
      });
    return task;
  }
}
