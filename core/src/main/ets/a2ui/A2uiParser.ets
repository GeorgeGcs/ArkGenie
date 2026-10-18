/**
 * A2UI 声明式消息解析与 schema 校验。
 *
 * 解析器只产生普通数据对象，绝不执行远端传入的代码。组件类型默认采用
 * 内置白名单；宿主可以传入自己的白名单与操作数量上限，再交给 genui
 * 的 ComponentCatalog 做最终渲染映射。
 */

export enum A2uiOperationType {
  SURFACE_CREATE = 'surface.create',
  COMPONENT_UPSERT = 'component.upsert',
  DATA_UPDATE = 'data.update'
}
export interface A2uiComponent {
  id: string;
  type: string;
  props: Record<string, Object>;
}

export interface A2uiOperation {
  type: A2uiOperationType;
  surfaceId: string;
  rootComponentId?: string;
  component?: A2uiComponent;
  path?: string;
  value?: Object;
}

export interface A2uiDocument {
  version: string;
  operations: A2uiOperation[];
}

export interface A2uiParserOptions {
  allowedComponents?: string[];
  maxOperations?: number;
  requireVersion?: boolean;
}

export interface A2uiParseResult {
  ok: boolean;
  document: A2uiDocument | null;
  errors: string[];
}

const DEFAULT_COMPONENTS: string[] = [
  'Text', 'Markdown', 'Button', 'ButtonGroup', 'Card', 'Column', 'Row',
  'List', 'Image', 'TextField', 'DatePicker', 'Chart', 'Form', 'Divider',
  'text', 'markdown', 'button', 'buttonGroup', 'card', 'column', 'row',
  'input', 'list', 'image', 'datePicker', 'progress', 'badge', 'confirm', 'spacer'
];

export class A2uiParser {
  static parse(input: string | Object, options?: A2uiParserOptions): A2uiParseResult {
    const errors: string[] = [];
    const config = options ?? {};
    let root: Record<string, Object> | null = null;

    if (typeof input === 'string') {
      try {
        root = A2uiParser.toObject(JSON.parse(input));
      } catch (e) {
        errors.push('A2UI payload 不是有效 JSON');
      }
    } else {
      root = A2uiParser.toObject(input);
    }

    if (!root) {
      errors.push('A2UI payload 必须是 JSON 对象');
      return { ok: false, document: null, errors };
    }

    const version = A2uiParser.stringValue(root, 'version') ?? '0.1';
    if (config.requireVersion === true && !A2uiParser.stringValue(root, 'version')) {
      errors.push('缺少 version 字段');
    }
    if (version.length === 0) {
      errors.push('version 不能为空');
    }

    let rawOperations: Object[] = [];
    const operationsValue = root['operations'] ?? root['messages'];
    if (A2uiParser.isArray(operationsValue)) {
      rawOperations = operationsValue as Object[];
    } else if (root['op'] !== undefined || root['type'] !== undefined) {
      // 允许流式传输时每个 SSE data 事件只携带一个操作。
      rawOperations = [root as Object];
    } else {
      errors.push('缺少 operations 数组');
    }

    const maxOperations = config.maxOperations ?? 100;
    if (rawOperations.length > maxOperations) {
      errors.push(`operations 数量超过上限 ${maxOperations}`);
    }

    const allowed = config.allowedComponents ?? DEFAULT_COMPONENTS;
    const parsed: A2uiOperation[] = [];
    const count = Math.min(rawOperations.length, maxOperations);
    for (let i = 0; i < count; i++) {
      const operation = A2uiParser.parseOperation(rawOperations[i], allowed, i, errors);
      if (operation) {
        parsed.push(operation);
      }
    }

    if (errors.length > 0) {
      return { ok: false, document: null, errors };
    }
    return {
      ok: true,
      document: { version, operations: parsed },
      errors: []
    };
  }

