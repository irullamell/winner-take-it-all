// index.js – versi 'localhost'
import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import path from 'path';
import process from 'process';

const APP_PORT = process.env.APP_PORT || 3000;     // port publik
const VSC_PORT = process.env.VSC_PORT || 9501;     // port internal VS Code Web
const HOST     = process.env.HOST     || 'localhost';   // ⬅️ default kini 'localhost'

const CODE_SERVER_BIN = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  './node_modules/.bin/code-server' + (process.platform === 'win32' ? '.cmd' : '')
);

// jalankan VS Code Web (code-server)
const codeProc = spawn(
  CODE_SERVER_BIN,
  [
    '--port', VSC_PORT,
    '--host', HOST,                       // ⬅️ lewatkan 'localhost'
    '--accept-server-license-terms',
    '--without-connection-token'
  ],
  { stdio: 'inherit' }
);

codeProc.on('exit', code => {
  console.error(`code-server exited with status ${code}`);
  process.exit(code);
});

// reverse-proxy Express
const app = express();
app.use(
  '/',
  createProxyMiddleware({
    target: `http://${HOST}:${VSC_PORT}`,
    changeOrigin: true,
    ws: true
  })
);

app.listen(APP_PORT, () => {
  console.log(`🔗 VS Code Web siap di http://${HOST}:${APP_PORT}`);
});
