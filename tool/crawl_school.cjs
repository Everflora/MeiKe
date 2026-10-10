// Standalone, user-approved browser workflow. Login is performed by the user.
// No cookies, login inputs, storage, authorization headers or HAR are inspected.
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const localRequire = createRequire(path.resolve(__dirname, '../.local/crawler/package.json'));
const { chromium } = localRequire('playwright');
const root = path.resolve(__dirname, '../.local/school-analysis');
const controlFile = path.join(root, 'control.json');
const entry = 'https://ehall.seu.edu.cn/jwapp/sys/kcbcx/*default/index.do#/qxkcb';
const allowedFields = new Set(['JXBID','JXBH','JXBDM','KCH','KCDM','KCM','KCMC',
  'SKJS','JSXM','JSM','SKXQ','XQJ','KSJC','JSJC','ZCMC','SKZC','JASMC','XNXQDM','XNXQ',
  'WID','KXH','JXBMC','YPSJDD','SKBJ','BJDM','BJXX',
  'KKDWDM','KKDWDM_DISPLAY','PKDWDM','PKDWDM_DISPLAY',
  'XXXQDM','XXXQDM_DISPLAY','JASDM','JASXQDM','XF','XS','ZXSXX',
  'KCXZDM','KCLBDM','XGXKLBDM','XGXKLBDM_DISPLAY','XKZRS','KRL']);
