'use strict';

const fs = require('fs');
const path = require('path');

/// Comentários de review moram FORA do .md, em sidecar por arquivo.
/// O markdown é o produto e tem que ficar limpo — quem grava marcador HTML
/// dentro do arquivo (md-redline) fez a escolha oposta, que é válida mas não a
/// nossa (ADR-005).
function sidecarPath(workspaceRoot, fileAbsPath) {
  const relative = path.relative(workspaceRoot, fileAbsPath) || path.basename(fileAbsPath);
  return path.join(workspaceRoot, '.egeon', 'reviews', `${relative}.json`);
}

function load(workspaceRoot, fileAbsPath) {
  const file = sidecarPath(workspaceRoot, fileAbsPath);
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return Array.isArray(parsed.comments) ? parsed.comments : [];
  } catch (error) {
    return [];
  }
}

function save(workspaceRoot, fileAbsPath, comments) {
  const file = sidecarPath(workspaceRoot, fileAbsPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    JSON.stringify({ file: path.relative(workspaceRoot, fileAbsPath), comments }, null, 2)
  );
  return file;
}

/// Reancora por CONTEÚDO, nunca por número de linha (ADR-005b).
///
/// O agente reescreve o arquivo; um comentário preso a "linha 12" passa a
/// apontar para outra coisa assim que ele insere um parágrafo acima — e apontar
/// para o lugar errado é pior do que não apontar.
///
/// Thread que não reancora vira órfã e continua visível, com o trecho original.
/// Nunca some calada.
function reanchor(comments, text) {
  return comments.map((comment) => {
    const quote = (comment.quote || '').trim();
    if (!quote) return { ...comment, orphan: true };

    let index = text.indexOf(quote);

    // Trecho de várias linhas pode ter sido reindentado; tenta pela primeira
    // linha antes de desistir.
    if (index === -1) {
      const firstLine = quote.split('\n')[0].trim();
      if (firstLine.length >= 8) index = text.indexOf(firstLine);
    }

    if (index === -1) return { ...comment, orphan: true };

    const line = text.slice(0, index).split('\n').length - 1;
    return { ...comment, line, orphan: false };
  });
}

/// Monta o payload que o dispatcher do app entende. `kind: review` faz o app
/// transformar isto num prompt só, com cabeçalho e trecho citado.
function buildDispatchPayload({ target, relativePath, comments }) {
  return {
    target,
    kind: 'review',
    file: relativePath,
    comments: comments.map((comment) => ({
      line: typeof comment.line === 'number' ? comment.line + 1 : undefined,
      quote: comment.quote,
      body: comment.body
    }))
  };
}

module.exports = { sidecarPath, load, save, reanchor, buildDispatchPayload };
