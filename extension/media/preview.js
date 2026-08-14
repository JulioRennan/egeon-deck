'use strict';

const vscode = acquireVsCodeApi();

const els = {
  doc: document.getElementById('doc'),
  threads: document.getElementById('threads'),
  file: document.getElementById('file'),
  status: document.getElementById('status'),
  request: document.getElementById('request'),
  source: document.getElementById('source'),
  bubble: document.getElementById('bubble'),
  bubbleText: document.getElementById('bubbleText'),
  bubbleSave: document.getElementById('bubbleSave'),
  bubbleCancel: document.getElementById('bubbleCancel')
};

let state = { comments: [], lines: [], file: '' };
let pendingSelection = null;

/// Comentário enviado não é mais acionável — some da vista para o painel
/// mostrar só o que ainda exige decisão. Nada é apagado: o sidecar guarda tudo
/// e o rodapé reexibe.
let showSent = (vscode.getState() || {}).showSent === true;

function visibleComments() {
  return state.comments.filter((comment) => showSent || !comment.sentAt);
}

// ---------------------------------------------------------------- render

window.addEventListener('message', (event) => {
  const message = event.data;
  if (message.type === 'render') {
    state = {
      comments: message.comments || [],
      lines: message.lines || [],
      file: message.file || '',
      // Guardado para o toggle de "enviados" poder repintar o documento do
      // zero: os destaques são inseridos no DOM, então mostrar ou esconder
      // exige recomeçar do HTML limpo.
      html: message.html || ''
    };
    els.file.textContent = message.file || '';
    els.doc.innerHTML = state.html;
    markBlocks();
    renderThreads();
  }
  if (message.type === 'status') {
    els.status.textContent = message.text;
    els.status.dataset.tone = message.tone || '';
  }
});

/// Bloco que contém a linha âncora do comentário ganha marca visual. Percorre
/// do mais específico para o mais genérico para o marcador cair no parágrafo,
/// não na seção inteira.
function blockAt(line) {
  const blocks = Array.from(els.doc.querySelectorAll('.mb-block'));
  let best = null;
  for (const block of blocks) {
    const start = Number(block.dataset.line);
    const end = Number(block.dataset.lineEnd);
    if (Number.isNaN(start) || line < start || line >= end) continue;
    if (!best || end - start < Number(best.dataset.lineEnd) - Number(best.dataset.line)) {
      best = block;
    }
  }
  return best;
}

function markBlocks() {
  for (const comment of visibleComments()) {
    if (comment.orphan) continue;
    const block = blockAt(comment.line);
    if (!block) continue;
    block.classList.add('mb-commented');
    if (!comment.sentAt) block.classList.add('mb-pending');
    highlightQuote(block, comment);
  }
}

/// Pinta a seleção enquanto o balão está aberto.
///
/// Focar o textarea apaga a seleção nativa do DOM — sem isto você perde de
/// vista o trecho marcado justamente enquanto escreve o comentário sobre ele.
function paintSelection(range) {
  clearSelectionPaint();

  const root = range.commonAncestorContainer;
  const container = root.nodeType === 1 ? root : root.parentElement;
  if (!container) return;

  // Calcula TODAS as fatias antes de mexer no DOM: embrulhar um nó invalida o
  // range para os seguintes.
  const slices = [];
  const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (!range.intersectsNode(node)) continue;
    const start = node === range.startContainer ? range.startOffset : 0;
    const end = node === range.endContainer ? range.endOffset : node.nodeValue.length;
    if (end > start) slices.push({ node, start, end });
  }

  for (const slice of slices) {
    const piece = document.createRange();
    piece.setStart(slice.node, slice.start);
    piece.setEnd(slice.node, slice.end);
    const mark = document.createElement('mark');
    mark.className = 'mb-selecting';
    try {
      piece.surroundContents(mark);
    } catch (error) {
      // Fatia que cruza fronteira de elemento não embrulha; as outras seguem.
    }
  }
}

function clearSelectionPaint() {
  for (const mark of Array.from(els.doc.querySelectorAll('mark.mb-selecting'))) {
    const parent = mark.parentNode;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  }
}

