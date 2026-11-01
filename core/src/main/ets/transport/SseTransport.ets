/**
 * SSE 客户端：基于 @kit.NetworkKit 的 requestInStream。
 * 支持行缓冲、[DONE] 收尾、取消、心跳超时和可选断线重连。
 */

import { http } from '@kit.NetworkKit';
import util from '@ohos.util';
import { ChatRequest, ChatTask, ChatTransport, StreamCallbacks, ToolCall } from './ChatTransport';

export interface SseOptions {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  buildBody: (request: ChatRequest) => string;
  parsePayload: (payload: string) => string | null;
  /** 可选工具调用解析器；不支持工具调用的 Provider 可省略。 */
  parseToolCall?: (payload: string) => ToolCall | null;
  parseToolCalls?: (payload: string) => ToolCall[];
  connectTimeoutMs?: number;
  readTimeoutMs?: number;
  /** 尚未输出文本或工具调用时的最大重试次数，默认 0。 */
  reconnectAttempts?: number;
  /** 重连间隔，默认 500ms。 */
  reconnectDelayMs?: number;
  /** 超过该时间无数据则失败；未输出内容时可重试，0 表示关闭。 */
  heartbeatTimeoutMs?: number;
}

class SseChatTask implements ChatTask {
  private cancelAction: () => void;

  constructor(cancelAction: () => void) {
    this.cancelAction = cancelAction;
  }

  cancel(): void {
    this.cancelAction();
  }
}

export class SseTransport implements ChatTransport {
  private options: SseOptions;

  constructor(options: SseOptions) {
    this.options = options;
  }

  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask {
    let client: http.HttpRequest | null = null;
    let generation = 0;
    let receivedContent = false;
    let cancelled = false;
    let completed = false;
    let lineBuffer = '';
    let fullText = '';
    let attempts = 0;
    let doneSignal = false;
    let lastActivity = Date.now();
    let retryTimer: number | null = null;
    let heartbeatTimer: number | null = null;

    const clearTimers = (): void => {
      if (retryTimer !== null) {
        clearTimeout(retryTimer);
        retryTimer = null;
      }
      if (heartbeatTimer !== null) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = null;
      }
    };

    const destroyClient = (): void => {
      const previous = client;
      client = null;
      try {
        if (previous !== null) { previous.destroy(); }
      } catch (e) {
        // 销毁是尽力操作。
      }
    };

    const fail = (err: Error): void => {
      if (cancelled || completed) {
        return;
      }
      completed = true;
      clearTimers();
      destroyClient();
      callbacks.onError(err);
    };

    const finish = (): void => {
      if (cancelled || completed) {
        return;
      }
      completed = true;
      clearTimers();
      destroyClient();
      callbacks.onComplete(fullText);
    };

    const retryOrFail = (err: Error, start: () => void): void => {
      if (cancelled || completed) {
        return;
      }
      if (retryTimer !== null) {
        return;
      }
      const maxRetries = this.options.reconnectAttempts ?? 0;
      // POST 生成请求不能从中间安全续传；已有文本/工具事件时交给用户重试。
      if (receivedContent || attempts >= maxRetries) {
        fail(err);
        return;
      }
      attempts += 1;
      generation += 1;
      destroyClient();
      retryTimer = setTimeout(() => {
        retryTimer = null;
        if (!cancelled && !completed) {
          start();
        }
      }, this.options.reconnectDelayMs ?? 500) as number;
    };

