/**
 * 消息模型：角色、状态与内容定义。
 * 状态机：idle → sending → streaming → done / error / cancelled
 */

export enum MessageRole {
  USER = 'user',
  ASSISTANT = 'assistant',
  SYSTEM = 'system'
}

export enum MessageStatus {
  IDLE = 'idle',
  SENDING = 'sending',
  STREAMING = 'streaming',
  DONE = 'done',
  ERROR = 'error',
  CANCELLED = 'cancelled'
}

/** 消息内容类型，覆盖文本、媒体、卡片和 Agent 工具消息。 */
export enum MessageContentType {
  TEXT = 'text',
  IMAGE = 'image',
  FILE = 'file',
  AUDIO = 'audio',
  CARD = 'card',
  TOOL = 'tool',
  ERROR = 'error'
}

/** 附件（图片/文件等），M1 仅记录元数据 */
export interface Attachment {
  kind: string;
  uri: string;
  name: string;
  mimeType?: string;
}

/**
 * 可安全落盘/跨进程传输的消息快照。
 *
 * 快照只包含数据，不携带任何函数或远端代码，因此可以交给宿主应用
 * 的 Preferences/关系型数据库适配器实现持久化。
 */
export interface ChatMessageSnapshot {
  id: string;
  role: string;
  content: string;
  status: string;
  errorText: string;
  attachments: Attachment[];
  createdAt: number;
  contentType?: string;
  metadata?: Record<string, Object>;
}

/** 网络传输层使用的精简消息结构 */
export interface WireMessage {
  role: string;
  content: string;
  attachments?: Attachment[];
}

@ObservedV2
export class ChatMessage {
  readonly id: string;
  readonly role: MessageRole;
  @Trace content: string = '';
  @Trace status: MessageStatus = MessageStatus.IDLE;
  @Trace errorText: string = '';
  @Trace attachments: Attachment[] = [];
  @Trace contentType: MessageContentType = MessageContentType.TEXT;
  @Trace metadata: Record<string, Object> = {};
  readonly createdAt: number;

  constructor(id: string, role: MessageRole, content: string = '', createdAt: number = Date.now()) {
    this.id = id;
    this.role = role;
    this.content = content;
    this.createdAt = createdAt;
  }

  get isUser(): boolean {
    return this.role === MessageRole.USER;
  }

  get isStreaming(): boolean {
    return this.status === MessageStatus.STREAMING || this.status === MessageStatus.SENDING;
  }

  toWire(): WireMessage {
    const wire: WireMessage = {
      role: this.role.toString(),
      content: this.content,
      attachments: this.attachments.length > 0 ? this.attachments : undefined
    };
    return wire;
  }

  /** 将消息转换为不含运行时状态的持久化快照。 */
  toSnapshot(): ChatMessageSnapshot {
    const attachments: Attachment[] = [];
    for (const item of this.attachments) {
      attachments.push({
        kind: item.kind,
        uri: item.uri,
        name: item.name,
        mimeType: item.mimeType
      });
    }
    return {
      id: this.id,
      role: this.role.toString(),
      content: this.content,
      status: this.status.toString(),
      errorText: this.errorText,
      attachments,
      createdAt: this.createdAt,
      contentType: this.contentType.toString(),
      metadata: this.metadata
    };
  }

  /** 从持久化快照恢复消息；未知枚举值会降级为安全的默认值。 */
  static fromSnapshot(snapshot: ChatMessageSnapshot): ChatMessage {
    const role = ChatMessage.parseRole(snapshot.role);
    const message = new ChatMessage(snapshot.id, role, snapshot.content, snapshot.createdAt);
    message.status = ChatMessage.parseStatus(snapshot.status);
    message.errorText = snapshot.errorText;
    message.attachments = snapshot.attachments ?? [];
    message.contentType = ChatMessage.parseContentType(snapshot.contentType);
    message.metadata = snapshot.metadata ?? {};
    return message;
  }

  private static parseRole(value: string): MessageRole {
    if (value === MessageRole.USER) {
      return MessageRole.USER;
    }
    if (value === MessageRole.SYSTEM) {
      return MessageRole.SYSTEM;
    }
    return MessageRole.ASSISTANT;
  }

  private static parseStatus(value: string): MessageStatus {
    if (value === MessageStatus.SENDING) {
      return MessageStatus.SENDING;
    }
    if (value === MessageStatus.STREAMING) {
      return MessageStatus.STREAMING;
    }
    if (value === MessageStatus.ERROR) {
      return MessageStatus.ERROR;
    }
    if (value === MessageStatus.CANCELLED) {
      return MessageStatus.CANCELLED;
    }
    if (value === MessageStatus.DONE) {
      return MessageStatus.DONE;
    }
    return MessageStatus.IDLE;
  }

  private static parseContentType(value?: string): MessageContentType {
    if (value === MessageContentType.IMAGE) { return MessageContentType.IMAGE; }
    if (value === MessageContentType.FILE) { return MessageContentType.FILE; }
    if (value === MessageContentType.AUDIO) { return MessageContentType.AUDIO; }
    if (value === MessageContentType.CARD) { return MessageContentType.CARD; }
    if (value === MessageContentType.TOOL) { return MessageContentType.TOOL; }
    if (value === MessageContentType.ERROR) { return MessageContentType.ERROR; }
    return MessageContentType.TEXT;
  }
}
