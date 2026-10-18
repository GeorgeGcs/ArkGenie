/**
 * A2UI 协议模型、解析与安全校验。
 *
 * 远端只能传递声明式数据，客户端只渲染预批准的组件类型，永远不会
 * eval 或执行远端脚本。解析器与渲染器之间使用同一份 Catalog 白名单。
 */

export enum A2uiOp {
  CREATE_SURFACE = 'createSurface',
  UPSERT_COMPONENT = 'upsertComponent',
  UPDATE_DATA = 'updateData',
  REMOVE_COMPONENT = 'removeComponent',
  REMOVE_SURFACE = 'removeSurface'
}

export enum A2uiActionType {
  PRESS = 'press',
  CHANGE = 'change',
  SUBMIT = 'submit',
  CONFIRM = 'confirm',
  REJECT = 'reject'
}

export class A2uiProps {
  private values: Map<string, Object> = new Map();

  set(key: string, value: Object): void {
    this.values.set(key, value);
  }

  get(key: string): Object | undefined {
    return this.values.get(key);
  }

  keys(): string[] {
    const result: string[] = [];
    for (const key of this.values.keys()) {
      result.push(key);
    }
    return result;
  }

  static fromObject(value: Object): A2uiProps {
    const result = new A2uiProps();
    const raw = value as Record<string, Object>;
    for (const key of Object.keys(raw)) {
      result.set(key, raw[key]);
    }
    return result;
  }
}

export interface A2uiComponentNode {
  id: string;
  type: string;
  props: A2uiProps;
  children: string[];
}

export interface A2uiAction {
  type: A2uiActionType | string;
  componentId: string;
  name?: string;
  value?: Object;
}

export interface A2uiMessage {
  version?: string;
  op: A2uiOp;
  surfaceId: string;
  component?: A2uiComponentNode;
  componentId?: string;
  data?: Record<string, Object>;
  action?: A2uiAction;
}

export interface A2uiSurface {
  id: string;
  rootIds: string[];
  components: Map<string, A2uiComponentNode>;
  data: Record<string, Object>;
}

export interface A2uiValidationResult {
  valid: boolean;
  errors: string[];
}

export class A2uiComponentBuilder {
}

/** 组件目录：白名单、扩展注册和属性级校验规则。 */
export class ComponentCatalog {
  private builders: Map<string, A2uiComponentBuilder> = new Map();
  private propRules: Map<string, string[]> = new Map();

  constructor() {
    const builtins: string[] = [
      'text', 'markdown', 'button', 'buttonGroup', 'card', 'column', 'row',
      'input', 'list', 'divider', 'progress', 'badge', 'image', 'spacer',
      'datePicker', 'confirm'
    ];
    for (const type of builtins) {
      this.builders.set(type, new A2uiComponentBuilder());
    }
    this.propRules.set('text', ['text', 'content', 'color', 'fontSize', 'bold']);
    this.propRules.set('markdown', ['text', 'content']);
    this.propRules.set('button', ['text', 'label', 'action', 'variant', 'enabled']);
    this.propRules.set('buttonGroup', ['direction', 'gap']);
    this.propRules.set('card', ['title', 'subtitle', 'elevated']);
    this.propRules.set('input', ['placeholder', 'value', 'multiline', 'label']);
    this.propRules.set('list', ['items', 'emptyText']);
    this.propRules.set('progress', ['value', 'label']);
    this.propRules.set('badge', ['text', 'color']);
    this.propRules.set('image', ['src', 'alt', 'width', 'height']);
    this.propRules.set('datePicker', ['value', 'min', 'max']);
    this.propRules.set('confirm', ['title', 'message', 'confirmText', 'cancelText']);
  }

  register(type: string, builder: A2uiComponentBuilder, allowedProps: string[] = []): void {
    if (type.trim().length === 0) {
      throw new Error('A2UI component type cannot be empty');
    }
    this.builders.set(type, builder);
    if (allowedProps.length > 0) {
      this.propRules.set(type, allowedProps);
    }
  }

