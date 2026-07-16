const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname);
const port = Number.parseInt(process.env.PORT || '3000', 10);
const mimeTypes = { '.css': 'text/css; charset=utf-8', '.exe': 'application/vnd.microsoft.portable-executable', '.html': 'text/html; charset=utf-8', '.jpg': 'image/jpeg', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml' };
const statsDirectory = path.join(root, 'data');
const statsFile = path.join(statsDirectory, 'visit-stats.json');

function todayInChina() {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts();
  const value = Object.fromEntries(parts.filter(({ type }) => type !== 'literal').map(({ type, value }) => [type, value]));
  return `${value.year}-${value.month}-${value.day}`;
}

function loadStats() {
  try {
    const parsed = JSON.parse(fs.readFileSync(statsFile, 'utf8'));
    if (Number.isSafeInteger(parsed.total) && parsed.total >= 0 && parsed.days && typeof parsed.days === 'object') return parsed;
  } catch (error) {
    if (error.code !== 'ENOENT') console.error('Unable to load visit stats:', error.message);
  }
  return { total: 0, days: {} };
}

let visitStats = loadStats();

function saveStats() {
  fs.mkdirSync(statsDirectory, { recursive: true });
  const temporaryFile = `${statsFile}.${process.pid}.tmp`;
  fs.writeFileSync(temporaryFile, `${JSON.stringify(visitStats)}\n`, 'utf8');
  fs.renameSync(temporaryFile, statsFile);
}

function parseCookies(header = '') {
  return Object.fromEntries(header.split(';').map((item) => item.trim().split(/=(.*)/s, 2)).filter(([name]) => name).map(([name, value = '']) => [name, decodeURIComponent(value)]));
}

function createVisitorId() {
  return require('node:crypto').randomBytes(16).toString('hex');
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', ...headers });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed.', { Allow: 'GET, HEAD' });
  if (req.url === '/healthz') return send(res, 200, JSON.stringify({ status: 'ok' }), { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });

  if (req.url === '/api/visits') {
    const date = todayInChina();
    const cookies = parseCookies(req.headers.cookie);
    const visitorId = cookies.uc_visitor || createVisitorId();
    const lastCountedDate = cookies.uc_visit_date;
    const isNewDailyVisitor = req.method === 'GET' && lastCountedDate !== date;

    if (isNewDailyVisitor) {
      visitStats.total += 1;
      visitStats.days[date] = (visitStats.days[date] || 0) + 1;
      saveStats();
    }

    const isSecure = req.socket.encrypted || req.headers['x-forwarded-proto'] === 'https';
    const cookieFlags = `Path=/; Max-Age=31536000; SameSite=Lax${isSecure ? '; Secure' : ''}; HttpOnly`;
    const headers = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' };
    if (req.method === 'GET') headers['Set-Cookie'] = [`uc_visitor=${visitorId}; ${cookieFlags}`, `uc_visit_date=${date}; ${cookieFlags}`];
    res.writeHead(200, headers);
    return res.end(req.method === 'HEAD' ? undefined : JSON.stringify({ today: visitStats.days[date] || 0, total: visitStats.total }));
  }

  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname); }
  catch { return send(res, 400, 'Bad request.'); }
  const relativePath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const filePath = path.resolve(root, relativePath);
  if (filePath !== root && !filePath.startsWith(`${root}${path.sep}`)) return send(res, 403, 'Forbidden.');

  fs.stat(filePath, (statError, stats) => {
    if (statError || !stats.isFile()) return send(res, 404, 'Not found.');
    const ext = path.extname(filePath).toLowerCase();
    const isMutable = ext === '.html' || ext === '.json';
    const headers = { 'Content-Type': mimeTypes[ext] || 'application/octet-stream', 'Cache-Control': isMutable ? 'no-cache' : 'public, max-age=604800' };
    if (ext === '.exe') headers['Content-Disposition'] = `attachment; filename="${path.basename(filePath)}"`;
    res.writeHead(200, headers);
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(filePath).on('error', () => { if (!res.headersSent) send(res, 500, 'Read error.'); else res.destroy(); }).pipe(res);
  });
});

server.listen(port, '127.0.0.1', () => console.log(`unlimited clipboard site listening on 127.0.0.1:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