/// Pinta o trecho exato que foi comentado.
///
/// A marca na margem diz que o bloco tem comentário, não QUAL pedaço — num
/// parágrafo longo isso não ajuda. O trecho vem da seleção do usuário, ou seja,
/// é texto renderizado; então a busca é feita sobre os nós de texto do bloco.
function highlightQuote(block, comment) {
  const quote = (comment.quote || '').trim();
  if (!quote) return;

  // Mapa dos nós de texto com deslocamento acumulado: o trecho pode atravessar
  // <strong>, <code> etc., e aí não existe um nó único para embrulhar.
  const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
  const nodes = [];
  let text = '';
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement && node.parentElement.closest('mark.mb-highlight')) continue;
    nodes.push({ node, start: text.length });
    text += node.nodeValue;
  }

  const at = text.indexOf(quote);
  if (at === -1) return; // sem match exato: a marca na margem já sinaliza
  const end = at + quote.length;

  for (const entry of nodes) {
    const nodeStart = entry.start;
    const nodeEnd = nodeStart + entry.node.nodeValue.length;
    if (nodeEnd <= at || nodeStart >= end) continue;

    const range = document.createRange();
    range.setStart(entry.node, Math.max(0, at - nodeStart));
    range.setEnd(entry.node, Math.min(entry.node.nodeValue.length, end - nodeStart));

    const mark = document.createElement('mark');
    mark.className = comment.sentAt ? 'mb-highlight mb-highlight-sent' : 'mb-highlight';
    mark.dataset.commentId = comment.id;
    mark.title = comment.body;
    try {
      range.surroundContents(mark);
    } catch (error) {
      // Range que cruza fronteira de elemento não pode ser embrulhado; os
      // outros pedaços do trecho seguem marcados.
    }
  }
}

function renderThreads() {
  const pending = state.comments.filter((c) => !c.sentAt);
  els.request.disabled = pending.length === 0;
  els.request.textContent = pending.length
    ? `Request changes (${pending.length})`
    : 'Request changes';

  els.threads.innerHTML = '';
  const visible = visibleComments();
  const sent = state.comments.filter((comment) => comment.sentAt);

  if (!visible.length) {
    const empty = document.createElement('p');
    empty.className = 'mb-empty';
    empty.textContent = sent.length
      ? 'Nada pendente. Selecione um trecho para comentar.'
      : 'Selecione um trecho para comentar.';
    els.threads.appendChild(empty);
  }

  for (const comment of visible) {
    const card = document.createElement('article');
    card.className = 'mb-thread';
    card.dataset.commentId = comment.id;
    if (comment.sentAt) card.classList.add('mb-sent');
    if (comment.orphan) card.classList.add('mb-orphan');

    const quote = document.createElement('blockquote');
    quote.textContent = comment.quote;
    card.appendChild(quote);

    const body = document.createElement('p');
    body.textContent = comment.body;
    card.appendChild(body);

    const meta = document.createElement('div');
    meta.className = 'mb-meta';
    meta.textContent = comment.orphan
      ? 'órfã — o trecho não existe mais no arquivo'
      : comment.sentAt
        ? `enviado ${comment.sentAt.slice(11, 16)}`
        : `linha ${comment.line + 1}`;
    card.appendChild(meta);

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'mb-remove';
    remove.textContent = 'remover';
    remove.addEventListener('click', () =>
      vscode.postMessage({ type: 'deleteComment', id: comment.id }));
    card.appendChild(remove);

    if (!comment.orphan) {
      card.addEventListener('click', (event) => {
        if (event.target === remove) return;
        const mark = els.doc.querySelector(`mark[data-comment-id="${comment.id}"]`);
        const anchor = mark || blockAt(comment.line);
        if (!anchor) return;
        anchor.scrollIntoView({ behavior: 'smooth', block: 'center' });
        anchor.classList.add('mb-flash');
        setTimeout(() => anchor.classList.remove('mb-flash'), 1200);
      });
    }

    els.threads.appendChild(card);
  }

  if (!sent.length) return;

  const footer = document.createElement('button');
  footer.type = 'button';
  footer.className = 'mb-toggle-sent';
  footer.textContent = showSent
    ? `ocultar ${sent.length} enviado${sent.length > 1 ? 's' : ''}`
    : `mostrar ${sent.length} enviado${sent.length > 1 ? 's' : ''}`;
  footer.addEventListener('click', () => {
    showSent = !showSent;
    vscode.setState({ showSent });
    els.doc.innerHTML = state.html || els.doc.innerHTML;
    markBlocks();
    renderThreads();
  });
  els.threads.appendChild(footer);
}

