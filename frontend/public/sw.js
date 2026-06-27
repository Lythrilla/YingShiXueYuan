// Minimal service worker — required for PWA installability.
// Network-first; falls back to cache so the app shell can launch offline.
const CACHE = 'yingshi-v1'
const SHELL = ['/', '/index.html', '/manifest.webmanifest', '/icon-192.png', '/icon-512.png']

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).catch(() => undefined))
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))),
  )
  self.clients.claim()
})

self.addEventListener('fetch', (event) => {
  const { request } = event
  if (request.method !== 'GET') return
  // Never cache API calls — availability/bookings must stay fresh.
  if (new URL(request.url).pathname.startsWith('/api/')) return
  event.respondWith(
    fetch(request)
      .then((res) => {
        const copy = res.clone()
        caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => undefined)
        return res
      })
      .catch(() =>
        caches.match(request).then((cached) => cached || caches.match('/index.html')),
      ),
  )
})
