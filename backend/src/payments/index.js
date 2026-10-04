// Payment service: creates payment records, talks to the configured provider,
// and settles orders when a payment succeeds or fails.
import { randomBytes } from 'node:crypto';
import { config, PAYMENT_METHODS } from '../config.js';
import { one, run, tx } from '../db.js';
import { orderChanged } from '../lib/events.js';
import { testProvider } from './test-provider.js';
import { templateProvider } from './provider-template.js';

const providers = { test: testProvider, template: templateProvider };
// Register real adapters here, e.g.: import { selcomProvider } from './selcom.js'; providers.selcom = selcomProvider;

export function provider(name = config.paymentProvider) {
  const p = providers[name];
  if (!p) throw new Error(`Unknown PAYMENT_PROVIDER "${name}".`);
  return p;
}

const timers = new Set();

/** Create a payment for an order. Bank transfers are verified by the station instead. */
export async function startPayment(order, phone) {
  const reference = `${order.code}-${randomBytes(3).toString('hex').toUpperCase()}`;
  const kind = PAYMENT_METHODS[order.payment_method].kind;
  const p = kind === 'bank' ? { name: 'manual' } : provider();
  const info = run(
    'INSERT INTO payments (order_id, provider, method, reference, amount, phone) VALUES (?,?,?,?,?,?)',
    order.id, p.name, order.payment_method, reference, order.total, phone,
  );
  const payment = one('SELECT * FROM payments WHERE id = ?', info.lastInsertRowid);

  if (kind === 'bank') {
    const acc = one('SELECT account FROM station_payment_methods WHERE station_id = ? AND method = ?', order.station_id, 'bank');
    return { reference, status: 'pending', kind, instructions: `Transfer ${order.total.toLocaleString('en-US')} TZS to ${acc?.account || 'the station account'} with reference ${order.code}. The station confirms once the money arrives.` };
  }

  try {
    const r = await p.initiate({ payment, order, method: order.payment_method, phone });
    run('UPDATE payments SET provider_ref = ?, updated_at = datetime(\'now\') WHERE id = ?', r.providerRef || null, payment.id);
    if (p.name === 'test' && r.autoApproveMs > 0) {
      const t = setTimeout(() => { timers.delete(t); settle(reference, 'paid', { auto: true }); }, r.autoApproveMs);
      t.unref?.();
      timers.add(t);
    }
    return { reference, status: 'pending', kind, instructions: r.instructions, checkoutUrl: r.checkoutUrl || null, testMode: p.name === 'test' };
  } catch (e) {
    settle(reference, 'failed', { error: e.message });
    throw e;
  }
}

/** Apply a payment result (from a webhook, test approval or auto-approve). Idempotent. */
export function settle(reference, status, raw = {}) {
  const changed = tx(() => {
    const pay = one('SELECT * FROM payments WHERE reference = ?', reference);
    if (!pay || pay.status !== 'pending') return null;
    run("UPDATE payments SET status = ?, raw = ?, updated_at = datetime('now') WHERE id = ?", status, JSON.stringify(raw), pay.id);
    const order = one('SELECT * FROM orders WHERE id = ?', pay.order_id);
    if (status === 'paid' && order.status === 'awaiting_payment') {
      run("UPDATE orders SET payment_status = 'paid', status = 'placed', updated_at = datetime('now') WHERE id = ?", order.id);
      run("INSERT INTO order_events (order_id, status, note) VALUES (?, 'placed', 'Payment received')", order.id);
    } else if (status === 'failed' && order.status === 'awaiting_payment') {
      run("UPDATE orders SET payment_status = 'failed', status = 'cancelled', cancel_reason = 'Payment failed', updated_at = datetime('now') WHERE id = ?", order.id);
      run("INSERT INTO order_events (order_id, status, note) VALUES (?, 'cancelled', 'Payment failed')", order.id);
    } else if (status === 'paid') {
      // Paid after the order was already closed: mark for refund.
      run("UPDATE orders SET payment_status = 'paid' WHERE id = ?", order.id);
    }
    return one('SELECT * FROM orders WHERE id = ?', order.id);
  });
  if (changed) {
    orderChanged(changed);
    if (status === 'paid' && ['cancelled', 'rejected'].includes(changed.status)) refundOrder(changed).catch(() => {});
  }
  return changed;
}

/** Refund whatever was paid on an order. */
export async function refundOrder(order) {
  const pay = one("SELECT * FROM payments WHERE order_id = ? AND status = 'paid' ORDER BY id DESC", order.id);
  if (!pay) return false;
  if (pay.provider !== 'manual') await provider(pay.provider).refund(pay);
  run("UPDATE payments SET status = 'refunded', updated_at = datetime('now') WHERE id = ?", pay.id);
  run("UPDATE orders SET payment_status = 'refunded', updated_at = datetime('now') WHERE id = ?", order.id);
  return true;
}

export function clearPaymentTimers() {
  for (const t of timers) clearTimeout(t);
  timers.clear();
}
