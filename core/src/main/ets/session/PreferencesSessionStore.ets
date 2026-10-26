import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ChatSessionSnapshot, InMemorySessionStore, SessionStore } from './SessionManager';

export interface PreferencesStoreError {
  operation: string;
  message: string;
}

export interface PreferencesSessionStoreOptions {
  /** 同一文件在同一进程内共用一个实例；不同账号应使用不同 name。 */
  name?: string;
  /** 合并频繁写入的时间窗口，默认 300ms。 */
  debounceMs?: number;
  onError?: (error: PreferencesStoreError) => void;
}

interface StoredSessions {
  version: number;
  sessions: ChatSessionSnapshot[];
}

interface SnapshotSlot {
  bank: number;
  chunks: number;
  length: number;
  checksum: number;
}

interface SnapshotManifest {
  version: number;
  active: SnapshotSlot;
  previous?: SnapshotSlot;
}

const MANIFEST_KEY: string = 'arkgenie.sessions.manifest';
// 小块写入也适配早期 SDK 的单个字符串长度限制。
const CHUNK_SIZE: number = 2048;
const MAX_CHUNKS: number = 8192;

/**
 * Preferences 持久化：同步内存快照 + 合并异步落盘。
 * 两个分区交替提交，先落盘内容再切换清单；读取损坏的活动分区时尝试前一版。
 * save/remove/clear 返回只表示内存更新成功；await flush() 才表示落盘完成。
 */
export class PreferencesSessionStore implements SessionStore {
  private backend: preferences.Preferences;
  private memory: InMemorySessionStore = new InMemorySessionStore();
  private manifest: SnapshotManifest | null = null;
  private revision: number = 0;
  private savedRevision: number = 0;
  private timer: number | null = null;
  private inFlight: Promise<void> | null = null;
  private debounceMs: number;
  private onError?: (error: PreferencesStoreError) => void;
  lastError: PreferencesStoreError | null = null;

  private constructor(backend: preferences.Preferences, options: PreferencesSessionStoreOptions) {
    this.backend = backend;
    this.debounceMs = options.debounceMs ?? 300;
    this.onError = options.onError;
    if (!Number.isFinite(this.debounceMs) || this.debounceMs < 0) {
      throw new Error('debounceMs must be a finite non-negative number');
    }
    this.restore();
  }

  static async open(context: common.Context,
    options: PreferencesSessionStoreOptions = {}): Promise<PreferencesSessionStore> {
    const backend = await preferences.getPreferences(context, { name: options.name ?? 'arkgenie_sessions' });
    return new PreferencesSessionStore(backend, options);
  }

  load(): ChatSessionSnapshot[] {
    return this.memory.load();
  }

  save(session: ChatSessionSnapshot): void {
    this.memory.save(session);
    this.changed();
  }

  remove(sessionId: string): void {
    this.memory.remove(sessionId);
    this.changed();
  }

  clear(): void {
    this.memory.clear();
    this.changed();
  }

  get hasPendingWrites(): boolean {
    return this.revision !== this.savedRevision;
  }

  /** 合并并串行提交，期间新增的修改也会在返回前落盘；失败可再次调用重试。 */
  async flush(): Promise<void> {
    this.cancelTimer();
    if (this.inFlight !== null) {
      await this.inFlight;
      if (this.hasPendingWrites) {
        await this.flush();
      }
      return;
    }
    const operation = this.drain();
    this.inFlight = operation;
    try {
      await operation;
    } catch (e) {
      this.report('flush', 'Session persistence failed; pending changes remain in memory');
      throw e;
    } finally {
      this.inFlight = null;
    }
  }

