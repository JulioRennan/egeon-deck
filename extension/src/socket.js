'use strict';

const http = require('http');
const os = require('os');
const path = require('path');

/// Cliente do socket de controle do app egeon.
/// Unix domain socket, não porta TCP — nada trafega pela rede.
function resolveSocketPath(configured) {
  const raw = configured && configured.trim() ? configured.trim() : '~/.egeon/sock';
  return raw.startsWith('~') ? path.join(os.homedir(), raw.slice(1)) : raw;
}

function request(socketPath, { method = 'GET', route, body }) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body)); 
    const req = http.request(
      {
        socketPath,
        path: route,
        method,
        headers: payload
          ? { 'Content-Type': 'application/json', 'Content-Length': payload.length }
          : {}
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          try {
            resolve({ status: res.statusCode, body: JSON.parse(text) });
          } catch (error) {
            resolve({ status: res.statusCode, body: { raw: text } });
          }
        });
      }
    );

    // Sem timeout, um app travado pendura o botão "Request changes" para
    // sempre — a UI fica em "enviando…" sem nunca resolver.
    req.setTimeout(5000, () => {
      req.destroy(new Error('sem resposta em 5s'));
    });

    req.on('error', (error) => {
      // Erro mais comum de longe: o app Egeon Deck não está rodando.
      reject(new Error(
        `não consegui falar com o Egeon Deck em ${socketPath}: ${error.message}`
      ));
    });

    if (payload) req.write(payload);
    req.end();
  });
}

async function listTargets(socketPath) {
  const { body } = await request(socketPath, { route: '/targets' });
  return Array.isArray(body.targets) ? body.targets : [];
}

async function dispatch(socketPath, payload) {
  return request(socketPath, { method: 'POST', route: '/dispatch', body: payload });
}

module.exports = { resolveSocketPath, request, listTargets, dispatch };
