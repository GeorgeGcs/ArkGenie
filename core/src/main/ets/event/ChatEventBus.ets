/**
 * 对话事件总线：把状态机与埋点、日志、工具调用 UI 解耦。
 * 监听器异常会被隔离，不会阻断消息传输。
 */

export enum ChatEventType {
  MESSAGE_SENT = 'message.sent',
  MESSAGE_CHUNK = 'message.chunk',
  MESSAGE_RECEIVED = 'message.received',
  MESSAGE_COMPLETED = 'message.completed',
  MESSAGE_CANCELLED = 'message.cancelled',
  MESSAGE_RETRY = 'message.retry',
  TOOL_CALL = 'tool.call',
  ERROR = 'error'
}
export interface ChatEvent {
  type: ChatEventType;
  timestamp: number;
  sessionId: string;
  messageId: string;
  /** 事件数据只允许普通 JSON 值，禁止传递函数或可执行代码。 */
  payload?: Object;
}

export interface ToolCallPayload {
  name: string;
  callId?: string;
  arguments?: Object;
  status?: string;
  result?: Object;
}

export type ChatEventListener = (event: ChatEvent) => void;

interface ListenerEntry {
  id: number;
  type: ChatEventType | null;
  listener: ChatEventListener;
}

export interface EventSubscription {
  unsubscribe(): void;
}

class Subscription implements EventSubscription {
  private bus: ChatEventBus;
  private id: number;
  private active: boolean = true;

  constructor(bus: ChatEventBus, id: number) {
    this.bus = bus;
    this.id = id;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.bus.remove(this.id);
  }
}

export class ChatEventBus {
  private listeners: ListenerEntry[] = [];
  private nextId: number = 1;

  subscribe(type: ChatEventType | null, listener: ChatEventListener): EventSubscription {
    const id = this.nextId++;
    this.listeners.push({ id, type, listener });
    return new Subscription(this, id);
  }

  on(type: ChatEventType, listener: ChatEventListener): EventSubscription {
    return this.subscribe(type, listener);
  }

  onAny(listener: ChatEventListener): EventSubscription {
    return this.subscribe(null, listener);
  }

  publish(event: ChatEvent): void {
    // 复制数组后再通知，允许监听器在回调中 unsubscribe。
    const current = this.listeners.slice();
    for (const entry of current) {
      if (entry.type !== null && entry.type !== event.type) {
        continue;
      }
      try {
        entry.listener(event);
      } catch (e) {
        // 单个埋点/观察者故障不应影响对话主链路。
      }
    }
  }

  emit(type: ChatEventType, sessionId: string, messageId: string, payload?: Object): void {
    this.publish({
      type,
      timestamp: Date.now(),
      sessionId,
      messageId,
      payload
    });
  }

  clear(): void {
    this.listeners = [];
  }

  remove(id: number): void {
    this.listeners = this.listeners.filter((entry: ListenerEntry) => entry.id !== id);
  }
}
