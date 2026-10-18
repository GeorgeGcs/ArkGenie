import {
  A2uiAction,
  A2uiActionType,
  A2uiComponentNode,
  A2uiMessage,
  A2uiSurface,
  A2uiSurfaceStore,
  ComponentCatalog,
  A2uiParser
} from './model/A2uiMessage';

/**
 * A2UI Surface 控制器：接收协议消息、校验并维护当前 Surface。
 * 宿主应用可以把 emitAction 连接到自己的 Agent 传输层。
 */
@ObservedV2
export class A2uiRendererController {
  @Trace version: number = 0;
  readonly catalog: ComponentCatalog;
  private store: A2uiSurfaceStore;
  private actionListener: (action: A2uiAction) => void = () => {
  };

  constructor(catalog: ComponentCatalog = new ComponentCatalog()) {
    this.catalog = catalog;
    this.store = new A2uiSurfaceStore(catalog);
  }

  setActionListener(listener: (action: A2uiAction) => void): void {
    this.actionListener = listener;
  }

  apply(message: A2uiMessage): string[] {
    const result = this.store.apply(message);
    this.version += 1;
    return result.errors;
  }

  applyJson(json: string): string[] {
    try {
      const messages = A2uiParser.parse(json);
      const errors: string[] = [];
      for (const message of messages) {
        errors.push(...this.apply(message));
      }
      return errors;
    } catch (e) {
      return [`A2UI parse error: ${e}`];
    }
  }

  surface(surfaceId: string): A2uiSurface | undefined {
    return this.store.get(surfaceId);
  }

  emitAction(action: A2uiAction): void {
    this.actionListener(action);
  }
}

/**
 * 安全的内置组件渲染器。未知类型只显示降级提示，不执行远端代码。
 */
@ComponentV2
export struct A2uiSurfaceView {
  @Require @Param controller: A2uiRendererController;
  @Require @Param surfaceId: string;
  @Param emptyText: string = '暂无生成式内容';

  private currentSurface(): A2uiSurface | undefined {
    // 读取 version 让 ComponentV2 在增量消息到达时重新构建。
    const ignored = this.controller.version;
    return this.controller.surface(this.surfaceId);
  }

  build() {
    if (!this.hasContent()) {
      Column() {
        Text(this.emptyText)
          .fontColor('#8A9199')
          .fontSize(14)
      }
      .width('100%')
      .padding(24)
    } else {
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.rootIds(), (id: string) => {
            this.renderRoot(id);
          }, (id: string) => id)
        }
        .width('100%')
        .padding(12)
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  renderRoot(id: string): void {
    if (this.nodeAt(id) !== undefined && this.currentSurface() !== undefined) {
      this.renderNode(this.nodeAt(id) as A2uiComponentNode, this.currentSurface() as A2uiSurface);
    }
  }

