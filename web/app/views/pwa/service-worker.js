// Offline reading for the public plane, and nothing else.
//
// The rule this file exists to enforce: **never cache anything behind
// authentication.** SECURITY.md is explicit that document metadata — that
// someone holds a Nepali passport expiring in March and is renewing it from
// Qatar — is stored in the clear and is sensitive for a migrant. Writing a
// dashboard into CacheStorage would put exactly that on disk, where it survives
// signing out and is readable by anyone who later picks up the device. For an
// application whose pitch is that the server has never seen your passport, that
// would be an own goal.
//
// So this is an allowlist, not a denylist. A path that is not provably public
// is never stored, and a new private route added later is excluded by default
// rather than by somebody remembering to exclude it.
//
// What it buys: the playbooks stay readable on a plane, in a queue at a
// consulate, or on the metered roaming data the target user is actually on.

const VERSION = "v1"
const CACHE = `renewals-public-${VERSION}`

// Public, crawlable, and identical for every visitor.
const PUBLIC_PATHS = [
  /^\/$/,
  /^\/playbooks(\/|$)/,
  /^\/when-to-start$/,
  /^\/icon\.(png|svg)$/,
  /^\/assets\//
]

const isPublic = (url) => PUBLIC_PATHS.some((pattern) => pattern.test(url.pathname))

// A response carrying a session, or marked private, is not ours to keep even if
// the path looked public — a redirect to the sign-in page would otherwise be
// cached as though it were the page itself.
const isCacheable = (response) =>
  response &&
  response.status === 200 &&
  response.type === "basic" &&
  !response.headers.get("set-cookie") &&
  !(response.headers.get("cache-control") || "").includes("private")

self.addEventListener("install", (event) => {
  // The stylesheet is fingerprinted, so it is picked up on first navigation
  // rather than guessed at here.
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(["/playbooks"])).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  // The query string carries the whole question on the calculator, so an
  // answered result is a different page. Not cached: the set is unbounded.
  if (url.search) return

  if (!isPublic(url)) return

  // Stale-while-revalidate. A playbook that is a day out of date and readable
  // beats a spinner, and the page itself always shows when it was last verified
  // — so a stale read is visibly stale rather than silently wrong.
  event.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(request)

      const network = fetch(request)
        .then((response) => {
          if (isCacheable(response)) cache.put(request, response.clone())
          return response
        })
        .catch(() => cached)

      return cached || network
    })
  )
})
