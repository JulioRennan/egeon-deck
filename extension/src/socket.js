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

/// `folder` faz o app responder só pelos terminais da sessão dona daquela pasta.
/// `all` vem junto: quem escolhe atravessar sessão de propósito continua podendo,
/// e é por ela que se confere se um alvo gravado ainda existe.
///
/// `scoped: false` é app mais antigo que a rota com escopo — ele responde 404 a
/// `/targets?folder=`, e sem esse degrau a extensão nova concluiria "nenhum
/// terminal ativo" contra um app cheio de terminais vivos.
async function listTargets(socketPath, folder) {
  if (folder) {
    const scoped = await request(socketPath, {
      route: `/targets?folder=${encodeURIComponent(folder)}`
    });
    if (scoped.body && Array.isArray(scoped.body.targets)) {
      const targets = scoped.body.targets;
      return {
        scoped: true,
        targets,
        all: Array.isArray(scoped.body.all) ? scoped.body.all : targets,
        session: typeof scoped.body.session === 'string' ? scoped.body.session : ''
      };
    }
  }

  const { body } = await request(socketPath, { route: '/targets' });
  const targets = Array.isArray(body.targets) ? body.targets : [];
  return { scoped: false, targets, all: targets, session: '' };
}

async function dispatch(socketPath, payload) {
  return request(socketPath, { method: 'POST', route: '/dispatch', body: payload });
}

module.exports = { resolveSocketPath, request, listTargets, dispatch };
