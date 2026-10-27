// Cloudflare Worker: serves a friendly page when the incubator's tunnel is
// down. Route it on "syncubator.in/" ONLY (the root document), never on the
// API paths -- /status is polled every second per viewer and would exhaust
// the free 100k requests/day quota within hours.
//
// When the Pi is unreachable Cloudflare answers 530 (tunnel not connected)
// or 502 (cloudflared up, nginx down); both are >= 500 and land here.

const OFFLINE_PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="30">
<title>Syncubator</title>
<style>
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font-family: system-ui, sans-serif; background: #f4f6f8; color: #1f2933; }
  main { text-align: center; padding: 2rem; max-width: 28rem; }
  h1 { font-size: 1.6rem; margin: 0 0 .5rem; }
  p  { margin: .4rem 0; color: #52606d; }
  a  { color: #2563eb; }
  .dot { display: inline-block; width: .6rem; height: .6rem; border-radius: 50%;
         background: #e11d48; margin-right: .4rem; }
</style>
</head>
<body>
<main>
  <h1><span class="dot"></span>Syncubator is offline</h1>
  <p>The incubator controller is not reachable at the moment.</p>
  <p>This page retries automatically every 30 seconds.</p>
  <p><a href="https://syncubator.godaddysites.com">About the project</a></p>
</main>
</body>
</html>`;

export default {
  async fetch(request) {
    try {
      const res = await fetch(request);
      if (res.status >= 500) throw new Error("origin " + res.status);
      return res;
    } catch (e) {
      return new Response(OFFLINE_PAGE, {
        status: 503,
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
          "retry-after": "30",
        },
      });
    }
  },
};
