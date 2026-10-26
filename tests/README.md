# 主机侧回归测试

在仓库根目录使用 Node.js 22+：

```sh
npm install
npm test
npm run check:core
```

若已有全局 TypeScript，可直接运行 `npm test`；测试器先尝试本地 TypeScript，再尝试 `ARKGENIE_TYPESCRIPT_PATH` 环境变量和全局安装。测试不需要 API Key、模拟器或设备。

测试通过 TypeScript 转译**实际 ETS 源码**，只剥离 `@ObservedV2/@Trace`，使用确定性虚拟时钟和 Preferences API 替身。平台替身模拟缓存与磁盘分离，并支持分阶段 flush 故障注入。

覆盖连续流式窗口、停止/错误保留尾部、取消后迟到回调、重试、会话切换、同步 Transport、快照恢复、写入合并、并发 flush、长中文和 emoji、损坏恢复及失败重试。包含 Controller 停止后落盘再重开的集成用例。

`check:core` 对 Controller、Preferences 适配器及依赖做 TypeScript strict 检查，平台声明只保留使用到的 SDK 签名。

这些检查不验证 ArkUI 响应式行为、ArkTS 严格语法兼容性、真实 Preferences 文件系统或设备生命周期。DevEco 构建与设备验收需要单独执行，主机测试通过不表示设备验收通过。
