/**
 * 会话管理与持久化抽象。
 *
 * core 不依赖具体的 Preferences 或关系型数据库。宿主应用可以实现
 * SessionStore，把快照写入自己的存储；InMemorySessionStore 作为默认实现，
 * 让 Demo 和无持久化场景开箱即用。
 */

import { Attachment, ChatMessage, ChatMessageSnapshot } from '../model/ChatMessage';
import { genId } from '../utils/Id';

export interface ChatSessionSnapshot {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMessageSnapshot[];
}
export interface SessionStore {
  load(): ChatSessionSnapshot[];
  save(session: ChatSessionSnapshot): void;
  remove(sessionId: string): void;
  clear?(): void;
}

/** 宿主可将此接口绑定到 Preferences 或关系型数据库的单键 JSON 适配器。 */
export interface SessionValueStore {
  get(key: string): string | null;
  set(key: string, value: string): void;
  remove(key: string): void;
}

/** 基于宿主字符串存储的完整持久化实现。 */
export class JsonSessionStore implements SessionStore {
  private storage: SessionValueStore;
  private key: string;

  constructor(storage: SessionValueStore, key: string = 'arkgenie.sessions') {
    this.storage = storage;
    this.key = key;
  }

  load(): ChatSessionSnapshot[] {
    const raw = this.storage.get(this.key);
    if (!raw || raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as ChatSessionSnapshot[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  save(session: ChatSessionSnapshot): void {
    const items = this.load();
    let replaced = false;
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === session.id) {
        items[i] = session;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      items.push(session);
    }
    try {
      this.storage.set(this.key, JSON.stringify(items));
    } catch (e) {
      // 非 JSON 元数据不应让对话主链路崩溃。
    }
  }

  remove(sessionId: string): void {
    const items = this.load().filter((item: ChatSessionSnapshot) => item.id !== sessionId);
    try {
      this.storage.set(this.key, JSON.stringify(items));
    } catch (e) {
      // 忽略无法序列化的损坏快照。
    }
  }

  clear(): void {
    this.storage.remove(this.key);
  }
}

/** 最小可用存储实现；应用退出后数据不保留，适合 Demo 和测试。 */
export class InMemorySessionStore implements SessionStore {
  private snapshots: ChatSessionSnapshot[] = [];

  load(): ChatSessionSnapshot[] {
    return InMemorySessionStore.cloneSnapshots(this.snapshots);
  }

  save(session: ChatSessionSnapshot): void {
    const copy = InMemorySessionStore.cloneSnapshot(session);
    for (let i = 0; i < this.snapshots.length; i++) {
      if (this.snapshots[i].id === session.id) {
        this.snapshots[i] = copy;
        return;
      }
    }
    this.snapshots.push(copy);
  }

  remove(sessionId: string): void {
    this.snapshots = this.snapshots.filter((item: ChatSessionSnapshot) => item.id !== sessionId);
  }

  clear(): void {
    this.snapshots = [];
  }

  private static cloneSnapshots(items: ChatSessionSnapshot[]): ChatSessionSnapshot[] {
    const result: ChatSessionSnapshot[] = [];
    for (const item of items) {
      result.push(InMemorySessionStore.cloneSnapshot(item));
    }
    return result;
  }

  private static cloneSnapshot(item: ChatSessionSnapshot): ChatSessionSnapshot {
    const messages: ChatMessageSnapshot[] = [];
    for (const message of item.messages) {
      const attachments: Attachment[] = [];
      for (const attachment of message.attachments) {
        attachments.push({
          kind: attachment.kind,
          uri: attachment.uri,
          name: attachment.name,
          mimeType: attachment.mimeType
        });
      }
      messages.push({
        id: message.id,
        role: message.role,
        content: message.content,
        status: message.status,
        errorText: message.errorText,
        attachments,
          createdAt: message.createdAt,
          contentType: message.contentType,
          metadata: message.metadata
      });
    }
    return {
      id: item.id,
      title: item.title,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      messages
    };
  }
}

@ObservedV2
export class ChatSession {
  readonly id: string;
  @Trace title: string;
  readonly createdAt: number;
  @Trace updatedAt: number;
  @Trace messages: ChatMessage[] = [];

  constructor(id: string, title: string = '新会话', createdAt: number = Date.now(), updatedAt: number = createdAt) {
    this.id = id;
    this.title = title;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
  }

  touch(): void {
    this.updatedAt = Date.now();
  }

  toSnapshot(): ChatSessionSnapshot {
    const messages: ChatMessageSnapshot[] = [];
    for (const message of this.messages) {
      messages.push(message.toSnapshot());
    }
    return {
      id: this.id,
      title: this.title,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
      messages
    };
  }

  static fromSnapshot(snapshot: ChatSessionSnapshot): ChatSession {
    const session = new ChatSession(snapshot.id, snapshot.title, snapshot.createdAt, snapshot.updatedAt);
    const messages: ChatMessage[] = [];
    for (const message of snapshot.messages) {
      messages.push(ChatMessage.fromSnapshot(message));
    }
    session.messages = messages;
    return session;
  }
}

/**
 * 多会话生命周期管理器。所有写操作都会立即调用 SessionStore.save，
 * 因此宿主只需实现 SessionStore 即可获得持久化能力。
 */
@ObservedV2
export class SessionManager {
  @Trace sessions: ChatSession[] = [];
  @Trace currentSessionId: string = '';
  private store: SessionStore;

  constructor(store?: SessionStore) {
    this.store = store ?? new InMemorySessionStore();
    const snapshots = this.store.load();
    for (const snapshot of snapshots) {
      if (snapshot.id && snapshot.id.length > 0) {
        this.sessions.push(ChatSession.fromSnapshot(snapshot));
      }
    }
    if (this.sessions.length > 0) {
      this.currentSessionId = this.sessions[0].id;
    }
  }

  get current(): ChatSession | null {
    if (this.currentSessionId.length === 0) {
      return null;
    }
    return this.find(this.currentSessionId);
  }

  create(title: string = '新会话'): ChatSession {
    const now = Date.now();
    const session = new ChatSession(genId('s'), title.trim().length > 0 ? title.trim() : '新会话', now, now);
    this.sessions.unshift(session);
    this.currentSessionId = session.id;
    this.persist(session);
    return session;
  }

  select(sessionId: string): ChatSession | null {
    const found = this.find(sessionId);
    if (!found) {
      return null;
    }
    this.currentSessionId = found.id;
    return found;
  }

  rename(sessionId: string, title: string): boolean {
    const found = this.find(sessionId);
    if (!found) {
      return false;
    }
    const nextTitle = title.trim();
    if (nextTitle.length === 0) {
      return false;
    }
    found.title = nextTitle;
    found.touch();
    this.persist(found);
    return true;
  }

  delete(sessionId: string): boolean {
    const index = this.sessions.findIndex((item: ChatSession) => item.id === sessionId);
    if (index < 0) {
      return false;
    }
    this.sessions.splice(index, 1);
    this.store.remove(sessionId);
    if (this.currentSessionId === sessionId) {
      this.currentSessionId = this.sessions.length > 0 ? this.sessions[0].id : '';
    }
    return true;
  }

  appendMessage(sessionId: string, message: ChatMessage): boolean {
    const found = this.find(sessionId);
    if (!found) {
      return false;
    }
    found.messages.push(message);
    found.touch();
    this.persist(found);
    return true;
  }

  replaceMessages(sessionId: string, messages: ChatMessage[]): boolean {
    const found = this.find(sessionId);
    if (!found) {
      return false;
    }
    found.messages = messages;
    found.touch();
    this.persist(found);
    return true;
  }

  persistCurrent(): void {
    const current = this.current;
    if (current) {
      this.persist(current);
    }
  }

  private find(sessionId: string): ChatSession | null {
    for (const session of this.sessions) {
      if (session.id === sessionId) {
        return session;
      }
    }
    return null;
  }

  private persist(session: ChatSession): void {
    this.store.save(session.toSnapshot());
  }
}
