# A2UI 安全模型

ArkGenie 只接受声明式组件数据。`ComponentCatalog` 维护允许的组件类型和属性白名单；未知类型、未知属性和结构错误会在渲染前被拒绝。

```ts
const controller = new A2uiRendererController()
controller.applyJson(JSON.stringify([
  { op: 'createSurface', surfaceId: 'main' },
  {
    op: 'upsertComponent',
    surfaceId: 'main',
    component: { id: 'hello', type: 'text', props: { text: 'Hello' }, children: [] }
  }
]))
```

宿主通过 `setActionListener` 接收按钮、输入和确认操作，并将其转换为自己的 Agent 请求。
