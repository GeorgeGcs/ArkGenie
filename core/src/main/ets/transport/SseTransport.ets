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
  connectTimeoutMs?: number;
  readTimeoutMs?: number;
  /** 首次连接失败后的最大重连次数，默认 0。 */
  reconnectAttempts?: number;
  /** 重连间隔，默认 500ms。 */
  reconnectDelayMs?: number;
  /** 超过该时间没有任何 SSE 数据/注释则重连，0 表示关闭。 */
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
    let client = http.createHttp();
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
      try {
        client.destroy();
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
      if (attempts >= maxRetries) {
        fail(err);
        return;
      }
      attempts += 1;
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
        if (this.options.parseToolCall && callbacks.onToolCall) {
          const toolCall = this.options.parseToolCall(payload);
          if (toolCall !== null) {
            callbacks.onToolCall(toolCall);
          }
        }
        const delta = this.options.parsePayload(payload);
        if (delta !== null && delta.length > 0) {
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
      lineBuffer = '';
      doneSignal = false;
      lastActivity = Date.now();
      client = http.createHttp();
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

      client.on('dataReceive', (data: ArrayBuffer) => {
        if (cancelled || completed) { return; }
        lastActivity = Date.now();
        const text = decoder.decodeToString(new Uint8Array(data), { stream: true });
        lineBuffer += text;
        let idx = lineBuffer.indexOf('\n');
        while (idx >= 0) {
          const line = lineBuffer.substring(0, idx);
          lineBuffer = lineBuffer.substring(idx + 1);
          handleLine(line);
          idx = lineBuffer.indexOf('\n');
        }
      });
      client.on('dataEnd', () => {
        if (cancelled || completed) { return; }
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
      client.on('dataReceiveProgress', () => {
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
      client.requestInStream(this.options.url, options)
        .then((code: number) => {
          if (code >= 400) {
            retryOrFail(new Error(`HTTP ${code}`), start);
          }
        })
        .catch((err: Error) => {
          retryOrFail(err, start);
        });
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
