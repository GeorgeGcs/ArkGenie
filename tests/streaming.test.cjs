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
