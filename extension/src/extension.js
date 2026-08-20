'use strict';

const fs = require('fs');
const path = require('path');
const vscode = require('vscode');

const { render } = require('./render');
const review = require('./review');
const socket = require('./socket');

const VIEW_TYPE = 'egeon.spec';

function workspaceRootFor(uri) {
  const folder = vscode.workspace.getWorkspaceFolder(uri);
  return folder ? folder.uri.fsPath : path.dirname(uri.fsPath);
}

function config() {
  return vscode.workspace.getConfiguration('egeon');
}

function socketPath() {
  return socket.resolveSocketPath(config().get('socketPath'));
}

const OUTRA_BANCADA = 'outra bancada…';

/// Pergunta o alvo uma vez e guarda — mas confere a cada envio se ele ainda
/// existe, e sugere só terminais vivos da bancada desta pasta.
///
/// O alvo mora no settings do workspace, e nó apagado ou renomeado deixava ali
/// um endereço morto: o app respondia "alvo desconhecido" e a extensão insistia
/// no mesmo valor, então TODO clique em "Request changes" falhava igual, para
/// sempre.
///
/// `force` ignora o que está gravado e pergunta de novo — é o que faz a troca de
/// alvo estar sempre a um clique, sem precisar da paleta de comandos.
async function resolveTarget({ folder, interactive = true, force = false } = {}) {
  const configured = force ? '' : (config().get('target') || '').trim();

  let listing = null;
  try {
    listing = await socket.listTargets(socketPath(), folder);
  } catch (error) {
    // App fora do ar ou socket errado: não há como saber se o alvo vale. Segue
    // com o que está gravado e deixa o dispatch dar o erro de verdade, que é
    // mais específico do que qualquer chute daqui.
    if (configured) return { target: configured };
    if (interactive) vscode.window.showErrorMessage(`egeon: ${error.message}`);
    return { target: '', detail: error.message };
  }

  // Confere contra a lista INTEIRA, não contra a da bancada: escolher um terminal
  // de outra bancada é legítimo, e apagar essa escolha a cada envio seria desfazer
  // na surdina o que o usuário pediu. O escopo da bancada vale para SUGERIR.
  if (configured && listing.all.includes(configured)) return { target: configured };

  if (configured) {
    // Limpar é o que faz o próximo clique perguntar em vez de repetir a falha.
    await config().update('target', '', vscode.ConfigurationTarget.Workspace);
    const detail = `alvo '${configured}' não existe mais; ativos: `
      + (listing.all.length ? listing.all.join(', ') : 'nenhum');
    if (!interactive) return { target: '', detail };
    vscode.window.showWarningMessage(`egeon: ${detail}`);
  }

  if (!interactive) return { target: '', detail: 'nenhum alvo configurado' };
  return pickTarget(listing);
}

/// Mostra a escolha e grava. Primeira lista é a da bancada desta pasta; as outras
/// ficam atrás de um segundo passo, para estarem ao alcance sem poluir o caso
/// normal.
async function pickTarget(listing) {
  const dentro = listing.targets;
  const fora = listing.all.filter((address) => !dentro.includes(address));

  if (!dentro.length && !fora.length) {
    const detail = 'nenhum terminal ativo no app.';
    vscode.window.showErrorMessage(`egeon: ${detail}`);
    return { target: '', detail };
  }

  let escolha;
  if (!listing.scoped) {
    // App sem escopo por pasta: lista global, e nada a prometer sobre bancada.
    escolha = await vscode.window.showQuickPick(listing.all, {
      title: 'egeon — para qual terminal vão os comentários?',
      placeHolder: 'ex: deck/claude-back'
    });
  } else if (dentro.length) {
    escolha = await vscode.window.showQuickPick(fora.length ? [...dentro, OUTRA_BANCADA] : dentro, {
      title: `egeon — terminais de ${listing.workbench}`,
      placeHolder: 'quem recebe os comentários deste arquivo'
    });
  } else {
    // Pasta que não é de nenhuma bancada, ou bancada sem terminal de pé: melhor
    // oferecer o resto dizendo por quê do que dar um beco sem saída.
    escolha = await vscode.window.showQuickPick(fora, {
      title: listing.workbench
        ? `egeon — ${listing.workbench} não tem terminal ativo; outras bancadas`
        : 'egeon — esta pasta não é de nenhuma bancada; terminais ativos'
    });
  }

  if (escolha === OUTRA_BANCADA) {
    escolha = await vscode.window.showQuickPick(fora, {
      title: 'egeon — terminais de outras bancadas'
    });
  }
  if (!escolha) return { target: '', detail: 'nenhum alvo escolhido' };

  await config().update('target', escolha, vscode.ConfigurationTarget.Workspace);
  return { target: escolha };
}

