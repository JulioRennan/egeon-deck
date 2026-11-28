/// O gesto do mouse sobre a tela do terminal, cru. A UI não decide nada: o
/// terminal escolhe entre mouse do programa, seleção (arrasto, palavra, linha,
/// ⇧-clique estende, clique limpa), rolagem e setas na tela alternativa.
enum PointerKind { press, release, drag, move, wheel }

enum PointerButton { left, middle, right }

class TerminalPointer {
  const TerminalPointer({
    required this.kind,
    required this.x,
    required this.y,
    required this.timeMs,
    this.button,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.lines,
  });

  final PointerKind kind;

  /// Omitido em `move` e `wheel`.
  final PointerButton? button;

  /// Em CÉLULAS, fracionário, relativo ao canto da vista (3.4 = 40% dentro da
  /// coluna 3). No `drag` pode vir fora da vista (<0 ou ≥ linhas).
  final double x;
  final double y;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  /// Relógio monotônico da UI: o core conta clique duplo e triplo com ele
  /// (intervalo de 500 ms).
  final int timeMs;

  /// Só em `wheel`: positivo sobe, em linhas inteiras.
  final int? lines;

  /// Os campos da mensagem, sem `id` e `cmd`.
  Map<String, Object?> toMap() => {
    'kind': kind.name,
    if (button != null) 'button': button!.name,
    'x': x,
    'y': y,
    'mods': {
      if (ctrl) 'ctrl': true,
      if (alt) 'alt': true,
      if (shift) 'shift': true,
      if (meta) 'meta': true,
    },
    'time_ms': timeMs,
    if (lines != null) 'lines': lines,
  };

  /// O mesmo gesto noutro instante: o timer de arrasto fora da vista repete o
  /// último `drag` a cada 50 ms.
  TerminalPointer at(int timeMs) => TerminalPointer(
    kind: kind,
    x: x,
    y: y,
    timeMs: timeMs,
    button: button,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    meta: meta,
    lines: lines,
  );
}

/// Rolar a vista: pela barra de rolagem e pelos atalhos.
sealed class TerminalScroll {
  const TerminalScroll();

  /// Corpo da mensagem: `{"rows": -3}`, `"top"` ou `"bottom"`.
  Object toWire();
}

class ScrollRows extends TerminalScroll {
  const ScrollRows(this.rows);

  /// Negativo sobe.
  final int rows;

  @override
  Object toWire() => {'rows': rows};
}

class ScrollTop extends TerminalScroll {
  const ScrollTop();

  @override
  Object toWire() => 'top';
}

class ScrollBottom extends TerminalScroll {
  const ScrollBottom();

  @override
  Object toWire() => 'bottom';
}
