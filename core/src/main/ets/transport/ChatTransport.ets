/**
 * 传输层抽象：一次"发送消息并流式接收回复"即一次 send 调用。
 * 内置实现：SseTransport（SSE）、MockTransport（本地演示数据源）。
 */

import { WireMessage } from '../model/ChatMessage';

export interface ChatRequest {
  messages: WireMessage[];
  model?: string;
  extraHeaders?: Record<string, string>;
}

export interface StreamCallbacks {
  /** 增量 token/文本片段 */
  onChunk: (delta: string) => void;
  /** 流正常结束，fullText 为完整文本 */
  onComplete: (fullText: string) => void;
  /** 传输或解析失败 */
  onError: (err: Error) => void;
  /** Agent 工具调用事件（可选，旧 Transport 无需实现）。 */
  onToolCall?: (tool: ToolCall) => void;
}

export interface ToolCall {
  name: string;
  callId?: string;
  arguments?: Object;
  status?: string;
  result?: Object;
}

export interface ChatTask {
  cancel(): void;
}

export interface ChatTransport {
  send(request: ChatRequest, callbacks: StreamCallbacks): ChatTask;
}