  private changed(): void {
    this.revision += 1;
    if (this.timer !== null || this.inFlight !== null) {
      return;
    }
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush().catch(() => {
        // 错误已通过 lastError/onError 暴露，保留脏数据供宿主重试。
      });
    }, this.debounceMs);
  }

  private cancelTimer(): void {
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  private async drain(): Promise<void> {
    while (this.hasPendingWrites) {
      const writingRevision = this.revision;
      const state: StoredSessions = { version: 1, sessions: this.memory.load() };
      const text = JSON.stringify(state);
      const chunks = this.splitChunks(text);
      const count = chunks.length;
      if (count > MAX_CHUNKS) {
        throw new Error('Session snapshot exceeds Preferences capacity; use a database SessionStore');
      }
      const bank = this.manifest === null ? 0 : 1 - this.manifest.active.bank;
      const slot: SnapshotSlot = {
        bank, chunks: count, length: text.length, checksum: this.checksum(text)
      };
      for (let i = 0; i < count; i++) {
        this.backend.putSync(this.chunkKey(bank, i), chunks[i]);
      }
      // 保证清单不会指向尚未完成持久化的分块。
      await this.backend.flush();
      const next: SnapshotManifest = {
        version: 1, active: slot,
        // 清空后的备份不能指向旧会话，避免损坏恢复时复活已删除数据。
        previous: this.manifest === null || state.sessions.length === 0 ? undefined : this.manifest.active
      };
      const previousRaw = this.backend.getSync(MANIFEST_KEY, '');
      try {
        this.backend.putSync(MANIFEST_KEY, JSON.stringify(next));
        await this.backend.flush();
      } catch (e) {
        // 恢复进程内清单缓存，后续 retry 从最后确认成功的版本继续。
        this.backend.putSync(MANIFEST_KEY, previousRaw);
        throw e;
      }
      this.manifest = next;
      this.savedRevision = writingRevision;
      this.lastError = null;
    }
  }

  private restore(): void {
    const raw = this.backend.getSync(MANIFEST_KEY, '');
    if (raw === '') {
      return;
    }
    if (typeof raw !== 'string') {
      throw new Error('Invalid Preferences session manifest');
    }
    const manifest = JSON.parse(raw) as SnapshotManifest;
    if (!manifest || manifest.version !== 1 || !this.validSlot(manifest.active)) {
      throw new Error('Unsupported or invalid Preferences session manifest');
    }
    let state: StoredSessions;
    try {
      state = this.readSlot(manifest.active);
      this.manifest = manifest;
    } catch (e) {
      if (!manifest.previous || !this.validSlot(manifest.previous)) {
        throw e;
      }
      state = this.readSlot(manifest.previous);
      this.manifest = { version: 1, active: manifest.previous };
      this.report('restore', 'Active session snapshot is damaged; restored the previous snapshot');
    }
    for (const session of state.sessions) {
      // 进程退出前的请求不能恢复为正在生成，保留已收到的内容并允许重试。
      for (const message of session.messages) {
        if (message.status === 'sending' || message.status === 'streaming') {
          message.status = 'cancelled';
        }
      }
      this.memory.save(session);
    }
  }

  private readSlot(slot: SnapshotSlot): StoredSessions {
    let text = '';
    for (let i = 0; i < slot.chunks; i++) {
      const chunk = this.backend.getSync(this.chunkKey(slot.bank, i), '');
      if (typeof chunk !== 'string' || chunk.length === 0 || chunk.length > CHUNK_SIZE) {
        throw new Error('Invalid Preferences session chunk');
      }
      text += chunk;
    }
    if (text.length !== slot.length || this.checksum(text) !== slot.checksum) {
      throw new Error('Preferences session snapshot checksum mismatch');
    }
    const state = JSON.parse(text) as StoredSessions;
    if (!state || state.version !== 1 || !Array.isArray(state.sessions)) {
      throw new Error('Unsupported Preferences session snapshot version');
    }
    const ids: string[] = [];
    for (const session of state.sessions) {
      if (!session || typeof session.id !== 'string' || session.id.length === 0 ||
        ids.indexOf(session.id) >= 0 || typeof session.title !== 'string' ||
        !Number.isFinite(session.createdAt) || !Number.isFinite(session.updatedAt) ||
        !Array.isArray(session.messages)) {
        throw new Error('Invalid Preferences session snapshot');
      }
      ids.push(session.id);
      for (const message of session.messages) {
        if (!message || typeof message.id !== 'string' || typeof message.role !== 'string' ||
          typeof message.content !== 'string' || typeof message.status !== 'string' ||
          typeof message.errorText !== 'string' || !Number.isFinite(message.createdAt) ||
          !Array.isArray(message.attachments)) {
          throw new Error('Invalid Preferences message snapshot');
        }
        for (const attachment of message.attachments) {
          if (!attachment || typeof attachment.kind !== 'string' ||
            typeof attachment.uri !== 'string' || typeof attachment.name !== 'string') {
            throw new Error('Invalid Preferences attachment snapshot');
          }
        }
      }
    }
    return state;
  }

  private validSlot(slot: SnapshotSlot): boolean {
    return slot !== undefined && slot !== null && (slot.bank === 0 || slot.bank === 1) &&
      Number.isInteger(slot.chunks) && slot.chunks > 0 && slot.chunks <= MAX_CHUNKS &&
      Number.isInteger(slot.length) && slot.length > 0 && slot.length <= slot.chunks * CHUNK_SIZE &&
      Number.isInteger(slot.checksum);
  }

  private chunkKey(bank: number, index: number): string {
    return `arkgenie.sessions.${bank}.${index}`;
  }

  private splitChunks(text: string): string[] {
    const result: string[] = [];
    let start = 0;
    while (start < text.length) {
      let end = Math.min(start + CHUNK_SIZE, text.length);
      const last = text.charCodeAt(end - 1);
      if (end < text.length && last >= 0xD800 && last <= 0xDBFF) {
        end -= 1;
      }
      result.push(text.substring(start, end));
      start = end;
    }
    return result;
  }

  private checksum(text: string): number {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i++) {
      hash = Math.imul(hash ^ text.charCodeAt(i), 16777619);
    }
    return hash >>> 0;
  }

  private report(operation: string, message: string): void {
    const error: PreferencesStoreError = { operation, message };
    this.lastError = error;
    if (this.onError) {
      try {
        this.onError(error);
      } catch (e) {
        // 观察者异常不影响持久化状态。
      }
    }
  }
}
