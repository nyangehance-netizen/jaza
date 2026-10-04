import { one, all, run, tx } from '../db.js';
import { config, PAYMENT_METHODS } from '../config.js';
import { requireUser, hashPassword } from '../lib/auth.js';
import { bad, conflict, notFound, forbidden, str, numIn, oneOf, phone } from '../lib/http.js';
import { roadKm, priceOrder } from '../lib/geo.js';
import { orderView } from './orders.js';

const ACTIVE = ['placed', 'accepted', 'assigned', 'picked_up', 'on_the_way', 'arrived'];

export function stationOrFail(user) {
  if (!user.station_id) throw bad('Register your station first.');
  return one('SELECT * FROM stations WHERE id = ?', user.station_id);
}

function checkPriceCap(fuelType, price) {
  const cap = config.priceCaps[fuelType];
  if (cap && price > cap) throw bad(`Price is above the regulated cap of ${cap.toLocaleString('en-US')} TZS per litre.`);
}

export function fullStation(id) {
  const s = one('SELECT * FROM stations WHERE id = ?', id);
  s.products = all('SELECT * FROM products WHERE station_id = ? AND deleted = 0 ORDER BY id', id);
  const pm = Object.fromEntries(all('SELECT * FROM station_payment_methods WHERE station_id = ?', id).map((p) => [p.method, p]));
  s.payment_methods = Object.entries(PAYMENT_METHODS).map(([method, m]) => ({
    method, label: m.label, kind: m.kind, enabled: !!pm[method]?.enabled, account: pm[method]?.account || '',
  }));
  s.riders = all(`SELECT u.id, u.name, u.phone, r.vehicle, r.plate, r.online, r.active, r.last_seen
                  FROM riders r JOIN users u ON u.id = r.user_id WHERE r.station_id = ? ORDER BY u.name`, id);
  return s;
}

