const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname);
const port = Number.parseInt(process.env.PORT || '3000', 10);
const mimeTypes = { '.css': 'text/css; charset=utf-8', '.exe': 'application/vnd.microsoft.portable-executable', '.html': 'text/html; charset=utf-8', '.jpg': 'image/jpeg', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml' };

function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', ...headers });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed.', { Allow: 'GET, HEAD' });
  if (req.url === '/healthz') return send(res, 200, JSON.stringify({ status: 'ok' }), { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });

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

server.listen(port, '127.0.0.1', () => console.log(`Unlimited Clipboard site listening on 127.0.0.1:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
