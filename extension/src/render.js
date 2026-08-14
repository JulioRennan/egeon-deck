'use strict';

const MarkdownIt = require('markdown-it');

/// Renderiza no extension host, não no webview. O markdown-it dá `token.map`
/// com as linhas de origem de cada bloco — é isso que permite clicar num
/// parágrafo e saber exatamente que linhas do arquivo editar.
const md = new MarkdownIt({ html: false, linkify: true, typographer: false });

const renderToken = md.renderer.renderToken.bind(md.renderer);
md.renderer.renderToken = function (tokens, idx, options) {
  const token = tokens[idx];
  if (token.map && token.nesting !== -1) {
    token.attrSet('data-line', String(token.map[0]));
    token.attrSet('data-line-end', String(token.map[1]));
    token.attrJoin('class', 'mb-block');
  }
  return renderToken(tokens, idx, options);
};

// `fence` e `code_block` têm regra própria e não passam por renderToken, então
// o bloco é embrulhado à mão para não perder a âncora de linha.
for (const rule of ['fence', 'code_block']) {
  const original = md.renderer.rules[rule];
  md.renderer.rules[rule] = function (tokens, idx, options, env, self) {
    const token = tokens[idx];
    const html = original
      ? original(tokens, idx, options, env, self)
      : renderToken(tokens, idx, options);
    if (!token.map) return html;
    return `<div class="mb-block" data-line="${token.map[0]}" `
         + `data-line-end="${token.map[1]}">${html}</div>`;
  };
}

function render(markdown) {
  return md.render(markdown);
} 

module.exports = { render };