  @Builder
  renderNode(node: A2uiComponentNode, surface: A2uiSurface): void {
    if (node.type === 'text' || node.type === 'markdown') {
      Text(this.textProp(node, 'text', this.textProp(node, 'content', '')))
        .fontSize(this.numberProp(node, 'fontSize', 15))
        .fontColor(this.stringProp(node, 'color', '#182431'))
        .fontWeight(this.boolProp(node, 'bold', false) ? FontWeight.Bold : FontWeight.Normal)
        .width('100%')
    } else if (node.type === 'button') {
      Button(this.textProp(node, 'text', this.textProp(node, 'label', '操作')))
        .enabled(this.boolProp(node, 'enabled', true))
        .onClick(() => this.emitPress(node))
    } else if (node.type === 'buttonGroup') {
      Row({ space: this.numberProp(node, 'gap', 8) }) {
        this.renderChildren(node, surface)
      }
      .width('100%')
    } else if (node.type === 'row') {
      Row({ space: this.numberProp(node, 'gap', 8) }) {
        this.renderChildren(node, surface)
      }
      .width('100%')
    } else if (node.type === 'column' || node.type === 'card' || node.type === 'confirm') {
      Column({ space: 8 }) {
        if (node.type === 'card' || node.type === 'confirm') {
          if (this.textProp(node, 'title', '').length > 0) {
            Text(this.textProp(node, 'title', '')).fontSize(16).fontWeight(FontWeight.Medium)
          }
          if (this.textProp(node, 'subtitle', this.textProp(node, 'message', '')).length > 0) {
            Text(this.textProp(node, 'subtitle', this.textProp(node, 'message', '')))
              .fontSize(13).fontColor('#69727D')
          }
        }
        this.renderChildren(node, surface)
        if (node.type === 'confirm') {
          Row({ space: 8 }) {
            Button(this.textProp(node, 'cancelText', '取消'))
               .onClick(() => this.controller.emitAction({
                type: A2uiActionType.REJECT,
                componentId: node.id,
                name: 'cancel'
              }))
            Button(this.textProp(node, 'confirmText', '确认'))
               .onClick(() => this.controller.emitAction({
                type: A2uiActionType.CONFIRM,
                componentId: node.id,
                name: 'confirm'
              }))
          }
        }
      }
      .width('100%')
      .padding(node.type === 'card' || node.type === 'confirm' ? 14 : 0)
      .backgroundColor(node.type === 'card' || node.type === 'confirm' ? '#F5F7FA' : Color.Transparent)
      .borderRadius(node.type === 'card' || node.type === 'confirm' ? 12 : 0)
    } else if (node.type === 'input') {
      TextInput({
        text: this.textProp(node, 'value', ''),
        placeholder: this.textProp(node, 'placeholder', '')
      })
        .width('100%')
        .onChange((value: string) => this.controller.emitAction({
          type: A2uiActionType.CHANGE,
          componentId: node.id,
          value: value
        }))
    } else if (node.type === 'list') {
      List() {
        ForEach(this.listProp(node, 'items'), (item: string) => {
          ListItem() { Text(item).padding(8) }
        }, (item: string, index: number) => `${node.id}-${index}-${item}`)
      }
      .width('100%')
    } else if (node.type === 'divider') {
      Divider().strokeWidth(1).color('#E4E7ED').width('100%')
    } else if (node.type === 'progress') {
      Progress({ value: this.numberProp(node, 'value', 0), total: 100 })
        .width('100%')
      if (this.textProp(node, 'label', '').length > 0) {
        Text(this.textProp(node, 'label', '')).fontSize(12).fontColor('#69727D')
      }
    } else if (node.type === 'badge') {
      Text(this.textProp(node, 'text', ''))
        .fontSize(12)
        .fontColor('#FFFFFF')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor(this.stringProp(node, 'color', '#0A59F7'))
        .borderRadius(10)
    } else if (node.type === 'image') {
      Image(this.textProp(node, 'src', ''))
        .alt(this.textProp(node, 'alt', ''))
        .width(this.numberProp(node, 'width', 120))
        .height(this.numberProp(node, 'height', 80))
        .objectFit(ImageFit.Contain)
    } else if (node.type === 'spacer') {
      Blank().height(this.numberProp(node, 'height', 8))
    } else if (node.type === 'datePicker') {
      Text(this.textProp(node, 'value', '选择日期'))
        .padding(10)
         .onClick(() => this.controller.emitAction({
          type: A2uiActionType.CHANGE,
          componentId: node.id,
          name: 'date'
        }))
    } else {
      Text(`不支持的组件：${node.type}`)
        .fontSize(12)
        .fontColor('#8A9199')
    }
  }

  @Builder
  renderChildren(node: A2uiComponentNode, surface: A2uiSurface): void {
    ForEach(node.children, (childId: string) => {
      if (surface.components.get(childId) !== undefined) {
        this.renderNode(surface.components.get(childId) as A2uiComponentNode, surface);
      }
    }, (childId: string) => childId)
  }

  private emitPress(node: A2uiComponentNode): void {
    this.controller.emitAction({
      type: A2uiActionType.PRESS,
      componentId: node.id,
      name: this.textProp(node, 'action', node.id)
    });
  }

  private textProp(node: A2uiComponentNode, key: string, fallback: string): string {
    const value = node.props.get(key);
    return value === undefined ? fallback : String(value);
  }

  private stringProp(node: A2uiComponentNode, key: string, fallback: string): string {
    return this.textProp(node, key, fallback);
  }

  private numberProp(node: A2uiComponentNode, key: string, fallback: number): number {
    const value = node.props.get(key);
    if (value === undefined) { return fallback; }
    const parsed = Number(value);
    return Number.isNaN(parsed) ? fallback : parsed;
  }

  private boolProp(node: A2uiComponentNode, key: string, fallback: boolean): boolean {
    const value = node.props.get(key);
    return value === undefined ? fallback : Boolean(value);
  }

  private listProp(node: A2uiComponentNode, key: string): string[] {
    const value = node.props.get(key);
    if (value === undefined || !Array.isArray(value)) { return []; }
    return (value as Object[]).map((item: Object) => String(item));
  }

  private hasContent(): boolean {
    const surface = this.currentSurface();
    return surface !== undefined && surface.rootIds.length > 0;
  }

  private rootIds(): string[] {
    const surface = this.currentSurface();
    return surface === undefined ? [] : surface.rootIds;
  }

  private nodeAt(id: string): A2uiComponentNode | undefined {
    const surface = this.currentSurface();
    return surface === undefined ? undefined : surface.components.get(id);
  }
}
