/* PICKLE HUB service worker v3
   - ナビゲーションはネットワーク優先、失敗時のみ保存済み index.html を表示
   - 同一オリジンの静的ファイルはキャッシュ優先
   - アイコン等の未配置ファイルを install 時に要求しない
   - Supabase / CDN / Analytics など他オリジン通信はキャッシュしない
*/
const CACHE_NAME = "pickle-hub-v3";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith("pickle-hub-") && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  let url;
  try { url = new URL(request.url); } catch (_) { return; }
  if (url.origin !== self.location.origin) return;

  const isNavigation = request.mode === "navigate" ||
    url.pathname.endsWith("/") ||
    url.pathname.endsWith("/index.html");

  if (isNavigation) {
    event.respondWith(
      fetch(request).then((response) => {
        if (response && response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME)
            .then((cache) => cache.put("./index.html", copy))
            .catch(() => {});
        }
        return response;
      }).catch(() =>
        caches.match("./index.html", { ignoreSearch: true })
          .then((cached) => cached || caches.match(request, { ignoreSearch: true }))
      )
    );
    return;
  }

  // Service Worker自身の更新確認はキャッシュしない
  if (url.pathname.endsWith("/sw.js")) return;

  event.respondWith(
    caches.match(request, { ignoreSearch: true }).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (response && response.ok && response.type === "basic") {
          const copy = response.clone();
          caches.open(CACHE_NAME)
            .then((cache) => cache.put(request, copy))
            .catch(() => {});
        }
        return response;
      });
    })
  );
});