/// Envia os comentários pendentes como UM prompt na bancada viva do agente.
/// Mesma função usada pelo botão do preview e pelo autoteste — para o que é
/// verificado ser exatamente o que o usuário dispara.
async function sendRequestChanges(documentUri, { interactive = true } = {}) {
  const root = workspaceRootFor(documentUri);
  const filePath = documentUri.fsPath;
  const comments = review.load(root, filePath);
  const pending = comments.filter((comment) => !comment.sentAt);

  if (!pending.length) {
    return { ok: false, detail: 'nenhum comentário pendente' };
  }

  const resolved = await resolveTarget({ folder: root, interactive });
  const target = resolved.target;
  if (!target) return { ok: false, detail: resolved.detail || 'nenhum alvo escolhido' };

  const payload = review.buildDispatchPayload({
    target,
    relativePath: path.relative(root, filePath) || path.basename(filePath),
    comments: pending
  });

  const response = await socket.dispatch(socketPath(), payload);
  if (response.status !== 200 || (response.body && response.body.ok === false)) {
    const detail = (response.body && response.body.error) || `HTTP ${response.status}`;
    // O alvo pode morrer entre a conferência e o envio, ou a conferência pode
    // nem ter rodado (app fora do ar na hora). Limpar aqui também é o que
    // impede o endereço morto de ficar preso no settings.
    if (/alvo desconhecido/.test(detail)) {
      await config().update('target', '', vscode.ConfigurationTarget.Workspace);
    }
    return { ok: false, detail };
  }

  // Marca por id, e relendo o sidecar: entre o load lá em cima e agora, o
  // usuário pode ter comentado mais uma coisa. Marcar "tudo que não tinha
  // sentAt" carimbaria como enviado um comentário que não entrou no payload —
  // ele sumiria da fila sem nunca ter chegado ao agente.
  const sentAt = new Date().toISOString();
  const sentIds = new Set(pending.map((comment) => comment.id));
  const current = review.load(root, filePath);
  review.save(
    root,
    filePath,
    current.map((comment) =>
      sentIds.has(comment.id) && !comment.sentAt ? { ...comment, sentAt } : comment
    )
  );

  return {
    ok: true,
    detail: (response.body && response.body.detail) || 'enviado',
    target,
    count: pending.length
  };
}

/// Edição vai por WorkspaceEdit, nunca gravando o arquivo por baixo: assim
/// undo, dirty state e save do VSCode continuam corretos, e uma edição não
/// salva no editor de texto não é atropelada (ADR-005).
async function applyBlockEdit(document, message) {
  const start = Math.max(0, Number(message.line) || 0);
  const end = Math.min(document.lineCount, Number(message.lineEnd) || start + 1);
  const range = new vscode.Range(
    new vscode.Position(start, 0),
    end >= document.lineCount
      ? document.lineAt(document.lineCount - 1).range.end
      : new vscode.Position(end, 0)
  );

  const text = String(message.text || '');
  const replacement = end >= document.lineCount ? text : `${text}\n`;

  const edit = new vscode.WorkspaceEdit();
  edit.replace(document.uri, range, replacement);
  return vscode.workspace.applyEdit(edit);
}

class SpecEditorProvider {
  constructor(context) {
    this.context = context;
  }

  async resolveCustomTextEditor(document, panel) {
    const root = workspaceRootFor(document.uri);
    const filePath = document.uri.fsPath;

    panel.webview.options = {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.file(path.join(this.context.extensionPath, 'media'))]
    };
    panel.webview.html = this.html(panel.webview);

