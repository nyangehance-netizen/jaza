import { all, one, run } from '../db.js';
import { requireUser, userFromToken } from '../lib/auth.js';
import { HttpError, notFound, oneOf } from '../lib/http.js';
import { openStream } from '../lib/events.js';
import { config, PAYMENT_METHODS } from '../config.js';
import { provider, settle } from '../payments/index.js';

export default (r) => {
  // ---------- Admin: approve stations after checking their EWURA licence ----------
  r.get('/api/admin/stations', requireUser('admin'), ({ query }) => {
    const status = query.status || 'pending';
    return all(`SELECT s.*, u.name AS owner_name, u.phone AS owner_phone FROM stations s JOIN users u ON u.id = s.owner_id
                WHERE s.status = ? ORDER BY s.id DESC`, status);
  });
  r.post('/api/admin/stations/:id/status', requireUser('admin'), ({ params, body }) => {
    if (!one('SELECT id FROM stations WHERE id = ?', params.id)) throw notFound('Station not found.');
    run('UPDATE stations SET status = ? WHERE id = ?', oneOf(body.status, 'Status', ['pending', 'approved', 'suspended']), params.id);
    return one('SELECT * FROM stations WHERE id = ?', params.id);
  });
  r.get('/api/admin/summary', requireUser('admin'), () => ({
    stations: all('SELECT status, COUNT(*) AS n FROM stations GROUP BY status'),
    orders: all('SELECT status, COUNT(*) AS n FROM orders GROUP BY status'),
    gmv_delivered: one("SELECT COALESCE(SUM(total),0) AS v FROM orders WHERE status = 'delivered'").v,
  }));

  // ---------- Payments ----------
  r.post('/api/payments/callback/:provider', ({ params, body, req }) => {
    const p = provider(params.provider);
    const { reference, status, raw } = p.parseCallback(body, req.headers, req.rawBody);
    settle(reference, status, raw);
    return { ok: true };
  });

  // Test mode only: approve or decline a pending payment by hand.
  r.post('/api/payments/test/:reference/:result', requireUser(), ({ params, user }) => {
    if (config.paymentProvider !== 'test') throw new HttpError(404, 'Not found.');
    const pay = one('SELECT p.*, o.client_id FROM payments p JOIN orders o ON o.id = p.order_id WHERE p.reference = ?', params.reference);
    if (!pay) throw notFound('Payment not found.');
    if (pay.client_id !== user.id && user.role !== 'admin') throw new HttpError(403, 'Not your payment.');
    if (PAYMENT_METHODS[pay.method].kind === 'bank') throw new HttpError(409, 'Bank transfers are confirmed by the station.');
    settle(params.reference, params.result === 'approve' ? 'paid' : 'failed', { manual: true });
    return { ok: true };
  });

  // ---------- Live updates ----------
  r.get('/api/events', ({ req, res, query }) => {
    const h = req.headers.authorization || '';
    const user = userFromToken(query.token || (h.startsWith('Bearer ') ? h.slice(7) : ''));
    if (!user) throw new HttpError(401, 'Please sign in.');
    openStream(req, res, user);
    return undefined; // stream stays open
  });

  r.get('/api/health', () => ({ ok: true, time: new Date().toISOString(), payments: config.paymentProvider }));
};
