// Service worker: keeps the app usable with no signal on the course.
// - Static assets and the course catalog: cache first.
// - Page navigations: network first, fall back to the last cached copy, then to /offline.
// - Supabase and edge function calls are never cached (scores queue in the page itself, see lib/scoreQueue.ts).
const VERSION = "v1";
const STATIC = `albatross-static-${VERSION}`;
const PAGES = `albatross-pages-${VERSION}`;

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(PAGES).then((c) => c.addAll(["/offline", "/courses.json", "/manifest.webmanifest"])).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => ![STATIC, PAGES].includes(k)).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== self.location.origin) return;

  if (url.pathname.startsWith("/_next/static/") || /\.(png|svg|ico|webmanifest)$/.test(url.pathname) || url.pathname === "/courses.json") {
    e.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      const copy = res.clone(); caches.open(STATIC).then((c) => c.put(req, copy)); return res;
    })));
    return;
  }
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req).then((res) => { const copy = res.clone(); caches.open(PAGES).then((c) => c.put(req, copy)); return res; })
        .catch(() => caches.match(req).then((hit) => hit || caches.match("/offline")))
    );
  }
});
