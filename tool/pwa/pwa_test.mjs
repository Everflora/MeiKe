import assert from 'node:assert/strict';
import {createHash, webcrypto} from 'node:crypto';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import vm from 'node:vm';
import {finalize} from './finalize.mjs';

const scope = 'https://example.test/MeiKe-web/';
const key = `meike-pwa:/MeiKe-web/:`;
const template = await readFile(new URL('./sw-template.js', import.meta.url), 'utf8');
const digest = value => createHash('sha256').update(value).digest('hex');
const release = {version: 'new', files: [
  {url: 'index.html', sha256: digest('APP')},
  {url: 'privacy.html', sha256: digest('PRIVACY')},
]};

function worker({broken = false} = {}) {
  const listeners = new Map(), buckets = new Map(), claimed = [];
  const id = request => typeof request === 'string' ? request : request.url;
  const caches = {
    async open(name) {
      if (!buckets.has(name)) buckets.set(name, new Map());
      const bucket = buckets.get(name);
      return {async put(request, response) {bucket.set(id(request), response.clone());},
        async match(request) {return bucket.get(id(request))?.clone();}};
    },
    async keys() {return [...buckets.keys()];},
    async delete(name) {return buckets.delete(name);},
  };
  const self = {registration: {scope}, clients: {
    async claim() {claimed.push(true);},
    async matchAll() {return [];},
  }, addEventListener(name, callback) {listeners.set(name, callback);}, skipWaiting() {}};
  const fetch = async request => new Response(id(request).endsWith('privacy.html') ? (broken ? 'WRONG' : 'PRIVACY') : 'APP');
  vm.runInNewContext(template.replace('__MEIKE_RELEASE__', JSON.stringify(release)), {self, caches, fetch, crypto: webcrypto, URL, Uint8Array, console});
  async function event(name) {
    let promise;
    listeners.get(name)({waitUntil(value) {promise = value;}});
    await promise;
  }
  return {caches, buckets, listeners, claimed, event};
}

test('partial/mixed release install fails without deleting the previous offline app', async () => {
  const app = worker({broken: true});
  await app.caches.open(key + 'old');
  await assert.rejects(app.event('install'), /Mixed release/);
  assert.deepEqual(await app.caches.keys(), [key + 'old']);
  assert.equal(app.claimed.length, 0);
});

test('activation removes only this site previous build caches', async () => {
  const app = worker();
  await app.caches.open(key + 'old');
  await app.caches.open('meike-pwa:/Other-project/:old');
  await app.event('install');
  await app.event('activate');
  assert.deepEqual((await app.caches.keys()).sort(), [key + 'new', 'meike-pwa:/Other-project/:old'].sort());
  assert.equal(app.claimed.length, 1);
});

test('offline navigation retains one release and privacy page; API and foreign requests bypass cache', async () => {
  const app = worker();
  await app.event('install');
  async function dispatch(request) {
    let response;
    app.listeners.get('fetch')({request, respondWith(value) {response = value;}});
    return await response;
  }
  const response = await dispatch({url: scope + '?from=qr', method: 'GET', mode: 'navigate'});
  assert.equal(await response.text(), 'APP');
  const privacy = await dispatch({url: scope + 'privacy.html', method: 'GET', mode: 'navigate'});
  assert.equal(await privacy.text(), 'PRIVACY');
  for (const request of [
    {url: scope + 'v1/profile', method: 'GET'},
    {url: scope + 'index.html', method: 'POST'},
    {url: 'https://api.example.test/v1/messages', method: 'GET'},
    {url: 'https://example.test/Other-project/index.html', method: 'GET'},
  ]) assert.equal(await dispatch(request), undefined);
});

test('release manifest is deterministic, includes offline essentials and strips debug sources', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'meike-pwa-'));
  try {
    for (const name of ['index.html', 'main.dart.js', 'manifest.json', 'assets/web-fonts/NotoSansSC.ttf', 'canvaskit/canvaskit.wasm', 'private.js.map', 'canvaskit/canvaskit.js.symbols', 'canvaskit/skwasm.wasm', '.nojekyll']) {
      await mkdir(path.dirname(path.join(dir, name)), {recursive: true});
      await writeFile(path.join(dir, name), name);
    }
    const first = await finalize(dir), second = await finalize(dir);
    assert.equal(first.version, second.version);
    assert.equal(first.files.length, 5);
    assert(first.files.every(file => !file.url.endsWith('.map') && !file.url.startsWith('canvaskit/skwasm')));
    await assert.rejects(readFile(path.join(dir, 'private.js.map')), /ENOENT/);
    const sw = await readFile(path.join(dir, 'sw.js'), 'utf8');
    assert(!sw.includes('__MEIKE_RELEASE__'));
  } finally {await rm(dir, {recursive: true, force: true});}
});
