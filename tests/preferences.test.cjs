const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader, FakeClock } = require('./helpers/ets-loader.cjs');

const MANIFEST_KEY = 'arkgenie.sessions.manifest';

function setup() {
  const clock = new FakeClock();
  const files = new Map();
  const backends = [];
  const preferences = { async getPreferences(_context, { name }) {
    const backend = {
      name, values: new Map(files.get(name) || []), flushCalls: 0, failOnFlush: 0, beforeFlush: null,
      getSync(key, fallback) { return this.values.has(key) ? this.values.get(key) : fallback; },
      putSync(key, value) {
        if (typeof value === 'string' && value.length > 8192) throw new Error('native value limit');
        this.values.set(key, value);
      },
      async flush() {
        this.flushCalls++;
        if (this.beforeFlush) await this.beforeFlush();
        if (this.flushCalls === this.failOnFlush) throw new Error('disk unavailable');
        files.set(name, new Map(this.values));
      }
    };
    backends.push(backend);
    return backend;
  } };
  const load = createLoader({ clock, mocks: { '@kit.ArkData': { preferences }, '@kit.AbilityKit': {} } });
  const { PreferencesSessionStore } = load('core/src/main/ets/session/PreferencesSessionStore.ets');
  const { SessionManager } = load('core/src/main/ets/session/SessionManager.ets');
  const { ChatController } = load('core/src/main/ets/ChatController.ets');
  return { clock, files, backends, PreferencesSessionStore, SessionManager, ChatController };
}

function snapshot(content = 'hello', id = 's1', status = 'done') {
  return {
    id, title: '测试会话', createdAt: 1, updatedAt: 2,
    messages: [{ id: 'm1', role: 'assistant', content, status, errorText: '',
      attachments: [{ kind: 'file', uri: 'sandbox:test', name: 'test.txt', mimeType: 'text/plain' }],
      createdAt: 1, contentType: 'text', metadata: { nested: { label: 'original' } } }]
  };
}

test('save and reopen restore messages, attachments and metadata', async () => {
  const { PreferencesSessionStore } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot()); await store.flush();
  const reopened = await PreferencesSessionStore.open({});
  assert.deepEqual(reopened.load(), [snapshot()]);
  assert.equal(store.hasPendingWrites, false);
});

test('save/load snapshots are isolated from caller mutations', async () => {
  const { PreferencesSessionStore } = setup();
  const store = await PreferencesSessionStore.open({});
  const original = snapshot(); store.save(original);
  original.messages[0].metadata.nested.label = 'changed';
  const loaded = store.load(); loaded[0].messages[0].metadata.nested.label = 'changed again';
  await store.flush();
  assert.equal(store.load()[0].messages[0].metadata.nested.label, 'original');
});

test('frequent writes coalesce into one staged commit', async () => {
  const { PreferencesSessionStore, backends, clock } = setup();
  const store = await PreferencesSessionStore.open({}, { debounceMs: 300 });
  for (let i = 0; i < 10; i++) store.save(snapshot(String(i)));
  clock.tick(299); assert.equal(backends[0].flushCalls, 0);
  clock.tick(1); await store.flush();
  assert.equal(backends[0].flushCalls, 2);
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, '9');
  await store.flush(); assert.equal(backends[0].flushCalls, 2);
});

test('long Chinese/emoji content is split below Preferences string limit', async () => {
  const { PreferencesSessionStore, backends } = setup();
  const store = await PreferencesSessionStore.open({});
  const value = '你好😀'.repeat(6000);
  store.save(snapshot(value)); await store.flush();
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, value);
  assert.ok([...backends[0].values.values()].every(v => v.length <= 2048));
  for (const [key, value] of backends[0].values) {
    if (key === MANIFEST_KEY) continue;
    const first = value.charCodeAt(0), last = value.charCodeAt(value.length - 1);
    assert.ok(first < 0xDC00 || first > 0xDFFF, 'chunk must not start with a lone low surrogate');
    assert.ok(last < 0xD800 || last > 0xDBFF, 'chunk must not end with a lone high surrogate');
  }
});

test('remove and clear survive reopening without deleting another namespace', async () => {
  const { PreferencesSessionStore } = setup();
  const store = await PreferencesSessionStore.open({});
  const other = await PreferencesSessionStore.open({}, { name: 'another_account' });
  other.save(snapshot('other')); await other.flush();
  store.save(snapshot('first', 's1')); store.save(snapshot('second', 's2')); await store.flush();
  store.remove('s1'); await store.flush();
  assert.deepEqual((await PreferencesSessionStore.open({})).load().map(s => s.id), ['s2']);
  store.clear(); await store.flush();
  assert.deepEqual((await PreferencesSessionStore.open({})).load(), []);
  assert.equal((await PreferencesSessionStore.open({}, { name: 'another_account' })).load().length, 1);
});

