import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { DemoRuntime } from '../config/DemoRuntime';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    DemoRuntime.initialize(this.context).then(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          console.error('ArkGenie demo page could not be loaded.');
        }
      });
    }).catch(() => {
      console.error('ArkGenie demo initialization failed.');
    });
  }

  onBackground(): void {
    DemoRuntime.flush().catch(() => {
      console.error('ArkGenie session flush failed; pending changes remain in memory.');
    });
  }

  onDestroy(): void {
    DemoRuntime.flush().catch(() => {
      console.error('ArkGenie final session flush failed.');
    });
  }
}
