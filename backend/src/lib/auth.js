// Password hashing (scrypt) and signed tokens (JWT, HS256) using node:crypto.
import { scryptSync, randomBytes, timingSafeEqual, createHmac } from 'node:crypto';
import { config } from '../config.js';
import { HttpError, forbidden } from './http.js';
import { one } from '../db.js';

export function hashPassword(pw) {
  const salt = randomBytes(16);
  const hash = scryptSync(pw, salt, 64);
  return `scrypt$${salt.toString('base64')}$${hash.toString('base64')}`;
}
export function verifyPassword(pw, stored) {
  const [, salt, hash] = String(stored).split('$');
  if (!salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64');
  const got = scryptSync(pw, Buffer.from(salt, 'base64'), expected.length);
  return timingSafeEqual(expected, got);
}

const b64url = (b) => Buffer.from(b).toString('base64url');
export function signToken(payload, days = 30) {
  const head = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify({ ...payload, exp: Math.floor(Date.now() / 1000) + days * 86400 }));
  const sig = createHmac('sha256', config.jwtSecret).update(`${head}.${body}`).digest('base64url');
  return `${head}.${body}.${sig}`;
}
export function verifyToken(token) {
  const [head, body, sig] = String(token || '').split('.');
  if (!head || !body || !sig) return null;
  const expected = createHmac('sha256', config.jwtSecret).update(`${head}.${body}`).digest();
  const given = Buffer.from(sig, 'base64url');
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  const data = JSON.parse(Buffer.from(body, 'base64url').toString());
  if (data.exp < Date.now() / 1000) return null;
  return data;
}

export function userFromToken(token) {
  const t = verifyToken(token);
  if (!t) return null;
  return one('SELECT id, name, phone, role, station_id FROM users WHERE id = ?', t.sub) || null;
}

/** Middleware: require a signed-in user, optionally with one of the given roles. */
export const requireUser = (...roles) => (ctx) => {
  const h = ctx.req.headers.authorization || '';
  const user = userFromToken(h.startsWith('Bearer ') ? h.slice(7) : '');
  if (!user) throw new HttpError(401, 'Please sign in.');
  if (roles.length && !roles.includes(user.role)) throw forbidden();
  ctx.user = user;
};

// Basic brute-force protection for login: 10 attempts per phone per 15 minutes.
const attempts = new Map();
export function checkLoginRate(key) {
  const now = Date.now();
  const a = (attempts.get(key) || []).filter((t) => now - t < 15 * 60_000);
  if (a.length >= 10) throw new HttpError(429, 'Too many sign-in attempts. Try again in 15 minutes.');
  a.push(now);
  attempts.set(key, a);
}
export const clearLoginRate = (key) => attempts.delete(key);
