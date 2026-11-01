/**
 * ChatController：对话状态机与 UI 之间的桥梁。
 *
 * 除了基础的发送/停止/重试，它还负责把消息同步到 SessionManager，
 * 并通过 ChatEventBus 发出可观测事件。每次请求都有独立 requestId，
 * 被取消或结束的旧请求即使晚到回调，也不会污染当前消息。
 */

import { Attachment, ChatMessage, MessageRole, MessageStatus, WireMessage } from './model/ChatMessage';
import { ChatEventBus, ChatEventType } from './event/ChatEventBus';
import { SessionManager } from './session/SessionManager';
import { ChatTask, ChatRequest, ChatTransport, StreamCallbacks, ToolCall } from './transport/ChatTransport';
import { genId } from './utils/Id';

interface MessageSentPayload {
  content: string;
  attachments: Attachment[];
}

interface RegeneratePayload {
  regenerate: boolean;
}

interface MessageChunkPayload {
  delta: string;
}

interface MessageReceivedPayload {
  content: string;
}

interface ErrorPayload {
  message: string;
}

interface ToolCallEventPayload {
  name: string;
  callId?: string;
  arguments?: Object;
  status?: string;
  result?: Object;
}

export interface ChatContextPolicy {
  /** 保留最近完整轮次，默认 20。 */
  maxRounds?: number;
  /** 历史正文字符预算（非 token）；最新一轮和 system prompt 始终保留。默认 32000。 */
  maxCharacters?: number;
}

@ObservedV2
export class ChatController {
  @Trace messages: ChatMessage[] = [];
  @Trace isGenerating: boolean = false;
  @Trace inputEnabled: boolean = true;
  @Trace contentRevision: number = 0;

  private transport: ChatTransport;
  private currentTask: ChatTask | null = null;
  private pendingDelta: string = '';
  private pendingTargetId: string = '';
  private flushTimer: number | null = null;
  private systemPrompt: string = '';
  private requestSequence: number = 0;
  private activeRequestId: number = 0;
  private activeTargetId: string = '';
  @Trace private sessionId: string = '';
  private sessions: SessionManager;
  private events: ChatEventBus;
  private contextPolicy: ChatContextPolicy = { maxRounds: 20, maxCharacters: 32000 };
  private persistTimer: number | null = null;

  constructor(transport: ChatTransport, systemPrompt: string = '', sessionManager?: SessionManager,
    eventBus?: ChatEventBus) {
    this.transport = transport;
    this.systemPrompt = systemPrompt;
    this.sessions = sessionManager ?? new SessionManager();
    this.events = eventBus ?? new ChatEventBus();

    let current = this.sessions.current;
    if (!current) {
      current = this.sessions.create();
    }
    this.sessionId = current.id;
    this.messages = current.messages;
  }

  get eventBus(): ChatEventBus {
    return this.events;
  }

  get sessionManager(): SessionManager {
    return this.sessions;
  }

  @Computed
  get currentSessionId(): string {
    return this.sessionId;
  }

  setContextPolicy(policy: ChatContextPolicy): void {
    const maxRounds = policy.maxRounds ?? 20;
    const maxCharacters = policy.maxCharacters ?? 32000;
    if (!Number.isInteger(maxRounds) || maxRounds < 1 ||
      !Number.isInteger(maxCharacters) || maxCharacters < 1) {
      throw new Error('Context limits must be positive integers');
    }
    this.contextPolicy = { maxRounds, maxCharacters };
  }

  /** 宿主后台保存前调用；先把 UI 缓冲同步到会话快照。 */
  persistCurrent(): void {
    const target = this.findById(this.activeTargetId);
    if (target) {
      this.flushFor(target, this.activeRequestId);
    }
    this.persistMessages();
  }

  /** 在空闲时切换 Mock/真实 Provider，便于设置页动态切换服务。 */
  setTransport(transport: ChatTransport): boolean {
    if (this.isGenerating) {
      return false;
    }
    this.transport = transport;
    return true;
  }

  /** 发送一条用户消息并请求流式回复。 */
  send(text: string): void {
    this.sendWithAttachments(text, []);
  }

  /** 发送文本和附件；附件只作为安全元数据传给宿主/Provider。 */
  sendWithAttachments(text: string, attachments: Attachment[]): void {
    const trimmed = text.trim();
    if (trimmed.length === 0 || this.isGenerating) {
      return;
    }
    const userMsg = new ChatMessage(genId('u'), MessageRole.USER, trimmed);
    userMsg.status = MessageStatus.DONE;
    userMsg.attachments = attachments.slice();
    this.messages.push(userMsg);

    const assistantMsg = new ChatMessage(genId('a'), MessageRole.ASSISTANT, '');
    assistantMsg.status = MessageStatus.SENDING;
    this.messages.push(assistantMsg);
    this.persistMessages();
    const sentPayload: MessageSentPayload = {
      content: trimmed,
      attachments: userMsg.attachments
    };
    this.events.emit(ChatEventType.MESSAGE_SENT, this.sessionId, userMsg.id, sentPayload);

    this.requestStream(assistantMsg);
  }

