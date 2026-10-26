import { common } from '@kit.AbilityKit';
import { ChatController, PreferencesSessionStore, SessionManager } from '@arkgenie/core';
import { DemoConfig } from './DemoConfig';

/** 示例的宿主集成点；页面只负责展示，存储由 Ability 生命周期管理。 */
export class DemoRuntime {
  private static store: PreferencesSessionStore | null = null;
  private static controller: ChatController | null = null;
  private static initialization: Promise<void> | null = null;

  static async initialize(context: common.Context): Promise<void> {
    if (DemoRuntime.initialization === null) {
      DemoRuntime.initialization = DemoRuntime.open(context);
    }
    await DemoRuntime.initialization;
  }

  static getController(): ChatController {
    if (DemoRuntime.controller === null) {
      throw new Error('DemoRuntime must be initialized before loading the page');
    }
    return DemoRuntime.controller;
  }

  static async flush(): Promise<void> {
    if (DemoRuntime.initialization !== null) {
      await DemoRuntime.initialization;
    }
    if (DemoRuntime.controller !== null) {
      DemoRuntime.controller.stop();
      DemoRuntime.controller.sessionManager.persistCurrent();
    }
    if (DemoRuntime.store !== null) {
      await DemoRuntime.store.flush();
    }
  }

  private static async open(context: common.Context): Promise<void> {
    let sessions: SessionManager;
    try {
      DemoRuntime.store = await PreferencesSessionStore.open(context, {
        name: 'arkgenie_demo_sessions',
        onError: (error) => {
          console.error(`ArkGenie storage ${error.operation}: ${error.message}`);
        }
      });
      sessions = new SessionManager(DemoRuntime.store);
    } catch (e) {
      // 初始化失败时保留原文件，仅让本次示例以临时内存会话运行。
      DemoRuntime.store = null;
      sessions = new SessionManager();
      console.error('ArkGenie Preferences unavailable; this run uses an in-memory session.');
    }
    DemoRuntime.controller = new ChatController(DemoConfig.createTransport(),
      '你是一个简洁友善的鸿蒙应用内 AI 助手。', sessions);
  }
}