  private static parseOperation(raw: Object, allowed: string[], index: number, errors: string[]): A2uiOperation | null {
    const object = A2uiParser.toObject(raw);
    if (!object) {
      errors.push(`operations[${index}] 必须是对象`);
      return null;
    }
    const typeValue = A2uiParser.stringValue(object, 'op') ?? A2uiParser.stringValue(object, 'type');
    if (typeValue !== A2uiOperationType.SURFACE_CREATE &&
      typeValue !== A2uiOperationType.COMPONENT_UPSERT &&
      typeValue !== A2uiOperationType.DATA_UPDATE) {
      errors.push(`operations[${index}] 的 op 不受支持`);
      return null;
    }
    const surfaceId = A2uiParser.stringValue(object, 'surfaceId');
    if (!surfaceId || surfaceId.length === 0) {
      errors.push(`operations[${index}] 缺少 surfaceId`);
      return null;
    }

    if (typeValue === A2uiOperationType.SURFACE_CREATE) {
      const rootId = A2uiParser.stringValue(object, 'root') ?? A2uiParser.stringValue(object, 'rootComponentId');
      const result: A2uiOperation = { type: A2uiOperationType.SURFACE_CREATE, surfaceId };
      if (rootId) {
        result.rootComponentId = rootId;
      }
      return result;
    }

    if (typeValue === A2uiOperationType.COMPONENT_UPSERT) {
      const rawComponent = A2uiParser.toObject(object['component']) ?? object;
      const componentId = A2uiParser.stringValue(rawComponent, 'id') ??
        A2uiParser.stringValue(object, 'componentId');
      const componentType = A2uiParser.stringValue(rawComponent, 'componentType') ??
        A2uiParser.stringValue(rawComponent, 'type');
      if (!componentId || componentId.length === 0) {
        errors.push(`operations[${index}] 缺少 component.id`);
        return null;
      }
      if (!componentType || componentType.length === 0) {
        errors.push(`operations[${index}] 缺少 component.type`);
        return null;
      }
      if (!A2uiParser.contains(allowed, componentType)) {
        errors.push(`组件 ${componentType} 不在允许目录中`);
        return null;
      }
      const props = A2uiParser.toObject(rawComponent['props']) ?? {};
      const propsError = A2uiParser.validateValue(props, 'props', 0);
      if (propsError) {
        errors.push(`operations[${index}] ${propsError}`);
        return null;
      }
      return {
        type: A2uiOperationType.COMPONENT_UPSERT,
        surfaceId,
        component: { id: componentId, type: componentType, props }
      };
    }

    const path = A2uiParser.stringValue(object, 'path');
    if (!path || path.length === 0) {
      errors.push(`operations[${index}] 缺少 data.update path`);
      return null;
    }
    const value = object['value'];
    const valueError = A2uiParser.validateValue(value, 'value', 0);
    if (valueError) {
      errors.push(`operations[${index}] ${valueError}`);
      return null;
    }
    return { type: A2uiOperationType.DATA_UPDATE, surfaceId, path, value };
  }

  private static toObject(value: Object): Record<string, Object> | null {
    if (value === null || typeof value !== 'object' || A2uiParser.isArray(value)) {
      return null;
    }
    return value as Record<string, Object>;
  }

  private static stringValue(object: Record<string, Object>, key: string): string | null {
    const value = object[key];
    return typeof value === 'string' ? value : null;
  }

  private static isArray(value: Object): boolean {
    return Array.isArray(value);
  }

  private static contains(items: string[], value: string): boolean {
    for (const item of items) {
      if (item === value) {
        return true;
      }
    }
    return false;
  }

  private static validateValue(value: Object, path: string, depth: number): string | null {
    if (value === null || value === undefined) {
      return null;
    }
    if (depth > 8) {
      return `${path} 嵌套层级过深`;
    }
    const kind = typeof value;
    if (kind === 'string' || kind === 'number' || kind === 'boolean') {
      return null;
    }
    if (kind === 'function') {
      return `${path} 不允许函数值`;
    }
    if (A2uiParser.isArray(value)) {
      const arrayValue = value as Object[];
      for (let i = 0; i < arrayValue.length; i++) {
        const error = A2uiParser.validateValue(arrayValue[i], `${path}[${i}]`, depth + 1);
        if (error) {
          return error;
        }
      }
      return null;
    }
    const object = A2uiParser.toObject(value);
    if (!object) {
      return `${path} 必须是 JSON 值`;
    }
    for (const key of Object.keys(object)) {
      // 事件处理器、脚本和函数属性会绕过 Catalog 白名单，全部拒绝。
      if (key === 'code' || key === 'script' || key === 'handler' || key.startsWith('on')) {
        return `${path}.${key} 不允许可执行属性`;
      }
      const error = A2uiParser.validateValue(object[key], `${path}.${key}`, depth + 1);
      if (error) {
        return error;
      }
    }
    return null;
  }
}
