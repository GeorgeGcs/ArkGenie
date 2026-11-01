const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createLoader } = require('./helpers/ets-loader.cjs');
const { StreamingMarkdownParser } = createLoader()('chat-ui/src/main/ets/components/StreamingMarkdownParser.ets');

test('incremental Markdown equals fresh parsing for every streamed character including code fences', () => {
  const content = '# 标题\n\n段落😀\n第二行\n\n- 条目\n- 条目\n> 引用\n\n```ts\nlet a = 1;\n\n```\n\n末尾';
  const parser = new StreamingMarkdownParser();
  for (let i = 0; i <= content.length; i++) {
    const partial = content.slice(0, i);
    assert.deepEqual(parser.update(partial), new StreamingMarkdownParser().update(partial), `offset ${i}`);
  }
});

test('duplicate blocks have unique stable IDs and completed prefix objects are reused', () => {
  const parser = new StreamingMarkdownParser();
  const first = parser.update('same\n\nsame\n\nend');
  const next = parser.update('same\n\nsame\n\nending');
  assert.equal(new Set(next.map(block => block.id)).size, 3);
  assert.equal(first[0], next[0]);
  assert.equal(first[1], next[1]);
  assert.equal(first[2].id, next[2].id);
  assert.deepEqual(parser.update('replacement'), new StreamingMarkdownParser().update('replacement'));
  assert.deepEqual(parser.update(''), []);
});