  /** 停止当前生成。回调失效先于 cancel，避免同步/迟到回调改写状态。 */
  stop(): void {
    if (!this.isGenerating && this.currentTask === null) {
      return;
    }
    const requestId = this.activeRequestId;
    this.cancelFlush();
    const target = this.findById(this.activeTargetId);
    if (target && requestId !== 0) {
      this.flushFor(target, requestId);
      target.status = MessageStatus.CANCELLED;
      this.persistMessages();
      this.events.emit(ChatEventType.MESSAGE_CANCELLED, this.sessionId, target.id);
    }
    // 先使回调失效，再调用 transport.cancel。
    this.activeRequestId = 0;
    this.activeTargetId = '';
    const task = this.currentTask;
    this.currentTask = null;
    this.pendingDelta = '';
    this.pendingTargetId = '';
    this.isGenerating = false;
    if (task) {
      try {
        task.cancel();
      } catch (e) {
        // 取消是尽力操作，不能让 UI 崩溃。
      }
    }
  }

  /** 重新生成最后一条 AI 回复。 */
  regenerate(): void {
    if (this.isGenerating) {
      return;
    }
    const last = this.lastAssistant();
    if (!last) {
      return;
    }
    last.content = '';
    last.errorText = '';
    last.status = MessageStatus.SENDING;
    const regeneratePayload: RegeneratePayload = { regenerate: true };
    this.events.emit(ChatEventType.MESSAGE_RETRY, this.sessionId, last.id, regeneratePayload);
    this.requestStream(last);
  }

  /** 重试失败气泡或被取消的回复。 */
  retry(messageId: string): void {
    if (this.isGenerating) {
      return;
    }
    const target = this.findById(messageId);
    if (!target || target.role !== MessageRole.ASSISTANT) {
      return;
    }
    target.content = '';
    target.errorText = '';
    target.status = MessageStatus.SENDING;
    this.events.emit(ChatEventType.MESSAGE_RETRY, this.sessionId, target.id);
    this.requestStream(target);
  }

  clear(): void {
    this.stop();
    this.messages = [];
    this.persistMessages();
  }

  /** 创建并切换到新会话。 */
  newSession(title: string = '新会话'): string {
    this.stop();
    const session = this.sessions.create(title);
    this.sessionId = session.id;
    this.messages = session.messages;
    return session.id;
  }

  /** 切换会话并返回是否成功。 */
  switchSession(sessionId: string): boolean {
    if (sessionId === this.sessionId) {
      return true;
    }
    this.stop();
    const session = this.sessions.select(sessionId);
    if (!session) {
      return false;
    }
    this.sessionId = session.id;
    this.messages = session.messages;
    return true;
  }

  deleteSession(sessionId: string): boolean {
    if (sessionId === this.sessionId) {
      this.stop();
    }
    const deleted = this.sessions.delete(sessionId);
    if (!deleted) {
      return false;
    }
    let current = this.sessions.current;
    if (!current) {
      current = this.sessions.create();
    }
    this.sessionId = current.id;
    this.messages = current.messages;
    return true;
  }

