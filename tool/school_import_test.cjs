const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../assets/school_import.js'), 'utf8');
const terms = [{ DM: '2026-2027-1', MC: '示例秋季' }, { DM: '2025-2026-2', MC: '示例春季' }];
const row = n => ({ KCM: `示例课${n}`, KCH: `TEST${n}`, SKJS: '示例教师', JASMC: '示例教室', SKXQ: 1, KSJC: 1, JSJC: 2, ZCMC: '1-16周', STUDENT_ID: 'DO_NOT_EXPORT' });
async function run({ requested = null, visible = '示例秋季', rows = [row(1)], total = rows.length, repeated = false, html = false, location = {} } = {}) {
  const messages = [], requests = [];
  const script = source.replaceAll('__MEIKE_NONCE__', '"test-nonce"').replaceAll('__MEIKE_TERM__', JSON.stringify(requested));
  await vm.runInNewContext(script, {
    URL, AbortController, setTimeout, clearTimeout,
    location: { protocol: 'https:', hostname: 'vpn.seu.edu.cn', origin: 'https://vpn.seu.edu.cn', pathname: '/proxy/demo/jwapp/sys/wdkb/index.do', ...location },
    document: { body: { innerText: visible } },
    MeiKeSchoolImport: { postMessage: value => messages.push(JSON.parse(value)) },
    fetch: async (value, options) => {
      const url = new URL(value);
      requests.push({ url, options });
      const data = url.pathname.endsWith('xnxqcx.do') ? { datas: { xnxqcx: { rows: terms } } } : {
        datas: { xskcb: { totalCount: total, rows: repeated ? rows.slice(0, 100) : rows.slice((Number(url.searchParams.get('pageNumber')) - 1) * 100, Number(url.searchParams.get('pageNumber')) * 100) } }
      };
      return { ok: true, text: async () => html ? '<html>Login</html>' : JSON.stringify(data) };
    },
  });
  return { messages, requests };
}
test('reads all pages through the VPN prefix and exports only scheduling fields', async () => {
  const { messages, requests } = await run({ rows: Array.from({ length: 125 }, (_, i) => row(i)) });
  assert.equal(messages[0].kind, 'success');
  assert.equal(messages[0].rows.length, 125);
  assert.equal(messages[0].nonce, 'test-nonce');
  assert.equal(requests.length, 3);
  assert.ok(requests.every(r => r.url.pathname.startsWith('/proxy/demo/jwapp/sys/wdkb/')));
  assert.ok(requests.every(r => r.options.credentials === 'same-origin'));
  assert.ok(messages[0].rows.every(r => !Object.hasOwn(r, 'STUDENT_ID')));
});
test('asks for term selection instead of guessing the latest term', async () => {
  const { messages, requests } = await run({ visible: '我的课表' });
  assert.equal(messages[0].kind, 'terms');
  assert.equal(messages[0].terms.length, 2);
  assert.equal(requests.length, 1);
});
test('explicit term selection is used and an unknown term fails', async () => {
  const result = await run({ requested: terms[1].DM });
  assert.equal(result.messages[0].termCode, terms[1].DM);
  assert.equal(result.requests[1].url.searchParams.get('XNXQDM'), terms[1].DM);
  assert.equal((await run({ requested: 'unknown' })).messages[0].kind, 'error');
});
test('expired login HTML and empty results do not produce import data', async () => {
  assert.equal((await run({ html: true })).messages[0].kind, 'error');
  assert.equal((await run({ rows: [] })).messages[0].kind, 'error');
});
test('detects repeated or incomplete pages rather than silently losing courses', async () => {
  const rows = Array.from({ length: 125 }, (_, i) => row(i));
  assert.equal((await run({ rows, repeated: true })).messages[0].kind, 'error');
  assert.equal((await run({ rows: [row(1)], total: 2 })).messages[0].kind, 'error');
});
test('untrusted origins and HTTP never request school data', async () => {
  for (const location of [{ hostname: 'seu.edu.cn.evil.test' }, { protocol: 'http:' }, { pathname: '/login' }]) {
    const result = await run({ location });
    assert.equal(result.requests.length, 0);
    assert.equal(result.messages[0].kind, 'error');
  }
});
