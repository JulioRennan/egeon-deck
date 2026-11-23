/// Uma peça de um ícone, na grade de 16 do design system.
sealed class EgShape {
  const EgShape();
}

class EgPath extends EgShape {
  const EgPath(this.d);

  final String d;
}

class EgCircle extends EgShape {
  const EgCircle(this.cx, this.cy, this.r, {this.filled = false});

  final double cx, cy, r;
  final bool filled;
}

class EgRect extends EgShape {
  const EgRect(this.x, this.y, this.width, this.height, this.rx);

  final double x, y, width, height, rx;
}

/// O traço padrão de um ícone (DS `Icon`): 1.5 na grade de 16.
const double egIconStroke = 1.5;

/// Um ícone: formas de traço 1.5 numa grade de 16, na cor do texto ao redor.
class EgIconData {
  const EgIconData(
    this.name,
    this.shapes, {
    this.strokeWidth = egIconStroke,
    this.filled = false,
  });

  /// O nome do DS (`Icon name`), igual ao de `iconNames` do bundle.
  final String name;
  final List<EgShape> shapes;
  final double strokeWidth;

  /// Preenchido além do traço (o `play`).
  final bool filled;
}

/// Os ícones do design system, com os nomes do `Icon` do DS (o objeto `P` do
/// bundle: grade de 16, traço 1.5). Onde as telas do canvas (v3) desenham um
/// caminho próprio, vale o da v3 com o nome do DS ([v3Overrides]); os que só
/// a v3 tem ficam no fim, sem equivalente no DS.
abstract final class EgIcons {
  static const x = EgIconData('x', [EgPath('M4 4l8 8M12 4l-8 8')]);
  static const plus = EgIconData('plus', [EgPath('M8 3.5v9M3.5 8h9')]);
  static const minus = EgIconData('minus', [EgPath('M3.5 8h9')]);
  static const check = EgIconData('check', [EgPath('M3.5 8.5l3 3 6-6.5')]);
  static const chevronDown = EgIconData('chevron-down', [
    EgPath('M4.5 6.5l3.5 3.5 3.5-3.5'),
  ]);
  static const chevronRight = EgIconData('chevron-right', [
    EgPath('M6 3.5L10.5 8 6 12.5'),
  ]);
  static const chevronUp = EgIconData('chevron-up', [
    EgPath('M4.5 9.5L8 6l3.5 3.5'),
  ]);
  static const terminal = EgIconData('terminal', [
    EgRect(1.75, 2.75, 12.5, 10.5, 2),
    EgPath('M4.5 6.25l1.75 1.75-1.75 1.75M8.25 10h2.5'),
  ]);
  static const globe = EgIconData('globe', [
    EgCircle(8, 8, 6.25),
    EgPath(
      'M1.75 8h12.5M8 1.75c1.7 1.8 2.5 3.9 2.5 6.25S9.7 12.45 8 14.25C6.3 12.45 5.5 10.35 5.5 8S6.3 3.55 8 1.75z',
    ),
  ]);
  static const queue = EgIconData('queue', [
    EgPath('M6.5 4h7M6.5 8h7M6.5 12h7M2.5 4h1M2.5 8h1M2.5 12h1'),
  ]);
  static const agent = EgIconData('agent', [
    EgRect(1.75, 3.75, 12.5, 9.5, 2),
    EgPath('M8 3.75V2.25M6.75 10.75h2.5'),
    EgCircle(8, 1.5, 0.75),
    EgCircle(5.5, 7.75, 0.6, filled: true),
    EgCircle(10.5, 7.75, 0.6, filled: true),
  ]);
  static const search = EgIconData('search', [
    EgCircle(7, 7, 4.25),
    EgPath('M10.25 10.25L13.5 13.5'),
  ]);
  static const more = EgIconData('more', [
    EgPath('M3.5 8h.01M8 8h.01M12.5 8h.01'),
  ], strokeWidth: 2.5);
  static const settings = EgIconData('settings', [
    EgPath('M2.5 5h6.5M12 5h1.5M2.5 11h1.5M7 11h6.5M10.5 3.5v3M5.5 9.5v3'),
  ]);
  static const play = EgIconData('play', [
    EgPath('M5 3.5v9l7-4.5z'),
  ], filled: true);
  static const pause = EgIconData('pause', [EgPath('M5.5 3.5v9M10.5 3.5v9')]);
  static const stop = EgIconData('stop', [
    EgPath(
      'M5 4.5h6a.5.5 0 0 1 .5.5v6a.5.5 0 0 1-.5.5H5a.5.5 0 0 1-.5-.5V5a.5.5 0 0 1 .5-.5z',
    ),
  ]);
  static const copy = EgIconData('copy', [
    EgPath(
      'M6.5 5.5h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1zM3.5 10.5a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1',
    ),
  ]);
  static const branch = EgIconData('branch', [
    EgCircle(4.5, 3.5, 1.5),
    EgCircle(4.5, 12.5, 1.5),
    EgCircle(11.5, 4.5, 1.5),
    EgPath('M4.5 5v6M11.5 6c0 3-2.5 4-6 5'),
  ]);
  static const folder = EgIconData('folder', [
    EgPath(
      'M2 4.5a1 1 0 0 1 1-1h3.2l1.5 1.5H13a1 1 0 0 1 1 1v6.5a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1z',
    ),
  ]);
  static const layers = EgIconData('layers', [
    EgPath(
      'M8 2.5l5.75 3L8 8.5l-5.75-3zM2.25 8.25L8 11.25l5.75-3M2.25 11L8 14l5.75-3',
    ),
  ]);
  static const clock = EgIconData('clock', [
    EgPath('M8 2a6 6 0 1 0 0 12A6 6 0 0 0 8 2zM8 4.75V8l2.25 1.5'),
  ]);
  static const coin = EgIconData('coin', [
    EgPath(
      'M8 2a6 6 0 1 0 0 12A6 6 0 0 0 8 2zM10 6.1c-.35-.6-1.1-.95-2-.95-1.1 0-2 .55-2 1.35 0 1.9 4 1 4 2.95 0 .8-.9 1.4-2 1.4-.95 0-1.7-.4-2.05-1M8 4v1.15M8 10.85V12',
    ),
  ]);
  static const alert = EgIconData('alert', [
    EgPath('M8 2.25l6.25 11H1.75zM8 6.5v3M8 11.25v.25'),
  ]);
  static const info = EgIconData('info', [
    EgPath('M8 2a6 6 0 1 0 0 12A6 6 0 0 0 8 2zM8 7.25v3.75M8 4.9v.2'),
  ]);
  static const lock = EgIconData('lock', [
    EgPath(
      'M4.5 7h7a1 1 0 0 1 1 1v4.5a1 1 0 0 1-1 1h-7a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM5.5 7V5a2.5 2.5 0 0 1 5 0v2',
    ),
  ]);
  static const message = EgIconData('message', [
    EgPath(
      'M2.75 4.25a1.5 1.5 0 0 1 1.5-1.5h7.5a1.5 1.5 0 0 1 1.5 1.5v5.5a1.5 1.5 0 0 1-1.5 1.5H7l-3 2.5v-2.5h.25a1.5 1.5 0 0 1-1.5-1.5z',
    ),
  ]);
  static const canvas = EgIconData('canvas', [
    EgPath(
      'M2.5 2.5h4.25v4.25H2.5zM9.25 2.5h4.25v4.25H9.25zM2.5 9.25h4.25v4.25H2.5zM9.25 9.25h4.25v4.25H9.25z',
    ),
  ]);
  static const zoomIn = EgIconData('zoom-in', [
    EgPath(
      'M7 2.75a4.25 4.25 0 1 0 0 8.5 4.25 4.25 0 0 0 0-8.5zM10.25 10.25l3.25 3.25M5 7h4M7 5v4',
    ),
  ]);
  static const zoomOut = EgIconData('zoom-out', [
    EgPath(
      'M7 2.75a4.25 4.25 0 1 0 0 8.5 4.25 4.25 0 0 0 0-8.5zM10.25 10.25l3.25 3.25M5 7h4',
    ),
  ]);
  static const fit = EgIconData('fit', [
    EgPath(
      'M2.5 6V3.5a1 1 0 0 1 1-1H6M10 2.5h2.5a1 1 0 0 1 1 1V6M13.5 10v2.5a1 1 0 0 1-1 1H10M6 13.5H3.5a1 1 0 0 1-1-1V10',
    ),
    EgRect(6, 6, 4, 4, 0.75),
  ]);
  static const pointer = EgIconData('pointer', [
    EgPath('M3.5 2.5l9.5 4.2-4.2 1.5-1.6 4.3z'),
  ]);
  static const hand = EgIconData('hand', [
    EgPath(
      'M5.5 8.5V3.75a1 1 0 0 1 2 0V7.5M7.5 7V2.75a1 1 0 0 1 2 0V7.5M9.5 7.5V3.75a1 1 0 0 1 2 0v5.75a4 4 0 0 1-4 4H7a4 4 0 0 1-3.2-1.6L2.4 10a1 1 0 0 1 1.6-1.2l1.5 1.7',
    ),
  ]);
  static const connect = EgIconData('connect', [
    EgPath(
      'M3.75 10.75a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM12.25 2.25a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zM5 11.25c3.5 0 2.5-6.5 6-6.5',
    ),
  ]);
  static const maestro = EgIconData('maestro', [
    EgPath('M2.75 13.25l7.5-7.5M11.75 2.25a2 2 0 1 0 0 4 2 2 0 0 0 0-4z'),
  ]);
  static const send = EgIconData('send', [EgPath('M8 13V3.5M4 7.5l4-4 4 4')]);
  static const at = EgIconData('at', [
    EgCircle(8, 8, 2.5),
    EgPath('M10.5 8v1a1.75 1.75 0 0 0 3.5 0V8A6 6 0 1 0 11.5 13'),
  ]);
  static const slash = EgIconData('slash', [EgPath('M10.5 2.5l-5 11')]);
  static const trash = EgIconData('trash', [
    EgPath(
      'M2.75 4.5h10.5M6.25 4.5V3h3.5v1.5M4.25 4.5l.6 8.5a1 1 0 0 0 1 1h4.3a1 1 0 0 0 1-1l.6-8.5',
    ),
  ]);
  static const refresh = EgIconData('refresh', [
    EgPath('M13.25 8a5.25 5.25 0 1 1-1.6-3.8'),
    EgPath('M13.25 2.75v2.5h-2.5'),
  ]);
  static const sidebar = EgIconData('sidebar', [
    EgRect(2, 2.75, 12, 10.5, 2),
    EgPath('M6.25 2.75v10.5'),
  ]);
  static const edit = EgIconData('edit', [
    EgPath('M10.25 2.75l3 3-7.5 7.5h-3v-3z'),
  ]);
  static const file = EgIconData('file', [
    EgPath('M4 1.75h5.25l3 3v9.5H4zM9 1.75V5h3.25'),
  ]);
  static const paperclip = EgIconData('paperclip', [
    EgPath(
      'M12.5 7.25l-4.6 4.6a2.75 2.75 0 0 1-3.9-3.9l4.95-4.95a1.75 1.75 0 0 1 2.5 2.5l-4.9 4.9a.75.75 0 0 1-1.05-1.05l4.4-4.4',
    ),
  ]);
  static const maximize = EgIconData('maximize', [
    EgPath('M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5l-4.5 4.5M2.5 13.5L7 9'),
  ]);
  static const expand = EgIconData('expand', [
    EgPath('M4 6l4-4 4 4M4 10l4 4 4-4'),
  ]);
  static const gauge = EgIconData('gauge', [
    EgPath('M2.5 11a5.5 5.5 0 1 1 11 0M8 11l2.5-3.5'),
  ]);
  static const cpu = EgIconData('cpu', [
    EgPath(
      'M4.5 4.5h7v7h-7zM6.5 2v2.5M9.5 2v2.5M6.5 11.5V14M9.5 11.5V14M2 6.5h2.5M2 9.5h2.5M11.5 6.5H14M11.5 9.5H14',
    ),
  ]);
  static const hourglass = EgIconData('hourglass', [
    EgPath(
      'M4 2h8M4 14h8M5 2v2.5c0 1.5 3 2.5 3 3.5S5 10 5 11.5V14M11 2v2.5c0 1.5-3 2.5-3 3.5s3 2 3 3.5V14',
    ),
  ]);
  static const hammer = EgIconData('hammer', [
    EgPath('M8.5 2.5l5 5-1.75 1.75-5-5zM7.6 5.4L2.5 10.5l3 3 5.1-5.1'),
  ]);
  static const octagon = EgIconData('octagon', [
    EgPath('M5.5 2h5L14 5.5v5L10.5 14h-5L2 10.5v-5zM8 5v3.5M8 10.75v.25'),
  ]);
  static const fork = EgIconData('fork', [
    EgPath(
      'M4.5 2.5v3a2 2 0 0 0 2 2h3a2 2 0 0 1 2 2v4M11.5 2.5v3a2 2 0 0 1-2 2M4.5 2.5h.01M11.5 2.5h.01',
    ),
  ]);
  static const broom = EgIconData('broom', [
    EgPath('M10.5 2l-3 5.5M4.5 7.5h6l1.5 6.5H3z M6.5 10.5v3.5M9 10.5v3.5'),
  ]);
  static const external = EgIconData('external', [
    EgPath(
      'M9 2.5h4.5V7M13.5 2.5L7.5 8.5M11.5 9.5v3a1 1 0 0 1-1 1h-7a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1h3',
    ),
  ]);
  static const reply = EgIconData('reply', [
    EgPath('M6 4.5L2.5 8 6 11.5M2.5 8h7a4 4 0 0 1 4 4v.5'),
  ]);

