const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

function compiler() {
  try { return require('typescript'); } catch { /* Allow an existing global installation offline. */ }
  if (process.env.ARKGENIE_TYPESCRIPT_PATH) return require(process.env.ARKGENIE_TYPESCRIPT_PATH);
  try {
    const script = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    const root = execFileSync(script, ['root', '-g'], {
      encoding: 'utf8', shell: process.platform === 'win32', windowsHide: true
    }).trim();
    return require(path.join(root, 'typescript'));
  } catch {
    throw new Error('Install test dependencies with npm install, or set ARKGENIE_TYPESCRIPT_PATH.');
  }
}

const ts = compiler();

/** Execute the actual ETS logic; reactive decorators and device APIs are not exercised. */
function createLoader({ clock = globalThis, mocks = {} } = {}) {
  const cache = new Map();
  function load(file) {
    file = path.resolve(__dirname, '../..', file);
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} };
    cache.set(file, module);
    const source = fs.readFileSync(file, 'utf8')
      .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
    const result = ts.transpileModule(source, {
      fileName: file.replace(/\.ets$/, '.ts'), reportDiagnostics: true,
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    });
    const errors = (result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error);
    if (errors.length) throw new Error(errors.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
    new Function('require', 'exports', 'module', 'setTimeout', 'clearTimeout', result.outputText)(
      name => {
        if (Object.hasOwn(mocks, name)) return mocks[name];
        if (!name.startsWith('.')) throw new Error(`Unmocked platform module: ${name}`);
        return load(path.resolve(path.dirname(file), name + '.ets'));
      }, module.exports, module, clock.setTimeout.bind(clock), clock.clearTimeout.bind(clock)
    );
    return module.exports;
  }
  return load;
}

class FakeClock {
  now = 0;
  next = 0;
  tasks = new Map();
  setTimeout(fn, delay) {
    const id = ++this.next;
    this.tasks.set(id, { fn, at: this.now + delay });
    return id;
  }
  clearTimeout(id) { this.tasks.delete(id); }
  tick(ms) {
    const end = this.now + ms;
    while (true) {
      const entry = [...this.tasks].filter(([, t]) => t.at <= end)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!entry) break;
      const [id, task] = entry;
      this.tasks.delete(id); this.now = task.at; task.fn();
    }
    this.now = end;
  }
}

module.exports = { createLoader, FakeClock, getTypeScript: () => ts };
