/**
 * OpenAI 兼容协议 Provider：覆盖 DeepSeek / Qwen / 智谱 / 自建网关等
 * 所有遵循 OpenAI Chat Completions SSE 格式的服务。
 */

import { ChatRequest, ChatTask, ChatTransport, StreamCallbacks, ToolCall } from '../transport/ChatTransport';
import { SseTransport } from '../transport/SseTransport';

export interface OpenAiCompatibleConfig {
  /** 例如 https://api.deepseek.com/v1/chat/completions */
  baseUrl: string;
  apiKey: string;
  model: string;
  /** 额外请求参数（temperature 等），JSON 片段，可选 */
  extraBody?: Record<string, Object>;
  reconnectAttempts?: number;
  reconnectDelayMs?: number;
  heartbeatTimeoutMs?: number;
}

interface DeltaChoice {
  delta?: DeltaContent;
}

interface DeltaContent {
  content?: string;
  tool_calls?: ToolCallDelta[];
}

interface ToolCallFunctionDelta {
  name?: string;
  arguments?: string;
}

interface ToolCallDelta {
  id?: string;
  function?: ToolCallFunctionDelta;
}

interface StreamChunk {
  choices?: DeltaChoice[];
}

export class OpenAiCompatibleProvider implements ChatTransport {
  private sse: SseTransport;

  constructor(config: OpenAiCompatibleConfig) {
    this.sse = new SseTransport({
      url: config.baseUrl,
      headers: {
        'Authorization': `Bearer ${config.apiKey}`
      },
      buildBody: (request: ChatRequest): string => {
        const body: Record<string, Object> = {
          'model': request.model ?? config.model,
          'stream': true,
          'messages': request.messages
        };
        if (config.extraBody) {
          const keys = Object.keys(config.extraBody);
          for (const k of keys) {
            body[k] = config.extraBody[k];
          }
        }
        return JSON.stringify(body);
      },
      parsePayload: (payload: string): string | null => {
        const chunk = JSON.parse(payload) as StreamChunk;
        const choices = chunk.choices;
        if (!choices || choices.length === 0) {
          return null;
        }
        const delta = choices[0].delta;
        if (!delta || delta.content === undefined) {
          return null;
        }
        return delta.content;
      },
      parseToolCall: (payload: string): ToolCall | null => {
        const chunk = JSON.parse(payload) as StreamChunk;
        const delta = chunk.choices && chunk.choices.length > 0 ? chunk.choices[0].delta : undefined;
        const calls = delta === undefined ? undefined : delta.tool_calls;
        if (!calls || calls.length === 0) {
          return null;
        }
        const call = calls[0];
        return {
          name: call.function === undefined ? 'tool' : (call.function.name ?? 'tool'),
          callId: call.id,
          arguments: call.function === undefined ? undefined : call.function.arguments,
          status: 'streaming'
        };
      },
      reconnectAttempts: config.reconnectAttempts,
      reconnectDelayMs: config.reconnectDelayMs,
      heartbeatTimeoutMs: config.heartbeatTimeoutMs
    });
  }

  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask {
    return this.sse.send(request, callbacks);
  }
}