  // Só da v3, sem equivalente no DS.
  static const chevronLeft = EgIconData('chevron-left', [
    EgPath('M10 3.5L5.5 8l4.5 4.5'),
  ]);
  static const rotateCcw = EgIconData('rotate-ccw', [
    EgPath('M2.75 8a5.25 5.25 0 1 0 1.6-3.8'),
    EgPath('M2.75 2.75v2.5h2.5'),
  ]);
  static const filter = EgIconData('filter', [
    EgPath('M2.5 3.5h11l-4.25 5v4l-2.5 1.5v-5.5z'),
  ]);
  static const archive = EgIconData('archive', [
    EgRect(2, 3, 12, 3, 1),
    EgPath('M3 6v6.5a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6M6.5 9h3'),
  ]);
  static const link = EgIconData('link', [
    EgRect(1.75, 2.75, 5.5, 4.5, 1),
    EgRect(8.75, 8.75, 5.5, 4.5, 1),
    EgPath('M7.25 5h1.5a2 2 0 0 1 2 2v1.75'),
  ]);
  static const template = EgIconData('template', [
    EgRect(2, 2.5, 12, 11, 1.5),
    EgPath('M2 6.25h12M6.75 6.25v7.25'),
  ]);
  static const worktree = EgIconData('worktree', [
    EgCircle(4.5, 3.5, 1.5),
    EgCircle(4.5, 12.5, 1.5),
    EgCircle(11.5, 5.5, 1.5),
    EgPath('M4.5 5v6M11.5 7c0 2.5-2 3.5-7 4'),
  ]);
  static const component = EgIconData('component', [
    EgRect(2, 2, 12, 12, 3),
    EgPath('M9.5 4.75l-3 6.5'),
  ]);
  static const arrowRight = EgIconData('arrow-right', [
    EgPath('M3 8h10M9.5 4.5L13 8l-3.5 3.5'),
  ]);