export default (r) => {
  // ---------- Client: find stations that can deliver ----------
  r.get('/api/stations/nearby', requireUser(), ({ query }) => {
    const lat = numIn(query.lat, 'Latitude', { min: -90, max: 90 });
    const lng = numIn(query.lng, 'Longitude', { min: -180, max: 180 });
    const fuel = oneOf(query.fuel || 'petrol', 'Fuel', ['petrol', 'diesel', 'other']);
    const litres = numIn(query.litres || 10, 'Litres', { min: 1, max: 1000 });
    const method = oneOf(query.delivery || (litres > 20 ? 'tanker' : 'boda'), 'Delivery', Object.keys(config.delivery));
    const d = config.delivery[method];

    const rows = all(`SELECT s.id, s.name, s.address, s.lat, s.lng, s.offers_boda, s.offers_tanker,
                             p.id AS product_id, p.name AS product_name, p.price_per_litre, p.stock_litres
                      FROM stations s JOIN products p ON p.station_id = s.id
                      WHERE s.status = 'approved' AND s.is_open = 1 AND p.active = 1 AND p.deleted = 0 AND p.fuel_type = ?`, fuel);
    const out = [];
    for (const s of rows) {
      const km = roadKm(lat, lng, s.lat, s.lng);
      let unavailable = null;
      if (km > config.maxDeliveryKm) unavailable = 'Too far';
      else if (!s[`offers_${method}`]) unavailable = `No ${d.label.toLowerCase()}`;
      else if (s.stock_litres < litres) unavailable = 'Not enough stock';
      else if (!one('SELECT 1 FROM riders WHERE station_id = ? AND vehicle = ? AND active = 1 AND online = 1', s.id, method)) unavailable = 'No rider online';
      const payment_methods = all('SELECT method FROM station_payment_methods WHERE station_id = ? AND enabled = 1', s.id)
        .map((p) => ({ method: p.method, ...PAYMENT_METHODS[p.method] }));
      if (!unavailable && !payment_methods.length) unavailable = 'No payment methods';
      out.push({
        station_id: s.id, name: s.name, address: s.address, distance_km: km,
        product_id: s.product_id, product_name: s.product_name, price_per_litre: s.price_per_litre,
        payment_methods, available: !unavailable, unavailable_reason: unavailable,
        quote: priceOrder({ pricePerLitre: s.price_per_litre, litres, method, km }),
      });
    }
    out.sort((a, b) => b.available - a.available || a.distance_km - b.distance_km);
    return { delivery: method, litres, limits: { min: d.minLitres, max: d.maxLitres }, stations: out };
  });

  r.get('/api/config', () => ({
    delivery: config.delivery, serviceFeeRate: config.serviceFeeRate, maxDeliveryKm: config.maxDeliveryKm,
    paymentMethods: PAYMENT_METHODS, paymentProvider: config.paymentProvider,
  }));

  // ---------- Station owner ----------
  r.post('/api/stations', requireUser('station'), ({ user, body }) => {
    if (user.station_id) throw conflict('You already have a station.');
    const id = tx(() => {
      const { lastInsertRowid } = run(
        'INSERT INTO stations (owner_id, name, license_no, phone, address, lat, lng, offers_boda, offers_tanker) VALUES (?,?,?,?,?,?,?,?,?)',
        user.id, str(body.name, 'Station name', { max: 100 }), str(body.license_no, 'EWURA licence number', { max: 60 }),
        phone(body.phone, 'Station phone'), str(body.address, 'Address', { max: 200 }),
        numIn(body.lat, 'Latitude', { min: -90, max: 90 }), numIn(body.lng, 'Longitude', { min: -180, max: 180 }),
        body.offers_boda === false ? 0 : 1, body.offers_tanker ? 1 : 0,
      );
      run('UPDATE users SET station_id = ? WHERE id = ?', lastInsertRowid, user.id);
      for (const m of Object.keys(PAYMENT_METHODS)) run('INSERT INTO station_payment_methods (station_id, method) VALUES (?, ?)', lastInsertRowid, m);
      return lastInsertRowid;
    });
    return fullStation(id);
  });

  r.get('/api/station', requireUser('station'), ({ user }) => fullStation(stationOrFail(user).id));

  r.patch('/api/station', requireUser('station'), ({ user, body }) => {
    const s = stationOrFail(user);
    const f = {};
    if (body.name !== undefined) f.name = str(body.name, 'Station name', { max: 100 });
    if (body.phone !== undefined) f.phone = phone(body.phone, 'Station phone');
    if (body.address !== undefined) f.address = str(body.address, 'Address', { max: 200 });
    if (body.license_no !== undefined) f.license_no = str(body.license_no, 'EWURA licence number', { max: 60 });
    if (body.lat !== undefined) f.lat = numIn(body.lat, 'Latitude', { min: -90, max: 90 });
    if (body.lng !== undefined) f.lng = numIn(body.lng, 'Longitude', { min: -180, max: 180 });
    for (const k of ['is_open', 'offers_boda', 'offers_tanker']) if (body[k] !== undefined) f[k] = body[k] ? 1 : 0;
    const keys = Object.keys(f);
    if (keys.length) run(`UPDATE stations SET ${keys.map((k) => `${k} = ?`).join(', ')} WHERE id = ?`, ...Object.values(f), s.id);
    return fullStation(s.id);
  });

  // Products
  r.post('/api/station/products', requireUser('station'), ({ user, body }) => {
    const s = stationOrFail(user);
    const fuel_type = oneOf(body.fuel_type, 'Fuel type', ['petrol', 'diesel', 'other']);
    const price = numIn(body.price_per_litre, 'Price per litre', { min: 1, max: 100000, int: true });
    checkPriceCap(fuel_type, price);
    run('INSERT INTO products (station_id, name, fuel_type, price_per_litre, stock_litres, active) VALUES (?,?,?,?,?,?)',
      s.id, str(body.name, 'Product name', { max: 60 }), fuel_type, price,
      numIn(body.stock_litres ?? 0, 'Stock', { min: 0, max: 10_000_000 }), body.active === false ? 0 : 1);
    return fullStation(s.id);
  });

  r.patch('/api/station/products/:id', requireUser('station'), ({ user, body, params }) => {
    const s = stationOrFail(user);
    const p = one('SELECT * FROM products WHERE id = ? AND station_id = ? AND deleted = 0', params.id, s.id);
    if (!p) throw notFound('Product not found.');
    const f = {};
    if (body.name !== undefined) f.name = str(body.name, 'Product name', { max: 60 });
    if (body.price_per_litre !== undefined) {
      f.price_per_litre = numIn(body.price_per_litre, 'Price per litre', { min: 1, max: 100000, int: true });
      checkPriceCap(p.fuel_type, f.price_per_litre);
    }
    if (body.stock_litres !== undefined) f.stock_litres = numIn(body.stock_litres, 'Stock', { min: 0, max: 10_000_000 });
    if (body.active !== undefined) f.active = body.active ? 1 : 0;
    const keys = Object.keys(f);
    if (keys.length) run(`UPDATE products SET ${keys.map((k) => `${k} = ?`).join(', ')}, updated_at = datetime('now') WHERE id = ?`, ...Object.values(f), p.id);
    return fullStation(s.id);
  });

  r.delete('/api/station/products/:id', requireUser('station'), ({ user, params }) => {
    const s = stationOrFail(user);
    run('UPDATE products SET deleted = 1, active = 0 WHERE id = ? AND station_id = ?', params.id, s.id);
    return fullStation(s.id);
  });

  // Payment methods
  r.put('/api/station/payment-methods/:method', requireUser('station'), ({ user, body, params }) => {
    const s = stationOrFail(user);
    const method = oneOf(params.method, 'Payment method', Object.keys(PAYMENT_METHODS));
    const account = str(body.account ?? '', 'Account', { min: 0, max: 120, optional: true });
    const enabled = body.enabled ? 1 : 0;
    if (enabled && method === 'bank' && !account) throw bad('Add the bank name and account number before switching on bank transfer.');
    run(`INSERT INTO station_payment_methods (station_id, method, enabled, account) VALUES (?,?,?,?)
         ON CONFLICT (station_id, method) DO UPDATE SET enabled = excluded.enabled, account = excluded.account`, s.id, method, enabled, account);
    return fullStation(s.id);
  });

  // Riders
  r.post('/api/station/riders', requireUser('station'), ({ user, body }) => {
    const s = stationOrFail(user);
    const ph = phone(body.phone, 'Rider phone');
    if (one('SELECT id FROM users WHERE phone = ?', ph)) throw conflict('That phone number already has an account.');
    tx(() => {
      const { lastInsertRowid } = run("INSERT INTO users (name, phone, password_hash, role, station_id) VALUES (?,?,?,'rider',?)",
        str(body.name, 'Rider name', { min: 2, max: 80 }), ph, hashPassword(str(body.password, 'Temporary password', { min: 6, max: 100 })), s.id);
      run('INSERT INTO riders (user_id, station_id, vehicle, plate) VALUES (?,?,?,?)', lastInsertRowid, s.id,
        oneOf(body.vehicle, 'Vehicle', ['boda', 'tanker']), str(body.plate, 'Plate number', { max: 20 }).toUpperCase());
    });
    return fullStation(s.id);
  });

  r.patch('/api/station/riders/:id', requireUser('station'), ({ user, body, params }) => {
    const s = stationOrFail(user);
    const rd = one('SELECT * FROM riders WHERE user_id = ? AND station_id = ?', params.id, s.id);
    if (!rd) throw notFound('Rider not found.');
    if (body.active !== undefined) run('UPDATE riders SET active = ?, online = CASE WHEN ? = 0 THEN 0 ELSE online END WHERE user_id = ?', body.active ? 1 : 0, body.active ? 1 : 0, rd.user_id);
    if (body.vehicle !== undefined) run('UPDATE riders SET vehicle = ? WHERE user_id = ?', oneOf(body.vehicle, 'Vehicle', ['boda', 'tanker']), rd.user_id);
    if (body.plate !== undefined) run('UPDATE riders SET plate = ? WHERE user_id = ?', str(body.plate, 'Plate number', { max: 20 }).toUpperCase(), rd.user_id);
    return fullStation(s.id);
  });

  // Orders & stats
  r.get('/api/station/orders', requireUser('station'), ({ user, query }) => {
    const s = stationOrFail(user);
    const rows = query.scope === 'history'
      ? all(`SELECT * FROM orders WHERE station_id = ? AND status IN ('delivered','cancelled','rejected') ORDER BY id DESC LIMIT 100`, s.id)
      : all(`SELECT * FROM orders WHERE station_id = ? AND status IN (${ACTIVE.map(() => '?').join(',')}) ORDER BY id DESC`, s.id, ...ACTIVE);
    return rows.map((o) => orderView(o, user));
  });

  r.get('/api/station/stats', requireUser('station'), ({ user }) => {
    const s = stationOrFail(user);
    const today = one(`SELECT COUNT(*) AS delivered, COALESCE(SUM(litres),0) AS litres, COALESCE(SUM(fuel_cost),0) AS fuel_sales
                       FROM orders WHERE station_id = ? AND status = 'delivered' AND date(updated_at, '+3 hours') = date('now', '+3 hours')`, s.id);
    const waiting = one("SELECT COUNT(*) AS n FROM orders WHERE station_id = ? AND status = 'placed'", s.id).n;
    const out = one("SELECT COUNT(*) AS n FROM orders WHERE station_id = ? AND status IN ('accepted','assigned','picked_up','on_the_way','arrived')", s.id).n;
    return { ...today, waiting, out_for_delivery: out };
  });
};