  unregister(type: string): void {
    if (!this.isBuiltin(type)) {
      this.builders.delete(type);
      this.propRules.delete(type);
    }
  }

  has(type: string): boolean {
    return this.builders.has(type);
  }

  getBuilder(type: string): A2uiComponentBuilder | undefined {
    return this.builders.get(type);
  }

  isBuiltin(type: string): boolean {
    return ['text', 'markdown', 'button', 'buttonGroup', 'card', 'column', 'row',
      'input', 'list', 'divider', 'progress', 'badge', 'image', 'spacer',
      'datePicker', 'confirm'].indexOf(type) >= 0;
  }

  allowedProps(type: string): string[] {
    return this.propRules.get(type) ?? [];
  }
}

/** 严格 JSON 解析；任何结构错误都以可读错误返回给调用方。 */
export class A2uiParser {
  static parse(input: string): A2uiMessage[] {
    let value: Object;
    try {
      value = JSON.parse(input) as Object;
    } catch (e) {
      throw new Error(`Invalid A2UI JSON: ${e}`);
    }
    return A2uiParser.parseValue(value);
  }

  static parseValue(value: Object): A2uiMessage[] {
    const raw: Object[] = Array.isArray(value) ? value as Object[] : [value];
    const result: A2uiMessage[] = [];
    for (const item of raw) {
      result.push(A2uiParser.toMessage(item));
    }
    return result;
  }

  private static toMessage(value: Object): A2uiMessage {
    const item = value as Record<string, Object>;
    const op = String(item['op'] ?? '');
    const surfaceId = String(item['surfaceId'] ?? '');
    if (surfaceId.length === 0 || op.length === 0) {
      throw new Error('A2UI message requires op and surfaceId');
    }
    const message: A2uiMessage = {
      version: item['version'] === undefined ? undefined : String(item['version']),
      op: op as A2uiOp,
      surfaceId: surfaceId
    };
    if (item['component'] !== undefined) {
      message.component = A2uiParser.toComponent(item['component'] as Object);
    }
    if (item['componentId'] !== undefined) {
      message.componentId = String(item['componentId']);
    }
    if (item['data'] !== undefined) {
      message.data = item['data'] as Record<string, Object>;
    }
    if (item['action'] !== undefined) {
      message.action = item['action'] as A2uiAction;
    }
    return message;
  }

  private static toComponent(value: Object): A2uiComponentNode {
    const item = value as Record<string, Object>;
    const id = String(item['id'] ?? '');
    const type = String(item['type'] ?? '');
    if (id.length === 0 || type.length === 0) {
      throw new Error('A2UI component requires id and type');
    }
    const rawChildren = item['children'];
    const children: string[] = rawChildren === undefined ? [] : (rawChildren as Object[]).map((v: Object) => String(v));
    let props: A2uiProps;
    if (item['props'] === undefined) {
      props = new A2uiProps();
    } else {
      props = A2uiProps.fromObject(item['props'] as Object);
    }
    return { id, type, props, children };
  }
}

export class A2uiValidator {
  static validate(message: A2uiMessage, catalog: ComponentCatalog): A2uiValidationResult {
    const errors: string[] = [];
    if (message.surfaceId.trim().length === 0) {
      errors.push('surfaceId is required');
    }
    const operations: A2uiOp[] = [A2uiOp.CREATE_SURFACE, A2uiOp.UPSERT_COMPONENT,
      A2uiOp.UPDATE_DATA, A2uiOp.REMOVE_COMPONENT, A2uiOp.REMOVE_SURFACE];
    if (operations.indexOf(message.op) < 0) {
      errors.push(`unsupported operation: ${message.op}`);
    }
    if (message.op === A2uiOp.UPSERT_COMPONENT) {
      if (!message.component) {
        errors.push('upsertComponent requires component');
      } else {
        A2uiValidator.validateComponent(message.component, catalog, errors);
      }
    }
    if (message.op === A2uiOp.REMOVE_COMPONENT && (!message.componentId || message.componentId.length === 0)) {
      errors.push('removeComponent requires componentId');
    }
    return { valid: errors.length === 0, errors };
  }

