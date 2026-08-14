// place.js — posiciona janelas reais de qualquer app via Accessibility API.
// Uso: osascript -l JavaScript place.js '<json>'
//
// json = {
//   "display": 0,
//   "retries": 20,
//   "waitMs": 400,
//   "targets": [
//     { "proc": "Code", "titleContains": "mega-brain", "frac": [0,0,0.62,1] },
//     { "proc": "Terminal", "titleContains": "MB:deck:back", "frac": [0.62,0,0.38,0.5] }
//   ]
// }
//
// frac = [x, y, largura, altura] como fracao da visibleFrame do display
// (visibleFrame ja desconta barra de menu e Dock).

ObjC.import('AppKit');

function sleepMs(ms) {
  $.NSThread.sleepForTimeInterval(ms / 1000.0);
}

// AppKit usa origem embaixo-esquerda; a Accessibility API usa cima-esquerda,
// com y medido a partir do topo do display principal. Converte aqui.
function visibleFrameForDisplay(index) {
  var screens = $.NSScreen.screens;
  var mainHeight = screens.objectAtIndex(0).frame.size.height;
  var i = Math.max(0, Math.min(index || 0, screens.count - 1));
  var v = screens.objectAtIndex(i).visibleFrame;
  return {
    x: v.origin.x,
    y: mainHeight - (v.origin.y + v.size.height),
    w: v.size.width,
    h: v.size.height
  };
}

function findWindow(se, procName, titleContains) {
  var proc;
  try {
    proc = se.processes[procName];
    proc.name(); // forca a resolucao; lanca se o processo nao existe
  } catch (e) {
    return { err: 'processo "' + procName + '" nao esta rodando' };
  }

  var wins;
  try {
    wins = proc.windows();
  } catch (e) {
    return { err: 'sem permissao de Acessibilidade para "' + procName + '"' };
  }

  var seen = [];
  for (var i = 0; i < wins.length; i++) {
    var title = '';
    try { title = wins[i].title(); } catch (e) { /* janela sem titulo acessivel */ }
    if (!title) continue;
    seen.push(title);
    if (title.indexOf(titleContains) !== -1) return { win: wins[i], title: title };
  }
  return { err: 'nenhuma janela com "' + titleContains + '" (vi: ' + seen.join(' | ') + ')' };
}

function run(argv) {
  var cfg = JSON.parse(argv[0]);
  var vf = visibleFrameForDisplay(cfg.display);
  var se = Application('System Events');
  var retries = cfg.retries || 20;
  var waitMs = cfg.waitMs || 400;

  var pending = cfg.targets.slice();
  var log = [];

  for (var attempt = 0; attempt <= retries && pending.length; attempt++) {
    if (attempt > 0) sleepMs(waitMs);

    var stillPending = [];
    for (var i = 0; i < pending.length; i++) {
      var t = pending[i];
      var found = findWindow(se, t.proc, t.titleContains);

      if (found.err) {
        // ultima tentativa: reporta; caso contrario, tenta de novo
        if (attempt === retries) log.push('FALHA ' + t.proc + ': ' + found.err);
        else stillPending.push(t);
        continue;
      }

      var x = Math.round(vf.x + t.frac[0] * vf.w);
      var y = Math.round(vf.y + t.frac[1] * vf.h);
      var w = Math.round(t.frac[2] * vf.w);
      var h = Math.round(t.frac[3] * vf.h);

      try {
        found.win.position = [x, y];
        found.win.size = [w, h];
        log.push('OK    ' + t.proc + ' [' + found.title + '] -> ' + x + ',' + y + ' ' + w + 'x' + h);
      } catch (e) {
        log.push('FALHA ' + t.proc + ': nao consegui mover/redimensionar (' + e.message + ')');
      }
    }
    pending = stillPending;
  }

  return log.join('\n');
}