test('flush errors are observable, retain dirty state, and support explicit retry', async () => {
  const { PreferencesSessionStore, backends } = setup();
  const errors = [];
  const store = await PreferencesSessionStore.open({}, { onError: e => errors.push(e) });
  store.save(snapshot()); backends[0].failOnFlush = 1;
  await assert.rejects(store.flush(), /disk unavailable/);
  assert.equal(store.hasPendingWrites, true);
  assert.equal(store.lastError.operation, 'flush');
  assert.equal(errors.length, 1);
  await store.flush();
  assert.equal(store.hasPendingWrites, false); assert.equal(store.lastError, null);
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, 'hello');
});

test('failed manifest commit leaves the previously committed snapshot readable', async () => {
  const { PreferencesSessionStore, backends } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot('old')); await store.flush();
  store.save(snapshot('new')); backends[0].failOnFlush = 4;
  await assert.rejects(store.flush());
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, 'old');
  await store.flush();
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, 'new');
});

test('changes made during a disk flush are serialized and included before return', async () => {
  const { PreferencesSessionStore, backends } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot('first'));
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  backends[0].beforeFlush = () => gate;
  const pending = store.flush();
  store.save(snapshot('second')); const concurrent = store.flush();
  release(); await Promise.all([pending, concurrent]);
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, 'second');
  assert.equal(store.hasPendingWrites, false);
});

test('damaged active snapshot falls back to previous committed snapshot and reports recovery', async () => {
  const { PreferencesSessionStore, files } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot('old')); await store.flush(); store.save(snapshot('new')); await store.flush();
  const disk = files.get('arkgenie_sessions');
  const manifest = JSON.parse(disk.get(MANIFEST_KEY));
  disk.set(`arkgenie.sessions.${manifest.active.bank}.0`, 'broken');
  const errors = [];
  const restored = await PreferencesSessionStore.open({}, { onError: e => errors.push(e) });
  assert.equal(restored.load()[0].messages[0].content, 'old');
  assert.equal(errors[0].operation, 'restore');
  restored.save(snapshot('recovered')); await restored.flush();
  assert.equal((await PreferencesSessionStore.open({})).load()[0].messages[0].content, 'recovered');
});

test('invalid manifest fails initialization instead of silently overwriting history', async () => {
  const { PreferencesSessionStore, files } = setup();
  files.set('arkgenie_sessions', new Map([[MANIFEST_KEY, '{broken']]));
  await assert.rejects(PreferencesSessionStore.open({}));
  assert.equal(files.get('arkgenie_sessions').get(MANIFEST_KEY), '{broken');
});

test('a damaged cleared snapshot cannot fall back to previously deleted history', async () => {
  const { PreferencesSessionStore, files } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot('old')); await store.flush(); store.clear(); await store.flush();
  const disk = files.get('arkgenie_sessions');
  const manifest = JSON.parse(disk.get(MANIFEST_KEY));
  assert.equal(manifest.previous, undefined);
  disk.set(`arkgenie.sessions.${manifest.active.bank}.0`, 'damaged');
  await assert.rejects(PreferencesSessionStore.open({}));
});

test('reopened unfinished messages become cancelled and retain partial text', async () => {
  const { PreferencesSessionStore } = setup();
  const store = await PreferencesSessionStore.open({});
  store.save(snapshot('partial', 's1', 'streaming')); await store.flush();
  const restored = (await PreferencesSessionStore.open({})).load()[0].messages[0];
  assert.equal(restored.status, 'cancelled'); assert.equal(restored.content, 'partial');
});

test('controller stop plus flush persists the complete streamed tail across reopening', async () => {
  const { PreferencesSessionStore, SessionManager, ChatController, clock } = setup();
  const store = await PreferencesSessionStore.open({});
  let callbacks;
  const controller = new ChatController({ send(_r, cb) { callbacks = cb; return { cancel() {} }; } },
    '', new SessionManager(store));
  controller.send('hello'); callbacks.onChunk('A'); clock.tick(50); callbacks.onChunk('B');
  controller.stop(); await store.flush();
  const restored = new SessionManager(await PreferencesSessionStore.open({}));
  assert.equal(restored.current.messages[1].content, 'AB');
  assert.equal(restored.current.messages[1].status, 'cancelled');
});

test('background flush failure does not produce an unhandled rejection', async () => {
  const { PreferencesSessionStore, backends, clock } = setup();
  const errors = [];
  const store = await PreferencesSessionStore.open({}, { onError: e => errors.push(e) });
  store.save(snapshot()); backends[0].failOnFlush = 1;
  clock.tick(300);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(errors.length, 1); assert.equal(store.hasPendingWrites, true);
  await store.flush();
});
