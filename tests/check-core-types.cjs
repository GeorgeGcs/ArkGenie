// TypeScript checks for core logic only. This does not replace ArkTS/DevEco compilation.
const fs = require('node:fs');
const path = require('node:path');
const { getTypeScript } = require('./helpers/ets-loader.cjs');
const ts = getTypeScript();
const root = path.resolve(__dirname, '..');
const definitions = path.join(root, 'tests', '__platform_types__.d.ts');
// Only the signatures used by this adapter, checked against the platform SDK.
const platform = `
declare module '@kit.AbilityKit' { export namespace common { interface Context {} } }
declare module '@kit.ArkData' {
  import { common } from '@kit.AbilityKit';
  export namespace preferences {
    type ValueType = string | number | boolean;
    interface Preferences {
      getSync(key: string, fallback: ValueType): ValueType;
      putSync(key: string, value: ValueType): void;
      flush(): Promise<void>;
    }
    function getPreferences(context: common.Context, options: { name: string }): Promise<Preferences>;
  }
}
`;
const options = { noEmit: true, strict: true, target: ts.ScriptTarget.ES2020,
  module: ts.ModuleKind.CommonJS, skipLibCheck: true };
const host = ts.createCompilerHost(options);
const nativeRead = host.readFile.bind(host);
function read(file) {
  if (path.resolve(file) === definitions) return platform;
  const original = file.endsWith('.ts') ? file.slice(0, -3) + '.ets' : '';
  if (original && fs.existsSync(original)) {
    return fs.readFileSync(original, 'utf8').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  }
  return nativeRead(file);
}
host.readFile = read;
const nativeExists = host.fileExists.bind(host);
host.fileExists = file => path.resolve(file) === definitions || nativeExists(file) ||
  (file.endsWith('.ts') && fs.existsSync(file.slice(0, -3) + '.ets'));
host.getSourceFile = (file, languageVersion) => {
  const source = read(file);
  return source === undefined ? undefined : ts.createSourceFile(file, source, languageVersion, true);
};
const entries = ['core/src/main/ets/ChatController.ts',
  'core/src/main/ets/session/PreferencesSessionStore.ts'].map(file => path.join(root, file));
const program = ts.createProgram([...entries, definitions], options, host);
const diagnostics = ts.getPreEmitDiagnostics(program);
if (diagnostics.length) {
  console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, {
    getCanonicalFileName: f => f, getCurrentDirectory: () => root, getNewLine: () => '\n'
  }));
  process.exitCode = 1;
} else console.log('Core TypeScript logic checks passed (platform signatures stubbed; ArkTS compilation excluded).');
