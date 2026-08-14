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

/// Pergunta o alvo uma vez e guarda. Os endereços vêm do próprio app, então a
/// lista nunca fica desatualizada em relação aos workspaces abertos.
async function resolveTarget({ interactive = true } = {}) {
  const configured = (config().get('target') || '').trim();
  if (configured) return configured;
  if (!interactive) return '';

  let targets = [];
  try {
    targets = await socket.listTargets(socketPath());
  } catch (error) {
    vscode.window.showErrorMessage(`egeon: ${error.message}`);
    return '';
  }
  if (!targets.length) {
    vscode.window.showErrorMessage('egeon: nenhuma sessão de agente registrada no app.');
    return '';
  }

  const picked = await vscode.window.showQuickPick(targets, {
    title: 'egeon — para qual sessão vão os comentários?',
    placeHolder: 'ex: deck/claude-back'
  });
  if (!picked) return '';

  await config().update('target', picked, vscode.ConfigurationTarget.Workspace);
  return picked;
}

/// Envia os comentários pendentes como UM prompt na sessão viva do agente.
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

  const target = await resolveTarget({ interactive });
  if (!target) return { ok: false, detail: 'nenhum alvo escolhido' };

  const payload = review.buildDispatchPayload({
    target,
    relativePath: path.relative(root, filePath) || path.basename(filePath),
    comments: pending
  });

  const response = await socket.dispatch(socketPath(), payload);
  if (response.status !== 200 || (response.body && response.body.ok === false)) {
    const detail = (response.body && response.body.error) || `HTTP ${response.status}`;
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
      await config().update('target', '', vscode.ConfigurationTarget.Workspace);
      const target = await resolveTarget();
      if (target) vscode.window.showInformationMessage(`egeon: alvo agora é ${target}`);
    })
  );

  watchSelfTest(context);
}

function deactivate() {}

module.exports = { activate, deactivate };