// ------------------------------------------------------------- comentar

/// Clicar no trecho destacado leva à thread correspondente — o caminho inverso
/// do clique na thread.
els.doc.addEventListener('click', (event) => {
  const mark = event.target.closest && event.target.closest('mark.mb-highlight');
  if (!mark) return;
  const card = els.threads.querySelector(`[data-comment-id="${mark.dataset.commentId}"]`);
  if (!card) return;
  card.scrollIntoView({ behavior: 'smooth', block: 'center' });
  card.classList.add('mb-flash');
  setTimeout(() => card.classList.remove('mb-flash'), 1200);
});

els.doc.addEventListener('mouseup', () => {
  const selection = window.getSelection();
  const text = selection ? selection.toString().trim() : '';
  if (!text) return;

  // startContainer, não anchorNode: quem seleciona de trás para frente tem o
  // anchor no FIM da seleção, e o comentário ancoraria no bloco errado.
  const range = selection.getRangeAt(0);
  const node = range.startContainer;
  const element = node && (node.nodeType === 1 ? node : node.parentElement);
  const block = element && element.closest('.mb-block');
  if (!block) return;

  const rect = range.getBoundingClientRect();
  pendingSelection = { quote: text, line: Number(block.dataset.line) || 0 };

  // Pinta ANTES de focar o textarea: o focus apaga a seleção nativa.
  paintSelection(range);

  els.bubble.hidden = false;
  els.bubble.style.top = `${window.scrollY + rect.bottom + 8}px`;
  els.bubble.style.left = `${Math.max(12, rect.left)}px`;
  els.bubbleText.value = '';
  els.bubbleText.focus();
});

function closeBubble() {
  els.bubble.hidden = true;
  pendingSelection = null;
  clearSelectionPaint();
}

els.bubbleCancel.addEventListener('click', closeBubble);

els.bubbleSave.addEventListener('click', () => {
  const body = els.bubbleText.value.trim();
  if (!body || !pendingSelection) return closeBubble();
  vscode.postMessage({ type: 'addComment', ...pendingSelection, body });
  closeBubble();
});

els.bubbleText.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) els.bubbleSave.click();
  if (event.key === 'Escape') closeBubble();
});

// ---------------------------------------------------------------- editar

/// Duplo clique abre o bloco para edição com o markdown de origem — é o que
/// faltava no preview embutido do VSCode, que é somente-leitura.
els.doc.addEventListener('dblclick', (event) => {
  const block = event.target.closest && event.target.closest('.mb-block');
  if (!block || block.classList.contains('mb-editing')) return;

  const start = Number(block.dataset.line);
  const end = Number(block.dataset.lineEnd);
  if (Number.isNaN(start) || Number.isNaN(end)) return;

  const source = state.lines.slice(start, end).join('\n');
  const editor = document.createElement('textarea');
  editor.className = 'mb-editor';
  editor.value = source;
  editor.rows = Math.max(2, source.split('\n').length + 1);

  block.classList.add('mb-editing');
  block.replaceChildren(editor);
  editor.focus();

  const commit = () => {
    if (editor.value !== source) {
      vscode.postMessage({
        type: 'editBlock', line: start, lineEnd: end, text: editor.value
      });
    } else {
      vscode.postMessage({ type: 'ready' });
    }
  };

  editor.addEventListener('keydown', (keyEvent) => {
    if (keyEvent.key === 'Enter' && (keyEvent.metaKey || keyEvent.ctrlKey)) commit();
    if (keyEvent.key === 'Escape') vscode.postMessage({ type: 'ready' });
  });
  editor.addEventListener('blur', commit);
});

// ----------------------------------------------------------------- barra

els.request.addEventListener('click', () => vscode.postMessage({ type: 'requestChanges' }));
els.source.addEventListener('click', () => vscode.postMessage({ type: 'openSource' }));

vscode.postMessage({ type: 'ready' });
