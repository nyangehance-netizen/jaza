// Small HTTP toolkit: router, JSON bodies, errors, CORS and static files.
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { config } from '../config.js';

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}
export const bad = (msg, details) => new HttpError(400, msg, details);
export const forbidden = (msg = 'You do not have access to this.') => new HttpError(403, msg);
export const notFound = (msg = 'Not found.') => new HttpError(404, msg);
export const conflict = (msg) => new HttpError(409, msg);

export class Router {
  routes = [];
  add(method, pattern, ...handlers) {
    const keys = [];
    const re = new RegExp('^' + pattern.replace(/:(\w+)/g, (_, k) => (keys.push(k), '([^/]+)')) + '/?$');
    this.routes.push({ method, re, keys, handlers });
    return this;
  }
  get(p, ...h) { return this.add('GET', p, ...h); }
  post(p, ...h) { return this.add('POST', p, ...h); }
  patch(p, ...h) { return this.add('PATCH', p, ...h); }
  put(p, ...h) { return this.add('PUT', p, ...h); }
  delete(p, ...h) { return this.add('DELETE', p, ...h); }
  match(method, pathname) {
    for (const r of this.routes) {
      if (r.method !== method) continue;
      const m = pathname.match(r.re);
      if (m) return { handlers: r.handlers, params: Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])])) };
    }
    return null;
  }
}

export async function readJson(req, limit = 1_000_000) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return {};
  let size = 0;
  const chunks = [];
  for await (const c of req) {
    size += c.length;
    if (size > limit) throw new HttpError(413, 'Request body is too large.');
    chunks.push(c);
  }
  const raw = Buffer.concat(chunks).toString('utf8');
  req.rawBody = raw;
  if (!raw) return {};
  try { return JSON.parse(raw); } catch { throw bad('Request body must be valid JSON.'); }
}

export function send(res, status, data) {
  if (res.headersSent) return;
  const body = data === undefined ? '' : JSON.stringify(data);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(body);
}

export function cors(req, res) {
  res.setHeader('Access-Control-Allow-Origin', config.corsOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.json': 'application/json', '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json' };

export async function serveStatic(res, dir, pathname) {
  let rel = decodeURIComponent(pathname).replace(/^\/+/, '') || 'index.html';
  let file = path.resolve(dir, rel);
  if (!file.startsWith(path.resolve(dir))) return false;
  try {
    let s = await stat(file);
    if (s.isDirectory()) { file = path.join(file, 'index.html'); s = await stat(file); }
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(body);
    return true;
  } catch {
    return false;
  }
}

// ---- validation helpers ----
export function str(v, name, { min = 1, max = 200, optional = false } = {}) {
  if (v === undefined || v === null || v === '') {
    if (optional) return '';
    throw bad(`${name} is required.`);
  }
  if (typeof v !== 'string') throw bad(`${name} must be text.`);
  const s = v.trim();
  if (s.length < min || s.length > max) throw bad(`${name} must be ${min}–${max} characters.`);
  return s;
}
export function numIn(v, name, { min = -Infinity, max = Infinity, int = false, optional = false } = {}) {
  if (v === undefined || v === null || v === '') {
    if (optional) return undefined;
    throw bad(`${name} is required.`);
  }
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max || (int && !Number.isInteger(n))) throw bad(`${name} must be a number between ${min} and ${max}.`);
  return n;
}
export function oneOf(v, name, list) {
  if (!list.includes(v)) throw bad(`${name} must be one of: ${list.join(', ')}.`);
  return v;
}
/** Normalise Tanzanian phone numbers to 2557XXXXXXXX. */
export function phone(v, name = 'Phone number') {
  const digits = String(v ?? '').replace(/\D/g, '');
  let p = digits;
  if (/^0[67]\d{8}$/.test(p)) p = '255' + p.slice(1);
  else if (/^[67]\d{8}$/.test(p)) p = '255' + p;
  if (!/^255[67]\d{8}$/.test(p)) throw bad(`${name} must be a Tanzanian mobile number, like 0754 123 456.`);
  return p;
}
