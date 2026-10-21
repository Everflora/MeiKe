'use strict';
// Filled by finalize.mjs, scoped by both site path and release content hash.
const RELEASE = __MEIKE_RELEASE__;
const PREFIX = `meike-pwa:${new URL(self.registration.scope).pathname}:`;
const CACHE = PREFIX + RELEASE.version;
const assets = new Map(RELEASE.files.map(file => [new URL(file.url, self.registration.scope).href, file.sha256]));
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  const queue = [...assets.entries()];
  try {
    await Promise.all(Array.from({length: 4}, async () => {
      while (queue.length) {
        const [url, expected] = queue.shift();
        const response = await fetch(url, {cache: 'reload', credentials: 'same-origin'});
        if (!response.ok) throw new Error('Resource unavailable');
        const hash = await crypto.subtle.digest('SHA-256', await response.clone().arrayBuffer());
        const actual = [...new Uint8Array(hash)].map(v => v.toString(16).padStart(2, '0')).join('');
        if (actual !== expected) throw new Error('Mixed release; retry later');
        await cache.put(url, response);
      }
    }));
  } catch (error) {
    // Do not activate a partial release or remove the previous working cache.
    await caches.delete(CACHE);
    throw error;
  }
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  await Promise.all((await caches.keys()).filter(key => key.startsWith(PREFIX) && key !== CACHE).map(key => caches.delete(key)));
  await self.clients.claim();
  for (const client of await self.clients.matchAll()) client.postMessage({type: 'OFFLINE_READY'});
})()));
self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  const scope = new URL(self.registration.scope);
  if (request.method !== 'GET' || url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  // Only explicit, versioned build resources are cached. Never cache API data.
  if (request.mode === 'navigate') {
    // Keep an existing tab on one coherent release while a new worker waits.
    event.respondWith(caches.open(CACHE).then(cache => cache.match(assets.has(url.href) ? url.href : new URL('index.html', scope).href)).then(cached => cached || fetch(request)));
  } else if (assets.has(url.href)) {
    event.respondWith(caches.open(CACHE).then(cache => cache.match(request)).then(cached => cached || fetch(request)));
  }
});