    const push = () => {
      const text = document.getText();
      const comments = review.reanchor(review.load(root, filePath), text);

      panel.webview.postMessage({
        type: 'render',
        html: render(text),
        // O webview precisa do markdown de origem para editar um bloco: o HTML
        // renderizado não permite reconstruir o texto original.
        lines: text.split('\n'),
        comments,
        file: path.relative(root, filePath) || path.basename(filePath),
        target: (config().get('target') || '').trim()
      });
    };

    const changeSub = vscode.workspace.onDidChangeTextDocument((event) => {
      if (event.document.uri.toString() === document.uri.toString()) push();
    });

    // O painel fica vivo escondido (retainContextWhenHidden), então voltar para
    // a aba não dispara resolve de novo. Sem isto, comentário criado enquanto a
    // aba estava fora de vista só apareceria recarregando a janela.
    const viewSub = panel.onDidChangeViewState((event) => {
      if (event.webviewPanel.visible) push();
    });

    // Sidecar pode mudar por fora: outra aba, outro editor, ou o próprio
    // autoteste. Observar o arquivo mantém as threads em dia.
    const sidecar = review.sidecarPath(root, filePath);
    fs.mkdirSync(path.dirname(sidecar), { recursive: true });
    let debounce = null;
    const watcher = fs.watch(path.dirname(sidecar), (_event, name) => {
      if (name && name !== path.basename(sidecar)) return;
      clearTimeout(debounce);
      debounce = setTimeout(push, 120);
    });

    panel.onDidDispose(() => {
      changeSub.dispose();
      viewSub.dispose();
      watcher.close();
      clearTimeout(debounce);
    });

    panel.webview.onDidReceiveMessage(async (message) => {
      switch (message.type) {
        case 'ready':
          push();
          break;

        case 'addComment': {
          const comments = review.load(root, filePath);
          comments.push({
            id: `c${Date.now()}${Math.floor(Math.random() * 1000)}`,
            quote: message.quote || '',
            line: typeof message.line === 'number' ? message.line : 0,
            body: message.body || '',
            createdAt: new Date().toISOString()
          });
          review.save(root, filePath, comments);
          push();
          break;
        }

        case 'deleteComment': {
          const comments = review.load(root, filePath)
            .filter((comment) => comment.id !== message.id);
          review.save(root, filePath, comments);
          push();
          break;
        }

        case 'editBlock':
          await this.applyBlockEdit(document, message);
          break;

        case 'requestChanges': {
          panel.webview.postMessage({ type: 'status', text: 'enviando…', tone: 'busy' });
          try {
            const result = await sendRequestChanges(document.uri);
            panel.webview.postMessage({
              type: 'status',
              text: result.ok
                ? `enviado para ${result.target} (${result.count})`
                : `falhou: ${result.detail}`,
              tone: result.ok ? 'ok' : 'error'
            });
            if (result.ok) push();
          } catch (error) {
            panel.webview.postMessage({
              type: 'status', text: `falhou: ${error.message}`, tone: 'error'
            });
          }
          break;
        }

        case 'pickTarget': {
          const { target, detail } = await resolveTarget({ folder: root, force: true });
          panel.webview.postMessage({
            type: 'status',
            text: target ? `alvo: ${target}` : `alvo mantido: ${detail}`,
            tone: target ? 'ok' : ''
          });
          push();
          break;
        }

        case 'openSource':
          await vscode.commands.executeCommand('vscode.openWith', document.uri, 'default');
          break;

      }
    });
  }

  async applyBlockEdit(document, message) {
    return applyBlockEdit(document, message);
  }

  html(webview) {
    const asset = (name) => webview.asWebviewUri(
      vscode.Uri.file(path.join(this.context.extensionPath, 'media', name))
    );
    const nonce = String(Date.now());
    return `<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
<link rel="stylesheet" href="${asset('preview.css')}">
</head>
<body>
  <header id="bar">
    <span id="file"></span>
    <button id="target" type="button" title="trocar a bancada que recebe">alvo…</button>
    <span id="status"></span>
    <button id="request" type="button">Request changes</button>
    <button id="source" type="button">Ver fonte</button>
  </header>
  <main id="doc"></main>
  <aside id="threads"></aside>
  <div id="bubble" hidden>
    <textarea id="bubbleText" rows="3" placeholder="o que precisa mudar?"></textarea>
    <div id="bubbleActions">
      <button id="bubbleSave" type="button">Comentar</button>
      <button id="bubbleCancel" type="button">Cancelar</button>
    </div>
  </div>
  <script nonce="${nonce}" src="${asset('preview.js')}"></script>
</body>
</html>`;
  }
}

