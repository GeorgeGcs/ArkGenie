const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader, FakeClock } = require('./helpers/ets-loader.cjs');

function setup() {
  const clock = new FakeClock();
  const load = createLoader({ clock });
  const { ChatController } = load('core/src/main/ets/ChatController.ets');
  const requests = [];
  const transport = {
    send(request, callbacks) {
      const task = { request, callbacks, cancelled: false };
      requests.push(task);
      return { cancel() { task.cancelled = true; task.onCancel?.(); } };
    }
  };
  const controller = new ChatController(transport);
  controller.send('hello');
  return { clock, controller, transport, requests, assistant: controller.messages[1], ChatController };
}

test('each 50ms window appends more chunks, including Chinese and emoji', () => {
  const { clock, requests, assistant } = setup();
  for (const [i, chunk] of ['A', '你好', '😀', 'B'].entries()) {
    requests[0].callbacks.onChunk(chunk);
    clock.tick(49);
    assert.equal(assistant.content, ['A', '你好', '😀', 'B'].slice(0, i).join(''));
    clock.tick(1);
  }
  assert.equal(assistant.content, 'A你好😀B');
});

test('bursts coalesce and completion cancels the outstanding timer', () => {
  const { clock, requests, assistant, controller } = setup();
  const cb = requests[0].callbacks;
  cb.onChunk('A'); cb.onChunk('B');
  assert.equal(clock.tasks.size, 1);
  cb.onComplete('AB'); clock.tick(100);
  assert.equal(assistant.content, 'AB');
  assert.equal(assistant.status, 'done');
  assert.equal(controller.isGenerating, false);
  assert.equal(clock.tasks.size, 0);
});

test('stop after an earlier flush preserves the unflushed tail and persists it', () => {
  const { clock, requests, assistant, controller } = setup();
  requests[0].callbacks.onChunk('A'); clock.tick(50);
  requests[0].callbacks.onChunk('B'); controller.stop();
  assert.equal(assistant.content, 'AB');
  assert.equal(assistant.status, 'cancelled');
  assert.equal(requests[0].cancelled, true);
  assert.equal(controller.sessionManager.current.toSnapshot().messages[1].content, 'AB');
  assert.equal(clock.tasks.size, 0);
});

test('transport cancellation callbacks cannot overwrite stopped content', () => {
  const { requests, assistant, controller } = setup();
  requests[0].callbacks.onChunk('A');
  requests[0].onCancel = () => {
    requests[0].callbacks.onChunk('late');
    requests[0].callbacks.onComplete('wrong');
  };
  controller.stop();
  assert.equal(assistant.content, 'A');
  assert.equal(assistant.status, 'cancelled');
});

test('error after an earlier flush preserves the buffered tail', () => {
  const { clock, requests, assistant, controller } = setup();
  const cb = requests[0].callbacks;
  cb.onChunk('A'); clock.tick(50); cb.onChunk('B'); cb.onError(new Error('offline'));
  assert.equal(assistant.content, 'AB');
  assert.equal(assistant.status, 'error');
  assert.equal(assistant.errorText, 'offline');
  assert.equal(controller.isGenerating, false);
  assert.equal(clock.tasks.size, 0);
});

test('stop then immediately send: a new request gets its own flush timer', () => {
  const { clock, requests, controller } = setup();
  requests[0].callbacks.onChunk('old'); clock.tick(20); controller.stop();
  controller.send('next');
  const next = controller.messages[3];
  requests[1].callbacks.onChunk('new');
  clock.tick(30); assert.equal(next.content, '');
  clock.tick(20); assert.equal(next.content, 'new');
  requests[0].callbacks.onChunk('late');
  requests[0].callbacks.onError(new Error('late'));
  requests[0].callbacks.onComplete('late');
  assert.equal(next.content, 'new');
  assert.equal(controller.isGenerating, true);
});

test('retrying the same message ignores stale callbacks and preserves only new text', () => {
  const { clock, requests, controller, assistant } = setup();
  requests[0].callbacks.onChunk('old'); controller.stop();
  controller.retry(assistant.id);
  requests[0].callbacks.onComplete('stale');
  requests[1].callbacks.onChunk('new'); clock.tick(50);
  assert.equal(assistant.content, 'new');
  requests[1].callbacks.onComplete('new');
  assert.equal(assistant.status, 'done');
});