    const handleLine = (rawLine: string): void => {
      const line = rawLine.trim();
      lastActivity = Date.now();
      if (line.length === 0 || line.startsWith(':')) {
        return;
      }
      if (!line.startsWith('data:')) {
        return;
      }
      const payload = line.substring(5).trim();
      if (payload === '[DONE]') {
        doneSignal = true;
        finish();
        return;
      }
      try {
        if (this.options.parseToolCalls) {
          for (const toolCall of this.options.parseToolCalls(payload)) {
            receivedContent = true;
            if (callbacks.onToolCall) { callbacks.onToolCall(toolCall); }
          }
        }
        if (!this.options.parseToolCalls && this.options.parseToolCall) {
          const toolCall = this.options.parseToolCall(payload);
          if (toolCall !== null) {
            receivedContent = true;
            if (callbacks.onToolCall) { callbacks.onToolCall(toolCall); }
          }
        }
        const delta = this.options.parsePayload(payload);
        if (delta !== null && delta.length > 0) {
          receivedContent = true;
          fullText += delta;
          callbacks.onChunk(delta);
        }
      } catch (e) {
        // 单条事件解析失败不阻断整个流，后续事件仍可继续。
      }
    };

    const start = (): void => {
      if (cancelled || completed) {
        return;
      }
      try {
        lineBuffer = '';
        doneSignal = false;
        lastActivity = Date.now();
        client = http.createHttp();
        const connection = client;
        const connectionId = ++generation;
        const isCurrent = (): boolean => !cancelled && !completed && connectionId === generation;
        const decoder = util.TextDecoder.create('utf-8');

        const headers: Record<string, string> = {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache'
        };
        if (this.options.headers) {
          for (const key of Object.keys(this.options.headers)) {
            headers[key] = this.options.headers[key];
          }
        }
        if (request.extraHeaders) {
          for (const key of Object.keys(request.extraHeaders)) {
            headers[key] = request.extraHeaders[key];
          }
        }

        connection.on('dataReceive', (data: ArrayBuffer) => {
          if (!isCurrent()) { return; }
          lastActivity = Date.now();
          const text = decoder.decodeToString(new Uint8Array(data), { stream: true });
          lineBuffer += text;
          let idx = lineBuffer.indexOf('\n');
          while (idx >= 0 && isCurrent()) {
            const line = lineBuffer.substring(0, idx);
            lineBuffer = lineBuffer.substring(idx + 1);
            handleLine(line);
            idx = lineBuffer.indexOf('\n');
          }
        });
        connection.on('dataEnd', () => {
          if (!isCurrent()) { return; }
          if (lineBuffer.length > 0) {
            handleLine(lineBuffer);
            lineBuffer = '';
          }
          if (doneSignal || completed) {
            finish();
          } else {
            retryOrFail(new Error('SSE stream ended before [DONE]'), start);
          }
        });
        connection.on('dataReceiveProgress', () => {
          if (!isCurrent()) { return; }
          lastActivity = Date.now();
        });

        if (this.options.heartbeatTimeoutMs && this.options.heartbeatTimeoutMs > 0 && heartbeatTimer === null) {
          const interval = Math.max(1000, Math.floor(this.options.heartbeatTimeoutMs / 2));
          heartbeatTimer = setInterval(() => {
            if (!cancelled && !completed && Date.now() - lastActivity > (this.options.heartbeatTimeoutMs ?? 0)) {
              retryOrFail(new Error('SSE heartbeat timeout'), start);
            }
          }, interval) as number;
        }

        const options: http.HttpRequestOptions = {
          method: (this.options.method ?? 'POST') as http.RequestMethod,
          header: headers,
          extraData: this.options.buildBody(request),
          connectTimeout: this.options.connectTimeoutMs ?? 15000,
          readTimeout: this.options.readTimeoutMs ?? 60000
        };
        connection.requestInStream(this.options.url, options)
          .then((code: number) => {
            if (!isCurrent()) { return; }
            if (code >= 400) {
              if (code === 408 || code === 429 || code >= 500) {
                retryOrFail(new Error(`HTTP ${code}`), start);
              } else {
                fail(new Error(`HTTP ${code}`));
              }
            }
          })
          .catch((err: Error) => {
            if (!isCurrent()) { return; }
            retryOrFail(err, start);
          });
      } catch (e) {
        fail(new Error('SSE request setup failed'));
      }
    };

    start();
    const task: ChatTask = new SseChatTask((): void => {
        if (cancelled || completed) { return; }
        cancelled = true;
        clearTimers();
        destroyClient();
      });
    return task;
  }
}