/// Escreve o resultado do autoteste. Precisa garantir o diretório: esta função
/// roda dentro de um setInterval, e uma exceção aqui vira rejeição não tratada
/// no extension host, que morre em silêncio.
function writeSelfTestResult(folder, result) {
  try {
    const dir = path.join(folder.uri.fsPath, '.egeon');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'selftest-result.json'), JSON.stringify(result, null, 2));
  } catch (error) {
    console.error('egeon: falha ao gravar resultado do autoteste', error);
  }
}

/// Autoteste: dispara o mesmo caminho do botão sem depender de clique.
/// O webview do custom editor é um iframe isolado — não dá para dirigi-lo de
/// fora, então esta é a única forma de provar o fluxo ponta a ponta.
function watchSelfTest(context) {
  const folders = vscode.workspace.workspaceFolders || [];
  for (const folder of folders) {
    const trigger = path.join(folder.uri.fsPath, '.egeon', 'selftest.json');
    const timer = setInterval(async () => {
      if (!fs.existsSync(trigger)) return;
      let spec;
      try {
        spec = JSON.parse(fs.readFileSync(trigger, 'utf8'));
      } catch (error) {
        return;
      }
      fs.unlinkSync(trigger);

      const result = { startedAt: new Date().toISOString(), spec };
      try {
        const fileUri = vscode.Uri.file(path.resolve(folder.uri.fsPath, spec.file));
        const root = workspaceRootFor(fileUri);

        // Exercita a edição de bloco pelo MESMO caminho do duplo clique.
        if (spec.action === 'edit') {
          const document = await vscode.workspace.openTextDocument(fileUri);
          result.before = document.getText();
          await applyBlockEdit(document, spec);
          await document.save();
          result.after = document.getText();
          result.ok = result.after !== result.before;
          result.detail = result.ok ? 'bloco editado' : 'texto não mudou';
          writeSelfTestResult(folder, result);
          return;
        }

        const comments = review.load(root, fileUri.fsPath);
        comments.push({
          id: `selftest${Date.now()}`,
          quote: spec.quote || '',
          line: spec.line || 0,
          body: spec.body || 'comentário de autoteste',
          createdAt: new Date().toISOString()
        });
        review.save(root, fileUri.fsPath, comments);

        if (spec.target) {
          await config().update('target', spec.target, vscode.ConfigurationTarget.Workspace);
        }
        Object.assign(result, await sendRequestChanges(fileUri, { interactive: false }));
        result.sidecar = review.sidecarPath(root, fileUri.fsPath);
      } catch (error) {
        result.ok = false;
        result.detail = error.message;
      }

      writeSelfTestResult(folder, result);
    }, 1000);
    context.subscriptions.push({ dispose: () => clearInterval(timer) });
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.window.registerCustomEditorProvider(VIEW_TYPE, new SpecEditorProvider(context), {
      webviewOptions: { retainContextWhenHidden: true },
      supportsMultipleEditorsPerDocument: false
    }),
    vscode.commands.registerCommand('egeon.openSource', async () => {
      const uri = vscode.window.activeTextEditor && vscode.window.activeTextEditor.document.uri;
      if (uri) await vscode.commands.executeCommand('vscode.openWith', uri, 'default');
    }),
    vscode.commands.registerCommand('egeon.pickTarget', async () => {
      const active = vscode.window.activeTextEditor;
      const folders = vscode.workspace.workspaceFolders || [];
      const folder = active
        ? workspaceRootFor(active.document.uri)
        : (folders.length ? folders[0].uri.fsPath : undefined);
      const { target } = await resolveTarget({ folder, force: true });
      if (target) vscode.window.showInformationMessage(`egeon: alvo agora é ${target}`);
    })
  );

  watchSelfTest(context);
}

function deactivate() {}

module.exports = { activate, deactivate };
