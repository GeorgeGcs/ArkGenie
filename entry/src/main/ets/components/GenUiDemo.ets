import {
  A2uiComponentNode,
  A2uiMessage,
  A2uiOp,
  A2uiProps,
  A2uiRendererController,
  A2uiSurfaceView
} from '@arkgenie/genui';

/**
 * Demo 中的 A2UI 预览：用本地声明式消息生成一张卡片，展示 GenUI
 * 不依赖远端脚本即可渲染并回传交互事件。
 */
@ComponentV2
export struct GenUiDemo {
  private controller: A2uiRendererController = new A2uiRendererController();
  private readonly surfaceId: string = 'demo-surface';

  aboutToAppear(): void {
    const cardProps: A2uiProps = new A2uiProps();
    cardProps.set('title', 'A2UI 生成式 UI');
    cardProps.set('subtitle', '组件来自白名单目录');
    const card: A2uiComponentNode = {
      id: 'card',
      type: 'card',
      props: cardProps,
      children: ['body', 'action']
    };
    const bodyProps: A2uiProps = new A2uiProps();
    bodyProps.set('text', 'Agent 只描述界面数据，客户端安全渲染。');
    const body: A2uiComponentNode = {
      id: 'body',
      type: 'text',
      props: bodyProps,
      children: []
    };
    const actionProps: A2uiProps = new A2uiProps();
    actionProps.set('text', '发送交互事件');
    actionProps.set('action', 'demo.confirm');
    const action: A2uiComponentNode = {
      id: 'action',
      type: 'button',
      props: actionProps,
      children: []
    };
    const messages: A2uiMessage[] = [
      { op: A2uiOp.CREATE_SURFACE, surfaceId: this.surfaceId },
      { op: A2uiOp.UPSERT_COMPONENT, surfaceId: this.surfaceId, component: card },
      { op: A2uiOp.UPSERT_COMPONENT, surfaceId: this.surfaceId, component: body },
      { op: A2uiOp.UPSERT_COMPONENT, surfaceId: this.surfaceId, component: action }
    ];
    for (const message of messages) {
      this.controller.apply(message);
    }
    this.controller.setActionListener((action) => {
      console.info(`ArkGenie A2UI action: ${action.type}/${action.name ?? ''}`);
    });
  }

  build() {
    Column() {
      Text('生成式 UI 预览')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .margin({ left: 12, top: 8, bottom: 2 })
      A2uiSurfaceView({
        controller: this.controller,
        surfaceId: this.surfaceId
      })
        .height(170)
    }
    .width('100%')
  }
}
