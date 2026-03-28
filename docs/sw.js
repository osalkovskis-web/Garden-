// Service Worker — caches app shell for offline use
const CACHE = "darzs-v1";
const SHELL = ["/Garden-/", "/Garden-/index.html", "/Garden-/manifest.json", "/Garden-/icon.svg"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener("fetch", e => {
  // API calls — network only, no cache
  if (e.request.url.includes("/api/")) return;
  e.respondWith(
    caches.match(e.request).then(r => r || fetch(e.request).catch(() =>
      caches.match("/Garden-/index.html")
    ))
  );
});
