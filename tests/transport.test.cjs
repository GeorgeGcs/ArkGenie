const { test } = require('node:test');
const assert = require('node:assert/strict');
const { TextDecoder } = require('node:util');
const { createLoader, FakeClock } = require('./helpers/ets-loader.cjs');

function setup(options = {}, provider = false) {
  const clock = new FakeClock();
  const clients = [];
  const load = createLoader({ clock, mocks: {
    '@kit.NetworkKit': { http: { createHttp() {
      const handlers = {};
      const client = {
        destroyed: 0, handlers,
        on(name, fn) { handlers[name] = fn; },
        destroy() { this.destroyed++; },
        requestInStream(url, request) {
          this.request = request;
          return new Promise((resolve, reject) => { this.resolve = resolve; this.reject = reject; });
        },
        data(text) { handlers.dataReceive(Buffer.from(text)); },
        end() { handlers.dataEnd(); }
      };
      clients.push(client); return client;
    } } },
    '@ohos.util': { default: { TextDecoder: { create() {
      const decoder = new TextDecoder();
      return { decodeToString(data, opts) { return decoder.decode(data, opts); } };
    } } } }
  } });
  const events = [];
  const callbacks = {
    onChunk: text => events.push(['chunk', text]),
    onComplete: text => events.push(['done', text]),
    onError: error => events.push(['error', error.message]),
    onToolCall: tool => events.push(['tool', tool])
  };
  const transport = provider
    ? new (load('core/src/main/ets/provider/OpenAiCompatibleProvider.ets').OpenAiCompatibleProvider)({
      baseUrl: 'https://example.invalid', apiKey: 'test', model: 'test', ...options })
    : new (load('core/src/main/ets/transport/SseTransport.ets').SseTransport)({
      url: 'https://example.invalid', buildBody: () => '{}', parsePayload: text => JSON.parse(text).text ?? null,
      reconnectAttempts: 2, reconnectDelayMs: 10, ...options });
  const task = transport.send({ messages: [] }, callbacks);
  return { clock, clients, events, task, transport, callbacks };
}
const event = delta => `data: ${JSON.stringify({ choices: [{ delta }] })}\n\n`;

test('SSE retries only before output and ignores callbacks from the old connection', async () => {
  const { clock, clients, events } = setup();
  const old = clients[0]; old.end();
  old.data('data: {"text":"late"}\n'); old.end();
  clock.tick(10);
  assert.equal(clients.length, 2);
  old.resolve(500); await Promise.resolve();
  clients[1].data('data: {"text":"new"}\n\ndata: [DONE]\n\ndata: {"text":"ignored"}\n');
  assert.deepEqual(events, [['chunk', 'new'], ['done', 'new']]);
  assert.equal(clock.tasks.size, 0);
  assert.equal(old.destroyed, 1);
});

test('SSE never replays a generation after receiving text', () => {
  const { clients, clock, events } = setup();
  clients[0].data('data: {"text":"partial"}\n'); clients[0].end(); clock.tick(100);
  assert.equal(clients.length, 1);
  assert.equal(events[1][0], 'error');
  assert.equal(clients[0].destroyed, 1);
});

test('SSE decodes fragmented UTF-8 and cancels retry timers without creating unused clients', () => {
  const { clients, events, task, clock } = setup();
  const data = Buffer.from('data: {"text":"你好😀"}\n');
  for (const byte of data) clients[0].handlers.dataReceive(Uint8Array.of(byte));
  task.cancel(); clients[0].end(); clock.tick(100);
  assert.deepEqual(events, [['chunk', '你好😀']]);
  assert.equal(clients.length, 1);
  assert.equal(clients[0].destroyed, 1);
});

test('heartbeat retry is bounded and all timers are cleaned on failure', () => {
  const { clients, clock, events } = setup({ heartbeatTimeoutMs: 1000, reconnectAttempts: 1 });
  clock.tick(5000);
  assert.equal(clients.length, 2);
  assert.equal(events.length, 1);
  assert.equal(events[0][0], 'error');
  assert.equal(clock.tasks.size, 0);
});

test('provider aggregates interleaved parallel tool arguments and completes before the text result', () => {
  const { clients, events } = setup({}, true);
  clients[0].data(event({ tool_calls: [
    { index: 0, id: 'a', function: { name: 'weather', arguments: '{"city":' } },
    { index: 1, id: 'b', function: { name: 'clock', arguments: '{' } }
  ] }));
  clients[0].data(event({ tool_calls: [
    { index: 1, function: { arguments: '"zone":"UTC"}' } },
    { index: 0, function: { arguments: '"福州"}' } }
  ] }));
  clients[0].data('data: [DONE]\n');
  const complete = events.filter(([kind, tool]) => kind === 'tool' && tool.status === 'done');
  assert.deepEqual(complete.map(([, tool]) => tool), [
    { name: 'weather', callId: 'a', arguments: { city: '福州' }, status: 'done' },
    { name: 'clock', callId: 'b', arguments: { zone: 'UTC' }, status: 'done' }
  ]);
  assert.deepEqual(events.at(-1), ['done', '']);
});

test('provider request states are isolated and incomplete tool JSON is an error', () => {
  const { transport, callbacks, clients, events } = setup({}, true);
  transport.send({ messages: [] }, callbacks);
  clients[0].data(event({ tool_calls: [{ index: 0, id: 'bad', function: { name: 'bad', arguments: '{' } }] }));
  clients[1].data(event({ tool_calls: [{ index: 0, id: 'ok', function: { name: 'ok', arguments: '{}' } }] }));
  clients[1].data('data: [DONE]\n'); clients[0].data('data: [DONE]\n');
  assert.equal(events.filter(([kind]) => kind === 'done').length, 1);
  assert.equal(events.at(-1)[0], 'error');
});

test('tool output prevents replay even without an onToolCall subscriber', () => {
  const { transport, clients, clock, events, callbacks } = setup({ reconnectAttempts: 2 }, true);
  transport.send({ messages: [] }, { ...callbacks, onToolCall: undefined });
  clients[1].data(event({ tool_calls: [{ index: 0, function: { name: 'tool', arguments: '{}' } }] }));
  clients[1].end(); clock.tick(2000);
  assert.equal(clients.length, 2);
  assert.equal(events.at(-1)[0], 'error');
});

test('cancel during retry delay destroys the old client once and prevents reconnection', () => {
  const { clients, task, clock, events } = setup();
  clients[0].end(); task.cancel(); clock.tick(100);
  assert.equal(clients.length, 1);
  assert.equal(clients[0].destroyed, 1);
  assert.equal(clock.tasks.size, 0);
  assert.deepEqual(events, []);
});

test('HTTP authentication failures fail immediately; transient server errors can retry', async () => {
  const auth = setup(); auth.clients[0].resolve(401); await Promise.resolve(); auth.clock.tick(100);
  assert.equal(auth.clients.length, 1);
  assert.deepEqual(auth.events, [['error', 'HTTP 401']]);
  const transient = setup(); transient.clients[0].resolve(503); await Promise.resolve(); transient.clock.tick(10);
  assert.equal(transient.clients.length, 2);
  transient.task.cancel();
});

test('synchronous request setup failures release clients and heartbeat timers', () => {
  const { clients, events, clock } = setup({ heartbeatTimeoutMs: 1000, buildBody() { throw new Error('bad input'); } });
  assert.equal(clients[0].destroyed, 1);
  assert.equal(clock.tasks.size, 0);
  assert.deepEqual(events, [['error', 'SSE request setup failed']]);
});
