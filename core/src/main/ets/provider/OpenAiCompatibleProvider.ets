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
  index?: number;
  id?: string;
  function?: ToolCallFunctionDelta;
}

interface StreamChunk {
  choices?: DeltaChoice[];
}

export class OpenAiCompatibleProvider implements ChatTransport {
  private config: OpenAiCompatibleConfig;

  constructor(config: OpenAiCompatibleConfig) {
    this.config = config;
  }

  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask {
    const config = this.config;
    // 每次 send 独立聚合，Provider 可安全复用或并发调用。
    const pending = new Map<number, ToolCall>();
    const sse = new SseTransport({
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
      parseToolCalls: (payload: string): ToolCall[] => {
        const chunk = JSON.parse(payload) as StreamChunk;
        const delta = chunk.choices && chunk.choices.length > 0 ? chunk.choices[0].delta : undefined;
        const calls = delta === undefined ? undefined : delta.tool_calls;
        if (!calls || calls.length === 0) {
          return [];
        }
        const updates: ToolCall[] = [];
        for (const call of calls) {
          const index = call.index ?? 0;
          const previous = pending.get(index);
          const tool: ToolCall = {
            name: (previous?.name ?? '') + (call.function?.name ?? ''),
            callId: call.id ?? previous?.callId,
            arguments: String(previous?.arguments ?? '') + (call.function?.arguments ?? ''),
            status: 'streaming'
          };
          pending.set(index, tool);
          updates.push(tool);
        }
        return updates;
      },
      reconnectAttempts: config.reconnectAttempts,
      reconnectDelayMs: config.reconnectDelayMs,
      heartbeatTimeoutMs: config.heartbeatTimeoutMs
    });
    const wrapped: StreamCallbacks = {
      onChunk: callbacks.onChunk,
      onError: callbacks.onError,
      onToolCall: callbacks.onToolCall,
      onComplete: (fullText: string): void => {
        const completed: ToolCall[] = [];
        try {
          for (const tool of pending.values()) {
            completed.push({
              name: tool.name,
              callId: tool.callId,
              arguments: JSON.parse(String(tool.arguments || '{}')) as Object,
              status: 'done'
            });
          }
        } catch (e) {
          callbacks.onError(new Error('Invalid tool call arguments JSON'));
          return;
        }
        if (callbacks.onToolCall) {
          for (const tool of completed) { callbacks.onToolCall(tool); }
        }
        callbacks.onComplete(fullText);
      }
    };
    return sse.send(request, wrapped);
  }
}
