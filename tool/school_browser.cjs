// Inspect only the authorized phone's campus WebView through local ADB.
// Never request cookies, login form values, request headers or storage.
const fs = require('node:fs');
const path = require('node:path');
class SchoolBrowser {
  constructor(socket) {
    this.socket = socket;
    this.next = 0;
    this.pending = new Map();
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
    });
  }
  static async connect() {
    const pages = await (await fetch('http://127.0.0.1:9222/json/list')).json();
    const candidates = pages.filter(page => {
      try {
        const url = new URL(page.url);
        return url.protocol === 'https:' && /(^|\.)seu\.edu\.cn$/.test(url.hostname);
      } catch { return false; }
    });
    if (candidates.length !== 1) throw new Error('请在梅课中打开唯一的学校课表网页。');
    const socket = new WebSocket(candidates[0].webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    return new SchoolBrowser(socket);
  }
  command(method, params = {}, milliseconds = 30000) {
    const id = ++this.next;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`网页操作超时：${method}`));
      }, milliseconds);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }
  async evaluate(expression, milliseconds) {
    const result = await this.command('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true,
    }, milliseconds);
    if (result.exceptionDetails) throw new Error('学校网页脚本执行失败。');
    return result.result.value;
  }
  close() { this.socket.close(); }
}
module.exports = { SchoolBrowser };
if (require.main === module) {
  (async () => {
    const browser = await SchoolBrowser.connect();
    try {
      const mode = process.argv[2] || 'status';
      if (mode === 'open') {
        await browser.command('Page.navigate', {
          url: 'https://ehall.seu.edu.cn/jwapp/sys/kcbcx/*default/index.do#/qxkcb',
        });
        console.log('已打开全校课表入口。');
      } else if (mode === 'status') {
        console.log(JSON.stringify(await browser.evaluate(`({
          origin: location.origin, path: location.pathname, route: location.hash,
          scripts: [...document.scripts].map(s => { try { const u = new URL(s.src); return u.origin === location.origin ? u.pathname : null; } catch { return null; } }).filter(Boolean)
        })`), null, 2));
      } else if (mode === 'sources') {
        const result = await browser.evaluate(`(async () => {
          const paths = [...new Set([...document.scripts].map(s => {
            try { const u = new URL(s.src); return u.origin === location.origin && u.pathname.includes('/kcbcx/') ? u.pathname : null; } catch { return null; }
          }).filter(Boolean))];
          const sources = [];
          for (const resource of paths) {
            const response = await fetch(resource, { credentials: 'same-origin' });
            if (response.ok) sources.push({ path: resource, source: await response.text() });
          }
          return sources;
        })()`);
        const folder = path.join(__dirname, '../.local/school-analysis/sources');
        fs.mkdirSync(folder, { recursive: true });
        for (const [index, asset] of result.entries()) fs.writeFileSync(path.join(folder, `${index}-${path.basename(asset.path)}`), asset.source);
        console.log(`已保存 ${result.length} 个全校课表脚本。`);
      } else throw new Error('未知操作。');
    } finally { browser.close(); }
  })().catch(error => { console.error(error.message); process.exitCode = 1; });
}
