import { createServer } from 'node:http';
import { config } from './config.js';
import { Router, HttpError, readJson, send, cors, serveStatic } from './lib/http.js';
import auth from './routes/auth.js';
import stations from './routes/stations.js';
import orders from './routes/orders.js';
import admin from './routes/admin.js';

const router = new Router();
for (const mount of [auth, stations, orders, admin]) mount(router);

export function createApp() {
  return createServer(async (req, res) => {
    cors(req, res);
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
    const url = new URL(req.url, 'http://x');
    try {
      if (!url.pathname.startsWith('/api/')) {
        // Station dashboard (static files). Unknown paths fall back to the app shell.
        if (req.method === 'GET' && ((await serveStatic(res, config.dashboardDir, url.pathname)) || (await serveStatic(res, config.dashboardDir, '/index.html')))) return;
        throw new HttpError(404, 'Not found.');
      }
      const m = router.match(req.method, url.pathname);
      if (!m) throw new HttpError(404, 'Not found.');
      const ctx = { req, res, params: m.params, query: Object.fromEntries(url.searchParams), body: await readJson(req) };
      let out;
      for (const h of m.handlers) out = await h(ctx);
      if (out !== undefined) send(res, 200, out);
    } catch (e) {
      if (e instanceof HttpError) return send(res, e.status, { error: e.message, details: e.details });
      if (String(e.message).includes('UNIQUE constraint')) return send(res, 409, { error: 'That already exists.' });
      console.error(e);
      send(res, 500, { error: 'Something went wrong on our side. Please try again.' });
    }
  });
}