  private static validateComponent(component: A2uiComponentNode, catalog: ComponentCatalog, errors: string[]): void {
    if (component.id.trim().length === 0) {
      errors.push('component id is required');
    }
    if (!catalog.has(component.type)) {
      errors.push(`component type is not allowed: ${component.type}`);
      return;
    }
    const allowed = catalog.allowedProps(component.type);
    if (allowed.length > 0) {
      for (const key of component.props.keys()) {
        if (allowed.indexOf(key) < 0) {
          errors.push(`property ${key} is not allowed on ${component.type}`);
        }
      }
    }
    for (const child of component.children) {
      if (child.trim().length === 0) {
        errors.push(`component ${component.id} contains an empty child id`);
      }
    }
  }
}

/** Surface 状态容器，用于把增量 A2UI 操作应用成可渲染的状态。 */
export class A2uiSurfaceStore {
  private surfaces: Map<string, A2uiSurface> = new Map();
  private catalog: ComponentCatalog;

  constructor(catalog: ComponentCatalog = new ComponentCatalog()) {
    this.catalog = catalog;
  }

  apply(message: A2uiMessage): A2uiValidationResult {
    const validation = A2uiValidator.validate(message, this.catalog);
    if (!validation.valid) {
      return validation;
    }
    if (message.op === A2uiOp.CREATE_SURFACE) {
      this.surfaces.set(message.surfaceId, {
        id: message.surfaceId,
        rootIds: [],
        components: new Map(),
        data: message.data ?? {}
      });
      return validation;
    }
    if (message.op === A2uiOp.REMOVE_SURFACE) {
      this.surfaces.delete(message.surfaceId);
      return validation;
    }
    const surface = this.surfaces.get(message.surfaceId) ?? {
      id: message.surfaceId,
      rootIds: [],
      components: new Map(),
      data: {}
    };
    this.surfaces.set(message.surfaceId, surface);
    if (message.op === A2uiOp.UPSERT_COMPONENT && message.component) {
      surface.components.set(message.component.id, message.component);
      this.recomputeRoots(surface);
    } else if (message.op === A2uiOp.REMOVE_COMPONENT && message.componentId) {
      surface.components.delete(message.componentId);
      this.recomputeRoots(surface);
    } else if (message.op === A2uiOp.UPDATE_DATA && message.data) {
      const data: Record<string, Object> = surface.data;
      for (const key of Object.keys(message.data)) {
        data[key] = message.data[key];
      }
    }
    return validation;
  }

  applyJson(input: string): A2uiValidationResult[] {
    try {
      const messages = A2uiParser.parse(input);
      return messages.map((message: A2uiMessage) => this.apply(message));
    } catch (e) {
      return [{ valid: false, errors: [`A2UI parse error: ${e}`] }];
    }
  }

  get(surfaceId: string): A2uiSurface | undefined {
    return this.surfaces.get(surfaceId);
  }

  all(): A2uiSurface[] {
    const result: A2uiSurface[] = [];
    for (const surface of this.surfaces.values()) {
      result.push(surface);
    }
    return result;
  }

  private recomputeRoots(surface: A2uiSurface): void {
    const childIds: string[] = [];
    for (const component of surface.components.values()) {
      for (const childId of component.children) {
        if (childIds.indexOf(childId) < 0) {
          childIds.push(childId);
        }
      }
    }
    surface.rootIds = [];
    for (const id of surface.components.keys()) {
      if (childIds.indexOf(id) < 0) {
        surface.rootIds.push(id);
      }
    }
  }
}