  /// Os nomes do DS cujo caminho vem da v3 e não do `Icon` do DS.
  static const v3Overrides = <String>{
    'terminal',
    'globe',
    'queue',
    'agent',
    'search',
    'check',
    'plus',
    'x',
    'chevron-down',
    'chevron-right',
    'edit',
    'pointer',
    'hand',
    'hammer',
    'sidebar',
    'folder',
    'message',
    'branch',
    'send',
    'at',
    'refresh',
    'fit',
  };

  static const all = <EgIconData>[
    x,
    plus,
    minus,
    check,
    chevronDown,
    chevronRight,
    chevronUp,
    terminal,
    globe,
    queue,
    agent,
    search,
    more,
    settings,
    play,
    pause,
    stop,
    copy,
    branch,
    folder,
    layers,
    clock,
    coin,
    alert,
    info,
    lock,
    message,
    canvas,
    zoomIn,
    zoomOut,
    fit,
    pointer,
    hand,
    connect,
    maestro,
    send,
    at,
    slash,
    trash,
    refresh,
    sidebar,
    edit,
    file,
    paperclip,
    maximize,
    expand,
    gauge,
    cpu,
    hourglass,
    hammer,
    octagon,
    fork,
    broom,
    external,
    reply,
    chevronLeft,
    rotateCcw,
    filter,
    archive,
    link,
    template,
    worktree,
    component,
    arrowRight,
  ];

  static final _byName = {for (final icon in all) icon.name: icon};

  /// O ícone pelo nome do DS, ou nulo.
  static EgIconData? byName(String name) => _byName[name];
}