test('switching sessions cancels the old request and keeps the tail in the old session', () => {
  const { clock, requests, controller, assistant } = setup();
  const oldId = controller.currentSessionId;
  requests[0].callbacks.onChunk('A'); clock.tick(50); requests[0].callbacks.onChunk('B');
  controller.newSession();
  requests[0].callbacks.onChunk('late'); clock.tick(100);
  assert.equal(controller.messages.length, 0);
  assert.equal(assistant.content, 'AB');
  controller.switchSession(oldId);
  assert.equal(controller.messages[1].content, 'AB');
});

test('clear cancels pending flushes and late completion cannot resurrect messages', () => {
  const { clock, requests, controller } = setup();
  requests[0].callbacks.onChunk('A'); controller.clear();
  requests[0].callbacks.onComplete('A'); clock.tick(100);
  assert.deepEqual(controller.messages, []);
  assert.equal(clock.tasks.size, 0);
});

test('synchronous transport completion and thrown send both settle the controller', () => {
  const { ChatController, clock } = setup();
  const instant = new ChatController({ send(_request, cb) {
    cb.onChunk('A'); cb.onComplete('A'); return { cancel() {} };
  } });
  instant.send('test');
  assert.equal(instant.messages[1].content, 'A');
  assert.equal(instant.isGenerating, false);
  assert.equal(clock.tasks.size, 0);
  const broken = new ChatController({ send() { throw new Error('failure'); } });
  broken.send('test');
  assert.equal(broken.messages[1].status, 'error');
  assert.equal(broken.isGenerating, false);
});

test('retry history excludes later turns while preserving local messages', () => {
  const { controller, requests, assistant } = setup();
  requests[0].callbacks.onComplete('first');
  controller.send('future question'); requests[1].callbacks.onComplete('future answer');
  const ids = controller.messages.map(m => m.id);
  controller.retry(assistant.id);
  assert.deepEqual(requests[2].request.messages.map(m => m.content), ['hello']);
  assert.deepEqual(controller.messages.map(m => m.id), ids);
  assert.equal(controller.messages[3].content, 'future answer');
});

test('context budgets keep whole recent turns and system prompt without trimming local history', () => {
  const { controller, requests } = setup();
  requests[0].callbacks.onComplete('first');
  controller.send('second'); requests[1].callbacks.onComplete('answer');
  controller.setContextPolicy({ maxRounds: 2, maxCharacters: 100 });
  controller.send('third');
  assert.deepEqual(requests[2].request.messages.map(m => m.content), ['second', 'answer', 'third']);
  requests[2].callbacks.onComplete('third answer');
  controller.setContextPolicy({ maxCharacters: 1 });
  controller.send('latest oversized question');
  assert.deepEqual(requests[3].request.messages.map(m => m.content), ['latest oversized question']);
  assert.equal(controller.messages.length, 8);
  assert.throws(() => controller.setContextPolicy({ maxRounds: 0 }), /positive integers/);
  const withSystem = new controller.constructor({ send(request, cb) {
    assert.deepEqual(request.messages.map(m => m.content), ['system', 'question']);
    cb.onComplete('ok'); return { cancel() {} };
  } }, 'system');
  withSystem.setContextPolicy({ maxCharacters: 1 }); withSystem.send('question');
});

test('stream UI updates are independent of snapshot frequency, and stop persists the full tail', () => {
  const { controller, requests, clock } = setup();
  const store = controller.sessionManager.store;
  let saves = 0;
  const save = store.save.bind(store);
  store.save = snapshot => { saves++; save(snapshot); };
  for (let i = 0; i < 10; i++) {
    requests[0].callbacks.onChunk('字'); clock.tick(50);
  }
  assert.equal(controller.messages[1].content, '字'.repeat(10));
  assert.equal(saves, 0);
  clock.tick(50); assert.equal(saves, 1);
  requests[0].callbacks.onChunk('尾部'); controller.stop();
  assert.equal(store.load()[0].messages[1].content, '字'.repeat(10) + '尾部');
  assert.equal(store.load()[0].messages[1].status, 'cancelled');
  assert.equal(clock.tasks.size, 0);
});

test('explicit controller persist includes buffered content before the next UI tick', () => {
  const { controller, requests, clock } = setup();
  requests[0].callbacks.onChunk('buffered');
  controller.persistCurrent();
  assert.equal(controller.sessionManager.store.load()[0].messages[1].content, 'buffered');
  controller.newSession(); clock.tick(1000);
  const old = controller.sessionManager.sessions.find(s => s.messages.length > 0);
  assert.equal(old.messages[1].content, 'buffered');
});