const safeParameters = new Set(['XNXQDM','XNXQ','xnxqdm','xnxq','pageNumber','pageSize',
  'pageIndex','pageNum','querySetting','query','KCH','KCDM','KCMC','SKJS','XQDM','XQ','JXBH']);
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const sanitize = rows => rows.map(row => Object.fromEntries(Object.entries(row).filter(([key]) => allowedFields.has(key))));
const writeJson = (name, value) => fs.writeFileSync(path.join(root, name), JSON.stringify(value, null, 2));
function tables(value, location = []) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
  const found = Array.isArray(value.rows) ? [{ path: location, table: value }] : [];
  for (const [key, child] of Object.entries(value)) {
    if (key !== 'rows') found.push(...tables(child, [...location, key]));
  }
  return found;
}
const tableAt = (value, keys) => keys.reduce((current, key) => current?.[key], value);
const tableTotal = table => table.totalCount ?? table.totalSize ?? table.total;
function parseParameters(request, contentType) {
  const postData = request.postData();
  if (postData && contentType?.includes('application/json')) {
    return { encoding: 'json', values: JSON.parse(postData) };
  }
  return { encoding: 'form', values: Object.fromEntries(new URLSearchParams(postData || new URL(request.url()).search)) };
}
async function main() {
  fs.mkdirSync(root, { recursive: true });
  const executable = process.env.MEIKE_BROWSER_EXECUTABLE;
  const launchOptions = { headless: false, ...(executable ? { executablePath: executable } : {}) };
  if (process.env.MEIKE_BROWSER_PROXY) launchOptions.proxy = { server: process.env.MEIKE_BROWSER_PROXY };
  const browser = await chromium.launch(launchOptions);
  const context = await browser.newContext({ viewport: null });
  const page = await context.newPage();
  const observed = new Map();
  let closed = false;
  browser.on('disconnected', () => { closed = true; });
  const observe = async response => {
    try {
      const url = new URL(response.url());
      if (!/(^|\.)seu\.edu\.cn$/.test(url.hostname) || !url.pathname.includes('/kcbcx/')) return;
      if (url.pathname.endsWith('.js')) {
        if (response.ok()) {
          const source = await response.text();
          if (source.length < 5000000) {
            const folder = path.join(root, 'sources');
            fs.mkdirSync(folder, { recursive: true });
            fs.writeFileSync(path.join(folder, path.basename(url.pathname)), source);
          }
        }
        return;
      }
      const request = response.request();
      if (!['xhr', 'fetch'].includes(request.resourceType()) || !response.ok()) return;
      const payload = await response.json();
      const contentType = await request.headerValue('content-type');
      for (const { path: tablePath, table } of tables(payload)) {
        if (!table.rows.length) continue;
        const row = table.rows[0];
        const courseTable = ('KCM' in row || 'KCMC' in row) &&
          ('SKXQ' in row || 'XQJ' in row || 'KSJC' in row);
        const parsed = parseParameters(request, contentType);
        const key = `${url.pathname}:${tablePath.join('.')}`;
        observed.set(key, { key, url: response.url(), endpoint: url.pathname,
          method: request.method(), contentType, ...parsed, tablePath,
          courseTable, total: tableTotal(table), tableKeys: Object.keys(table), rowKeys: Object.keys(row),
          firstRows: courseTable ? sanitize(table.rows.slice(0, 5)) : table.rows.slice(0, 5).map(r => ({DM: r.DM, MC: r.MC})), firstCount: table.rows.length });
      }
      saveObserved();
    } catch { /* Non-JSON campus responses are not stored. */ }
  };
  context.on('response', response => { void observe(response); });
  function saveObserved() {
    writeJson('observed.json', [...observed.values()].map(spec => ({
      key: spec.key, endpoint: spec.endpoint, method: spec.method,
      tablePath: spec.tablePath, courseTable: spec.courseTable, total: spec.total,
      parameterNames: Object.keys(spec.values),
      parameters: Object.fromEntries(Object.entries(spec.values).filter(([name]) => safeParameters.has(name))),
      tableKeys: spec.tableKeys, rowKeys: spec.rowKeys, firstCount: spec.firstCount, firstRows: spec.firstRows,
    })));
  }
  async function crawl(command) {
    const spec = observed.get(command.key);
    if (!spec?.courseTable) throw new Error('请选择已实际观察到的全校课程接口。');
    if (!Number.isInteger(Number(spec.total)) || Number(spec.total) <= 0) throw new Error('必须先核实学校返回的课程总数。');
    const total = Number(spec.total);
    if (total > 200000) throw new Error('课程总数超过本次抓取上限。');
    const names = Object.keys(spec.values);
    const pageParameter = names.find(name => /^pageNumber$/i.test(name));
    const sizeParameter = names.find(name => /^pageSize$/i.test(name));
    if (!pageParameter || !sizeParameter) throw new Error('学校分页参数尚未确认，不猜测分页方式。');
    const originalSize = Number(spec.values[sizeParameter]);
    if (!Number.isInteger(originalSize) || originalSize <= 0 || originalSize > 1000) throw new Error('页大小无效。');
    const parameters = structuredClone(spec.values);
    const rows = [], seen = new Set();
    const maxPages = Math.ceil(total / originalSize) + 1;
    writeJson('progress.json', { state: 'running', total, rows: 0 });
    for (let number = 1; number <= maxPages; number++) {
      parameters[pageParameter] = String(number);
      const url = new URL(spec.url);
      let response;
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
      if (spec.method === 'GET') {
        for (const [name, value] of Object.entries(parameters)) url.searchParams.set(name, String(value));
        response = await context.request.get(url.toString(), { timeout: 30000, maxRedirects: 0 });
      } else if (spec.method === 'POST') {
        response = await context.request.post(url.toString(), {
          timeout: 30000, maxRedirects: 0,
          ...(spec.encoding === 'json' ? { data: parameters } : { form: parameters }),
        });
      } else throw new Error('此查询不是只读 GET / POST。');
          break;
        } catch (error) {
          if (!/Timeout|ECONNRESET|socket hang up/.test(error.message) || attempt === 2) throw error;
          console.log(`第 ${number} 页查询超时，稍后重试。`);
          await delay(2000 * (attempt + 1));
        }
      }
      if (!response.ok()) throw new Error(`课表查询失败（HTTP ${response.status()}）。`);
      let payload;
      try { payload = await response.json(); } catch { throw new Error('登录可能已失效，响应不是课表 JSON。'); }
      const table = tableAt(payload, spec.tablePath);
      if (!Array.isArray(table?.rows) || Number(tableTotal(table)) !== total) throw new Error('课表总数或响应结构发生变化，停止避免漏课。');
      const pageRows = sanitize(table.rows);
      const signature = JSON.stringify(pageRows);
      if (seen.has(signature)) throw new Error('接口重复返回相同页，分页未生效。');
      seen.add(signature);
      rows.push(...pageRows);
      writeJson('progress.json', { state: 'running', page: number, total, rows: rows.length });
      console.log(`课程数据 ${rows.length}/${total}`);
      if (rows.length >= total) break;
      if (!pageRows.length) throw new Error('分页提前结束，数据不完整。');
      await delay(500);
    }
    if (rows.length !== total) throw new Error('下载行数与学校总数不一致。');
    const term = String(command.termCode || '').trim();
    if (!term) throw new Error('需要已核实的学期代码。');
    if (rows.some(row => row.XNXQDM && String(row.XNXQDM) !== term)) throw new Error('数据包含其他学期，停止输出。');
    const rowIds = rows.map(row => row.WID).filter(Boolean);
    if (rowIds.length === rows.length && new Set(rowIds).size !== rows.length) throw new Error('存在重复记录 ID，停止输出。');
    writeJson('school-rows.json', { termCode: term, termName: command.termName || term,
      endpoint: spec.endpoint, fetchedAt: new Date().toISOString(), totalCount: total,
      fields: [...new Set(rows.flatMap(row => Object.keys(row)))], rows });
    writeJson('progress.json', { state: 'complete', total, rows: rows.length, file: 'school-rows.json' });
    return { rows: rows.length, file: 'school-rows.json' };
  }
  try {
    await page.goto(entry, { waitUntil: 'domcontentloaded', timeout: 60000 });
  } catch { console.log('网页仍在加载，请在窗口检查网络或完成登录。'); }
  console.log('LOGIN_WINDOW_READY：请在新窗口登录并查询全校课表。');
  let lastLocation = '';
  while (!closed) {
    try {
      const url = new URL(page.url());
      const location = `${url.origin}${url.pathname}${url.hash.split('?')[0]}`;
      if (location !== lastLocation) {
        lastLocation = location;
        writeJson('status.json', { page: location, observedTables: observed.size });
        console.log(`当前页面：${url.hostname}${url.pathname}`);
      }
      if (fs.existsSync(controlFile)) {
        const command = JSON.parse(fs.readFileSync(controlFile, 'utf8').replace(/^\uFEFF/, ''));
        fs.unlinkSync(controlFile);
        let result;
        if (command.action === 'crawl') result = await crawl(command);
        else if (command.action === 'navigate') {
          await page.goto(entry, { waitUntil: 'domcontentloaded', timeout: 60000 });
          result = { opened: true };
        } else if (command.action === 'status') {
          saveObserved();
          const semester = await page.locator('#dqxnxq').evaluateAll(nodes => nodes.map(n => ({name: n.textContent.trim(), code: n.getAttribute('value')})));
          result = { page: lastLocation, observedTables: observed.size, semester };
        } else if (command.action === 'terms') {
          const spec = [...observed.values()].find(s => s.endpoint.endsWith('/bjkcb/dqxnxq.do'));
          if (!spec) throw new Error('尚未观察到学校学期接口。');
          const target = new URL(spec.url);
          target.pathname = target.pathname.replace('/dqxnxq.do', '/xnxqcx.do');
          target.search = '';
          const response = await context.request.post(target.toString(), {form: {'*order': '-DM'}, timeout: 30000, maxRedirects: 0});
          if (!response.ok()) throw new Error('学期查询失败。');
          const data = await response.json();
          const rows = data?.datas?.xnxqcx?.rows;
          if (!Array.isArray(rows)) throw new Error('学期字典结构不符。');
          result = {terms: rows.map(r => ({code: r.DM, name: r.MC}))};
          writeJson('terms.json', result);
        } else if (command.action === 'refresh-query') {
          const spec = observed.get(command.key);
          if (!spec?.courseTable || spec.method !== 'POST') throw new Error('尚未观察到课程查询接口。');
          const size = Number(command.pageSize);
          if (!Number.isInteger(size) || size < 1 || size > 200) throw new Error('页大小必须在 1–200。');
          const parameters = {...spec.values, pageNumber: '1', pageSize: String(size)};
          const response = await context.request.post(spec.url, {form: parameters, timeout: 30000, maxRedirects: 0});
          if (!response.ok()) throw new Error('课程查询失败。');
          const table = tableAt(await response.json(), spec.tablePath);
          if (!Array.isArray(table?.rows)) throw new Error('课程数据结构不符。');
          spec.values = parameters;
          spec.total = tableTotal(table);
          spec.firstCount = table.rows.length;
          spec.tableKeys = Object.keys(table);
          spec.firstRows = sanitize(table.rows.slice(0, 5));
          saveObserved();
          result = {total: spec.total, count: spec.firstCount};
        } else throw new Error('未知指令。');
        writeJson('command-result.json', { ok: true, ...result });
      }
    } catch (error) {
      writeJson('command-result.json', { ok: false, error: error.message.split('\n')[0].slice(0, 300) });
      console.log('操作未完成，请查看 command-result.json。');
    }
    await delay(1000);
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