  private lastAssistant(): ChatMessage | null {
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === MessageRole.ASSISTANT) {
        return this.messages[i];
      }
    }
    return null;
  }

  private findById(id: string): ChatMessage | null {
    if (id.length === 0) {
      return null;
    }
    for (const message of this.messages) {
      if (message.id === id) {
        return message;
      }
    }
    return null;
  }

  private buildWireMessages(excludeId: string): WireMessage[] {
    const wires: WireMessage[] = [];
    if (this.systemPrompt.length > 0) {
      wires.push({ role: MessageRole.SYSTEM.toString(), content: this.systemPrompt });
    }
    for (const message of this.messages) {
      // 重试历史回复只使用该回复之前的上下文；后续消息保留在本地。
      if (message.id === excludeId) {
        break;
      }
      if (message.role === MessageRole.SYSTEM) {
        continue;
      }
      if (message.status === MessageStatus.ERROR || message.status === MessageStatus.CANCELLED) {
        continue;
      }
      wires.push(message.toWire());
    }
    const start = this.systemPrompt.length > 0 ? 1 : 0;
    let rounds = 0;
    let characters = 0;
    let keepFrom = wires.length;
    for (let i = wires.length - 1; i >= start; i--) {
      characters += wires[i].content.length;
      if (wires[i].role === MessageRole.USER) {
        if (rounds > 0 && (rounds >= (this.contextPolicy.maxRounds ?? 20) ||
          characters > (this.contextPolicy.maxCharacters ?? 32000))) {
          break;
        }
        rounds += 1;
        keepFrom = i;
      }
    }
    return wires.slice(0, start).concat(wires.slice(keepFrom));
  }

  private requestStream(target: ChatMessage): void {
    this.cancelFlush();
    const requestId = ++this.requestSequence;
    this.activeRequestId = requestId;
    this.activeTargetId = target.id;
    this.pendingDelta = '';
    this.pendingTargetId = target.id;
    this.isGenerating = true;
    const request: ChatRequest = { messages: this.buildWireMessages(target.id) };

    const callbacks: StreamCallbacks = {
      onChunk: (delta: string): void => {
        if (!this.isActive(requestId, target.id)) {
          return;
        }
        if (target.status === MessageStatus.SENDING) {
          target.status = MessageStatus.STREAMING;
        }
        this.pendingDelta += delta;
        const chunkPayload: MessageChunkPayload = { delta };
        this.events.emit(ChatEventType.MESSAGE_CHUNK, this.sessionId, target.id, chunkPayload);
        this.scheduleFlush(target, requestId);
      },
      onComplete: (fullText: string): void => {
        if (!this.isActive(requestId, target.id)) {
          return;
        }
        this.flushFor(target, requestId);
        target.content = fullText;
        this.contentRevision += 1;
        target.status = MessageStatus.DONE;
        target.errorText = '';
        this.persistMessages();
        const receivedPayload: MessageReceivedPayload = { content: fullText };
        this.events.emit(ChatEventType.MESSAGE_RECEIVED, this.sessionId, target.id, receivedPayload);
        this.events.emit(ChatEventType.MESSAGE_COMPLETED, this.sessionId, target.id);
        this.finishRequest(requestId);
      },
      onError: (err: Error): void => {
        if (!this.isActive(requestId, target.id)) {
          return;
        }
        this.flushFor(target, requestId);
        target.status = MessageStatus.ERROR;
        target.errorText = err.message;
        this.persistMessages();
        const errorPayload: ErrorPayload = { message: err.message };
        this.events.emit(ChatEventType.ERROR, this.sessionId, target.id, errorPayload);
        this.finishRequest(requestId);
      },
      onToolCall: (tool: ToolCall): void => {
        if (!this.isActive(requestId, target.id)) {
          return;
        }
        const toolPayload: ToolCallEventPayload = {
          name: tool.name,
          callId: tool.callId,
          arguments: tool.arguments,
          status: tool.status,
          result: tool.result
        };
        this.events.emit(ChatEventType.TOOL_CALL, this.sessionId, target.id, toolPayload);
      }
    };

    let task: ChatTask;
    try {
      task = this.transport.send(request, callbacks);
    } catch (e) {
      // 自定义 Transport 的同步异常也要走统一错误状态机。
      callbacks.onError(new Error('Transport send failed'));
      return;
    }
    if (this.isActive(requestId, target.id)) {
      this.currentTask = task;
    } else {
      // 处理同步完成的 Transport，避免把已完成任务错误地挂到当前状态。
      try {
        task.cancel();
      } catch (e) {
        // 忽略取消异常。
      }
    }
  }

  private scheduleFlush(target: ChatMessage, requestId: number): void {
    if (this.flushTimer !== null) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      if (this.isActive(requestId, target.id)) {
        this.flushFor(target, requestId);
      }
    }, 50);
  }

  private flushFor(target: ChatMessage, requestId: number): void {
    if (this.pendingTargetId !== target.id || this.pendingDelta.length === 0) {
      return;
    }
    if (requestId !== this.activeRequestId && requestId !== 0) {
      return;
    }
    target.content += this.pendingDelta;
    this.pendingDelta = '';
    this.contentRevision += 1;
    // 归属保留到整个请求结束，后续 chunk 仍需写入同一条消息。
    this.schedulePersist();
  }

  private finishRequest(requestId: number): void {
    if (requestId !== this.activeRequestId) {
      return;
    }
    this.cancelFlush();
    this.activeRequestId = 0;
    this.activeTargetId = '';
    this.currentTask = null;
    this.pendingDelta = '';
    this.pendingTargetId = '';
    this.isGenerating = false;
  }

  private isActive(requestId: number, targetId: string): boolean {
    return this.activeRequestId === requestId && this.activeTargetId === targetId && this.isGenerating;
  }

  private cancelFlush(): void {
    if (this.flushTimer !== null) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
  }

  private persistMessages(): void {
    if (this.persistTimer !== null) {
      clearTimeout(this.persistTimer);
      this.persistTimer = null;
    }
    this.sessions.replaceMessages(this.sessionId, this.messages);
  }

  private schedulePersist(): void {
    if (this.persistTimer !== null) {
      return;
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      this.persistMessages();
    }, 500);
  }
}
