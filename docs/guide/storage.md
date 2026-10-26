# Preferences 会话持久化

`SessionManager` 默认使用内存。需要在应用重启后恢复会话时，在 Ability 或宿主服务中初始化 `PreferencesSessionStore`，再把它交给 `SessionManager`。

```ts
import { common } from '@kit.AbilityKit';
import {
  ChatController, MockTransport, PreferencesSessionStore, SessionManager
} from '@arkgenie/core';

interface HostChat {
  store: PreferencesSessionStore;
  controller: ChatController;
}

async function createChat(context: common.Context): Promise<HostChat> {
  const store = await PreferencesSessionStore.open(context, {
    name: 'my_app_chat_sessions',
    debounceMs: 300,
    onError: (error) => {
      // 回调不包含会话内容。可在宿主 UI 中显示存储失败提示。
      console.error(`Session storage ${error.operation}: ${error.message}`);
    }
  });
  const controller = new ChatController(new MockTransport(), '', new SessionManager(store));
  return { store, controller };
}

// 宿主保留 createChat(context) 返回的 runtime。
// 后台切换时：runtime.controller.stop(); await runtime.store.flush();
```

## 保存语义与生命周期

- `save()`、`remove()`、`clear()` 同步更新内存，默认在 300ms 窗口中合并落盘。持续流式更新也会按窗口提交。
- `await store.flush()` 等待待写数据提交；并发调用会串行合并，期间新增的修改也会被处理。
- 应用转到后台时，先 `controller.stop()` 保留缓冲尾部，再调用 `store.flush()`。若存储中仍有上次中断的 `sending/streaming` 消息，重启恢复时会改为 `cancelled`，保留部分文本以供重试。
- `flush()` 失败会 reject，并保留脏数据；可检查 `hasPendingWrites`、`lastError` 或订阅 `onError` 后显式重试。初始化失败由 `open()` reject 交给宿主处理，不会自动覆盖损坏数据。
- 强制杀进程可能来不及执行生命周期回调；刚收到且尚未提交的内容仍可能丢失。

`entry` 示例已在 `DemoRuntime` 中实现初始化，在 `EntryAbility.onBackground/onDestroy` 中发起保存。页面仅获取已初始化的 Controller，没有增加存储操作控件。初始化失败时示例会明确输出错误，并让本次运行使用内存会话。

## 分块、恢复与使用边界

快照使用版本为 `1` 的内部格式。长文本分成不超过 2048 个 UTF-16 单元的字符串，两个分区交替写入；内容 flush 成功后再切换清单。清单保存长度与校验值，活动快照损坏时尝试恢复前一次已提交快照，并通过 `onError` 报告恢复。若清单损坏、版本不支持或两个快照都不可用，初始化失败。

前一次快照是恢复备份，可能包含较早的内容。`clear()` 提交空快照后不再以旧历史作为恢复备份；这不是安全擦除磁盘数据的接口。

每个 Preferences 文件在同一进程内共用一个 Store 实例；不同账号使用不同 `name`。本适配器面向少量本地会话，不提供跨进程并发、加密、当前选中会话持久化或大规模历史分页。大量历史数据应实现基于关系型数据库的 `SessionStore`。已有 `JsonSessionStore` 自定义存储不会自动迁移到新格式。

平台 API 参考：[用户首选项](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-data-preferences)。
