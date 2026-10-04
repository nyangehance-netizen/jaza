// End-to-end test of the whole order flow against a real server and in-memory database.
process.env.NODE_ENV = 'test';
process.env.TEST_AUTO_APPROVE_MS = '0';
process.env.PORT = '0';

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

const { createApp } = await import('../src/app.js');
const { run } = await import('../src/db.js');
const { hashPassword } = await import('../src/lib/auth.js');
const { clearPaymentTimers } = await import('../src/payments/index.js');

let server, base;
before(async () => {
  run("INSERT INTO users (name, phone, password_hash, role) VALUES ('Admin','255700000000',?,'admin')", hashPassword('admin123'));
  server = createApp().listen(0);
  await new Promise((r) => server.once('listening', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => { clearPaymentTimers(); server.close(); });

async function api(method, path, body, token) {
  const res = await fetch(base + path, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  return { status: res.status, data };
}
const ok = async (...a) => { const r = await api(...a); assert.ok(r.status < 300, `${a[0]} ${a[1]} → ${r.status} ${JSON.stringify(r.data)}`); return r.data; };

test('client orders fuel, station accepts, rider delivers with the code', async () => {
  // Station signs up and registers
  const st = await ok('POST', '/api/auth/register', { name: 'Rehema', phone: '0713 000 001', password: 'secret1', role: 'station' });
  const T = st.token;
  let s = await ok('POST', '/api/stations', { name: 'Mwenge Energies', license_no: 'EWURA/1', phone: '0713000001', address: 'Mwenge', lat: -6.768, lng: 39.226, offers_tanker: true }, T);
  assert.equal(s.status, 'pending');

  // Admin approves
  const admin = await ok('POST', '/api/auth/login', { phone: '0700000000', password: 'admin123' });
  await ok('POST', `/api/admin/stations/${s.id}/status`, { status: 'approved' }, admin.token);

  // Station sets up products, payments and a rider
  s = await ok('POST', '/api/station/products', { name: 'Petrol', fuel_type: 'petrol', price_per_litre: 2900, stock_litres: 1000 }, T);
  const petrol = s.products[0];
  await ok('PUT', '/api/station/payment-methods/mpesa', { enabled: true, account: 'Lipa 551204' }, T);
  assert.equal((await api('PUT', '/api/station/payment-methods/bank', { enabled: true }, T)).status, 400, 'bank needs an account');
  await ok('PUT', '/api/station/payment-methods/bank', { enabled: true, account: 'CRDB 0150' }, T);
  await ok('POST', '/api/station/riders', { name: 'Juma', phone: '0754000011', password: 'rider123', vehicle: 'boda', plate: 'mc 712 cvb' }, T);

  // Rider signs in and goes online
  const rider = await ok('POST', '/api/auth/login', { phone: '0754000011', password: 'rider123' });
  const R = rider.token;
  await ok('POST', '/api/rider/status', { online: true, lat: -6.768, lng: 39.226 }, R);

  // Client finds stations
  const c = await ok('POST', '/api/auth/register', { name: 'Asha', phone: '0754123456', password: 'client1' });
  const C = c.token;
  const near = await ok('GET', '/api/stations/nearby?lat=-6.765&lng=39.248&fuel=petrol&litres=15&delivery=boda', null, C);
  const opt = near.stations[0];
  assert.ok(opt.available, JSON.stringify(opt));
  assert.equal(opt.quote.fuelCost, 2900 * 15);

  // Client orders and pays (test mode, approved manually)
  const placed = await ok('POST', '/api/orders', {
    station_id: opt.station_id, product_id: opt.product_id, litres: 15, delivery_method: 'boda',
    lat: -6.765, lng: 39.248, landmark: 'Shoppers Plaza', plate: 't 482 dkp', vehicle_type: 'Car', payment_method: 'mpesa',
  }, C);
  const o = placed.order;
  assert.equal(o.status, 'awaiting_payment');
  assert.match(o.otp, /^\d{4}$/);
  assert.equal((await api('POST', `/api/orders/${o.id}/accept`, {}, T)).status, 409, 'cannot accept unpaid');
  await ok('POST', `/api/payments/test/${placed.payment.reference}/approve`, {}, C);
  assert.equal((await ok('GET', `/api/orders/${o.id}`, null, C)).status, 'placed');

  // A second active order is refused
  assert.equal((await api('POST', '/api/orders', { station_id: opt.station_id, product_id: opt.product_id, litres: 10, delivery_method: 'boda', lat: -6.765, lng: 39.248, plate: 'T1', payment_method: 'mpesa' }, C)).status, 409);

  // Station sees it without the code, accepts, stock drops
  const stOrders = await ok('GET', '/api/station/orders', null, T);
  assert.equal(stOrders[0].otp, undefined);
  await ok('POST', `/api/orders/${o.id}/accept`, {}, T);
  assert.equal((await ok('GET', '/api/station', null, T)).products[0].stock_litres, 985);

  // Rider takes it and moves through the steps
  const jobs = await ok('GET', '/api/rider/jobs', null, R);
  assert.equal(jobs.length, 1);
  await ok('POST', `/api/orders/${o.id}/take`, {}, R);
  for (const expected of ['picked_up', 'on_the_way', 'arrived']) assert.equal((await ok('POST', `/api/orders/${o.id}/advance`, {}, R)).status, expected);

  // Wrong code is refused, right code delivers
  assert.equal((await api('POST', `/api/orders/${o.id}/deliver`, { otp: '0000' }, R)).status, 400);
  const delivered = await ok('POST', `/api/orders/${o.id}/deliver`, { otp: o.otp }, R);
  assert.equal(delivered.status, 'delivered');

  const me = await ok('GET', '/api/rider', null, R);
  assert.equal(me.today.trips, 1);
  assert.ok(me.today.earned > 0);
  const stats = await ok('GET', '/api/station/stats', null, T);
  assert.equal(stats.litres, 15);

  // Bank transfer order: station must confirm, then declines → refunded
  const bank = await ok('POST', '/api/orders', {
    station_id: opt.station_id, product_id: opt.product_id, litres: 10, delivery_method: 'boda',
    lat: -6.765, lng: 39.248, plate: 'T 482 DKP', payment_method: 'bank',
  }, C);
  assert.equal(bank.order.status, 'placed');
  assert.equal(bank.order.payment_status, 'pending');
  await ok('POST', `/api/orders/${bank.order.id}/confirm-transfer`, {}, T);
  const rej = await ok('POST', `/api/orders/${bank.order.id}/reject`, { reason: 'Pump maintenance' }, T);
  assert.equal(rej.status, 'rejected');
  assert.equal(rej.payment_status, 'refunded');

  // Other clients cannot see someone else's order
  const other = await ok('POST', '/api/auth/register', { name: 'Peter', phone: '0688210555', password: 'peter12' });
  assert.equal((await api('GET', `/api/orders/${o.id}`, null, other.token)).status, 403);
});

test('rejects bad input clearly', async () => {
  const r = await api('POST', '/api/auth/register', { name: 'X', phone: '123', password: 'abcdef' });
  assert.equal(r.status, 400);
  assert.match(r.data.error, /Name|phone/i);
  assert.equal((await api('GET', '/api/me')).status, 401);
});
