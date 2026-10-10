const {test,before,after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const local = createRequire(path.resolve(__dirname,'../.local/crawler/package.json'));
const {chromium} = local('playwright');
const source = fs.readFileSync(path.resolve(__dirname,'../assets/labor_news.js'),'utf8');
const script = source.replaceAll('__MEIKE_LABOR_NONCE__', JSON.stringify('demo'));
let browser;
before(async () => { browser = await chromium.launch({headless:true, executablePath:
  process.env.MEIKE_BROWSER_EXECUTABLE || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'}); });
after(async () => { await browser?.close(); });
function row(id,offset=0) {
  const cells = Array(15+offset).fill('');
  cells[offset]='1'; cells[1+offset]='示例项目'; cells[2+offset]='示例劳动课';
  cells[3+offset]='校园劳动'; cells[6+offset]='<span class="limit-line">九龙湖 教室甲</span>';
  cells[7+offset]='2026-10-12 10:00'; cells[8+offset]='明天'; cells[9+offset]='已满';
  cells[14+offset]='示例教师';
  cells[0]+=`<td-data data-name="SJItemID" data-value="demo"></td-data><td-data data-name="SJItemKaiKeID" data-value="${id}"></td-data><td-data data-name="StudentId" data-value="PRIVATE-NOT-EXPORTED"></td-data>`;
  return '<tr class="c--tr">'+cells.map(v=>'<td>'+v+'</td>').join('')+'</tr>';
}
const table = rows => '<table id="c_app_page_index_XuanKe_table"><tbody>'+rows+'</tbody></table>';
async function run(url,html,visible=html) {
  const page = await browser.newPage(); const requests=[];
  await page.route('**/*',route => { requests.push(route.request().method()); return route.fulfill({body:html, contentType:'text/html'}); });
  let resolve; const received=new Promise(r=>resolve=r);
  await page.exposeFunction('newsResult',value=>resolve(JSON.parse(value)));
  await page.goto(url); await page.setContent(visible);
  await page.evaluate(() => { window.MeiKeLaborNews={postMessage:window.newsResult}; });
  await page.evaluate(script);
  const result = await Promise.race([received,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Reader timeout')),3000))]);
  await page.close(); return {result,requests};
}
test('读取完整 HTML 中两种列偏移，页面分页不丢课程，仅返回课程字段', async () => {
  const {result,requests}=await run('https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index',table(row('a')+row('b',1)),table(row('a')));
  assert.equal(result.kind,'courses'); assert.equal(result.rows.length,2);
  assert.deepEqual(result.rows.map(r=>r.offeringId),['a','b']);
  assert.equal(result.rows[1].teacher,'示例教师'); assert.equal(result.rows[0].location,'九龙湖 教室甲');
  assert.equal(result.rows[0].enrollment,'已满');
  assert.ok(!JSON.stringify(result).includes('PRIVATE-NOT-EXPORTED'));
  assert.ok(requests.every(m=>m==='GET'));
});
test('登录失效及结构变化返回错误；合法空表返回空列表', async () => {
  const login=await run('https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index','<form>统一身份认证</form>');
  assert.equal(login.result.kind,'error'); assert.equal(login.result.rows,undefined);
  const changed=await run('https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index',table('<tr class="c-tr"><td>bad</td></tr>'));
  assert.equal(changed.result.kind,'error');
  const missingClass=await run('https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index',table(row('a').replace('class="c--tr"','')));
  assert.equal(missingClass.result.kind,'error');
  const empty=await run('https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index',table(''));
  assert.deepEqual(empty.result.rows,[]);
});
test('非学校页面不发起读取请求，VPN 路径保留', async () => {
  const denied=await run('https://example.com/SJItemKaiKe/XuanKe/Index',table(row('a')));
  assert.equal(denied.result.kind,'error'); assert.equal(denied.requests.length,1);
  const vpn=await run('https://webvpn.seu.edu.cn/proxy/SJItemKaiKe/XuanKe/Index',table(row('a')));
  assert.equal(vpn.result.kind,'courses');
});
