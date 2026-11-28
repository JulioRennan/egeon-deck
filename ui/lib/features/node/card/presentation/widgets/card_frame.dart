import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/identity.dart';
import '../../../../../commons/widgets/eg/menu.dart';
import '../../../../../commons/widgets/eg/pressable.dart';
import '../../../../../commons/widgets/eg/status_dot.dart';
import '../../../../../commons/widgets/eg/tooltip.dart';
import '../../../../../core/domain/entities/workbench_node.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_tokens.dart';
import '../../../../../theme/egeon_type.dart';
import '../../domain/entities/card_activity.dart';
import 'card_state.dart';
import 'subtitle_link.dart';

/// A moldura de todo nó do canvas: cabeçalho (área de arrasto), corpo, alça de
/// resize e, nos terminais, o `+` de onde sai a ligação.
///
/// Os três estados da moldura se distinguem sem depender só da cor: o agente
/// que **precisa de você** troca a borda e o anel para `attention` (e o ponto
/// pulsa), o **maestro** ganha, em `sand`, a faixa no topo, a etiqueta e o anel de 4, e o
/// arrastado leva a sombra de arrasto.
///
/// Todos os pontos que sobem são GLOBAIS (pixels de tela): o card vive num
/// documento magnificado, e quem divide pelo zoom é o canvas.
class CardFrame extends StatefulWidget {
  const CardFrame({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.height,
    required this.linkable,
    required this.child,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onResize,
    required this.onResizeEnd,
    required this.onClose,
    required this.onPortDrag,
    required this.onPortRelease,
    required this.onPortCancel,
    this.titleTooltip,
    this.onOpenFolder,
    this.activity = CardActivity.none,
    this.onRetry,
    this.identity,
    this.maestro = false,
    this.accessory,
    this.onConfigure,
    this.onWorktree,
    this.focusColor,
    super.key,
  });

  final String id;
  final NodeKind kind;
  final String title;

  /// A dica do título: o endereço e, no agente, o nome do CLI.
  final String? titleTooltip;

  /// O ⌘-clique no subtítulo abre a pasta; nulo onde o subtítulo não é pasta.
  final VoidCallback? onOpenFolder;
  final String subtitle;

  /// Altura do card no documento: a porta fica no meio dela.
  final double height;

  /// Tem o `+` de onde sai a ligação: só terminal liga.
  final bool linkable;
  final Widget child;

  /// O que o agente está fazendo, como o core diz: o ponto do cabeçalho, a
  /// borda e o anel. Só agente tem tentativa agendada ([onRetry]).
  final CardActivity activity;
  final void Function({required bool now})? onRetry;

  /// A cor de identidade do agente (`agentIdentity`, a mesma do chat): o nome,
  /// a borda e o anel. O maestro não usa a dele: o card inteiro fica em `sand`.
  final Identity? identity;

  /// O maestro se distingue no card inteiro (ADR-066), sempre em `sand`.
  final bool maestro;

  /// A linha de controles embaixo do cabeçalho do agente (modelo, esforço,
  /// contexto…). Sem ela, o cabeçalho fica como é.
  final Widget? accessory;

  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  /// Delta do mouse, em pixels de tela.
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onClose;

  /// A cor da bancada: a borda do card em que você está digitando a leva
  /// (ADR-086). Sem ela, o foco não muda a borda.
  final Color? focusColor;

  /// O lápis do cabeçalho: configurar este nó (no agente, "Editar papel e
  /// regras"; no shell, "Editar nome e comando").
  final VoidCallback? onConfigure;

  /// "Nova worktree para este terminal…": só quem abre pasta (shell e
  /// agente).
  final VoidCallback? onWorktree;
  final ValueChanged<Offset> onPortDrag;
  final ValueChanged<Offset> onPortRelease;
  final VoidCallback onPortCancel;

  /// O cabeçalho do agente (56) é maior que o dos outros nós (50).
  static double headerHeightOf(NodeKind kind) =>
      kind == NodeKind.agent ? 56 : 50;

  /// A linha de controles do agente.
  static const accessoryHeight = 36.0;
  static const radius = EgeonRadius.lg - 2;
  static const gripSize = 16.0;
  static const portSize = 18.0;

  @override
  State<CardFrame> createState() => _CardFrameState();
}

class _CardFrameState extends State<CardFrame> {
  var _dragging = false;

  /// O foco do teclado está em algo dentro do card (o terminal, um campo).
  var _focused = false;

  bool get _isAgent => widget.kind == NodeKind.agent;

  double get _headerHeight => CardFrame.headerHeightOf(widget.kind);

  /// Onde o cabeçalho acaba: a linha do nome mais a faixa, quando há.
  double get _headerExtent =>
      _headerHeight +
      (widget.accessory == null ? 0 : CardFrame.accessoryHeight);

  Identity get _identity => widget.identity ?? Identity.slate;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final state = CardState.of(widget.activity);
    final alert = state == CardState.attention;
    // O maestro é amarelo (`sand`) sempre, e não na cor do agente: o destaque
    // do cabeçalho, a borda e o anel são dele.
    final id = _isAgent && widget.maestro
        ? Identity.sand.color(c)
        : _identity.color(c);
    final focus = _focused ? widget.focusColor : null;

    Color border;
    Color? ring;
    double ringWidth = 3;
    Color? glow;
    var shadowAlpha = 0x66;
    var lift = 16.0;
    var blur = 40.0;
    if (alert) {
      border = c.attention.withValues(alpha: 0.7);
      ring = c.attention.withValues(alpha: 0.14);
    } else if (_isAgent && widget.maestro) {
      border = id.withValues(alpha: 0.9);
      ring = id.withValues(alpha: 0.17);
      ringWidth = 4;
      glow = id.withValues(alpha: 0.12);
      shadowAlpha = 0x80;
      lift = 20;
      blur = 48;
    } else if (_isAgent) {
      border = id.withValues(alpha: 0.5);
      ring = id.withValues(alpha: 0.08);
    } else if (state == CardState.error) {
      border = c.danger.withValues(alpha: 0.4);
    } else {
      border = EgeonColors.overlay10;
    }
    final focused = focus != null && !alert;
    if (focused) border = focus.withValues(alpha: 0.95);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (inside) => setState(() => _focused = inside),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.graphite,
          borderRadius: BorderRadius.circular(CardFrame.radius),
          border: Border.all(color: border, width: focused ? 2 : 1),
          boxShadow: _dragging
              ? EgeonShadow.drag
              : [
                  if (ring != null)
                    BoxShadow(color: ring, spreadRadius: ringWidth),
                  if (glow != null) BoxShadow(color: glow, blurRadius: 48),
                  BoxShadow(
                    color: Color(shadowAlpha << 24),
                    blurRadius: blur,
                    offset: Offset(0, lift),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CardFrame.radius - 1),
          child: Stack(
            children: [
              Positioned.fill(top: _headerExtent, child: widget.child),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _headerExtent,
                child: _header(c, id, state),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                width: CardFrame.gripSize,
                height: CardFrame.gripSize,
                child: _grip(c),
              ),
              if (widget.linkable)
                Positioned(
                  right: 1,
                  top: widget.height / 2 - CardFrame.portSize / 2,
                  width: CardFrame.portSize,
                  height: CardFrame.portSize,
                  child: _Port(
                    key: ValueKey('port-${widget.id}'),
                    onDrag: widget.onPortDrag,
                    onRelease: widget.onPortRelease,
                    onCancel: widget.onPortCancel,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// O botão direito no cabeçalho, e só nele: o corpo é do terminal e da
  /// página, cada um com o menu dele.
  void _headerMenu(Offset position) {
    final configure = widget.onConfigure;
    final worktree = widget.onWorktree;
    if (configure == null && worktree == null) return;
    showMenu(
      context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      width: 280,
      items: [
        if (configure != null)
          MenuItem('Configurar ${widget.id}…', onSelected: configure),
        if (worktree != null)
          MenuItem('Nova worktree para este terminal…', onSelected: worktree),
        const MenuSeparator(),
        MenuItem(
          'Remover ${widget.id}…',
          danger: true,
          onSelected: widget.onClose,
        ),
      ],
    );
  }

  /// Arrastar pelo cabeçalho move o nó no espaço do canvas. Listener cru, e não
  /// `GestureDetector`: o ⌥ panorâmica por cima do nó, e quem decide isso lê o
  /// modificador do próprio evento — não há "tecla pressionada" para grudar.
  ///
  /// A camada de arrasto fica ATRÁS do conteúdo, e não em volta: o Listener de um
  /// ancestral veria também o gesto dos controles da faixa (o slider arrastaria o
  /// card junto). Atrás, só o que nenhum controle pegou chega nela.
  Widget _header(EgeonColors c, Color id, CardState state) {
    final maestro = _isAgent && widget.maestro;
    return MouseRegion(
      // Seta onde se arrasta (ADR-048): a mão é de quem responde a clique.
      cursor: SystemMouseCursors.basic,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                if (e.buttons == kSecondaryButton) {
                  _headerMenu(e.position);
                  return;
                }
                if (e.buttons != kPrimaryButton ||
                    HardwareKeyboard.instance.isAltPressed) {
                  return;
                }
                setState(() => _dragging = true);
                widget.onDragStart(e.position);
              },
              onPointerMove: (e) {
                if (_dragging) widget.onDrag(e.position);
              },
              onPointerUp: (_) => _endDrag(),
              onPointerCancel: (_) => _endDrag(),
              child: Column(
                children: [
                  SizedBox(
                    height: _headerHeight,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: maestro
                            ? LinearGradient(
                                stops: const [0, 0.7, 1],
                                colors: [
                                  id.withValues(alpha: 0.14),
                                  id.withValues(alpha: 0.03),
                                  id.withValues(alpha: 0),
                                ],
                              )
                            : null,
                        border: _isAgent
                            ? null
                            : Border(bottom: BorderSide(color: c.lineSubtle)),
                      ),
                      child: maestro
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                height: 2,
                                width: double.infinity,
                                child: ColoredBox(color: id),
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (widget.accessory != null)
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.lineSubtle)),
                        ),
                        child: const SizedBox(width: double.infinity),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 8,
            top: 0,
            height: _headerHeight,
            child: Row(
              children: [
                Expanded(child: _titles(c, id)),
                if (widget.onWorktree != null)
                  _HeaderButton(
                    key: const ValueKey('card-worktree'),
                    icon: EgIcons.worktree,
                    tooltip: _isAgent
                        ? 'Rodar numa worktree'
                        : 'Nova worktree para este terminal…',
                    onTap: widget.onWorktree!,
                  ),
                if (widget.onConfigure != null)
                  _HeaderButton(
                    key: const ValueKey('card-configure'),
                    icon: EgIcons.edit,
                    tooltip: switch (widget.kind) {
                      NodeKind.agent => 'Editar papel e regras',
                      NodeKind.shell => 'Editar nome e comando',
                      NodeKind.web || NodeKind.queue => 'Configurar este nó',
                    },
                    onTap: widget.onConfigure!,
                  ),
                _HeaderButton(
                  key: const ValueKey('card-close'),
                  icon: EgIcons.x,
                  tooltip: _isAgent ? 'Fechar' : 'Remover nó',
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
          if (widget.accessory != null)
            Positioned(
              left: 8,
              right: 8,
              top: _headerHeight,
              height: CardFrame.accessoryHeight,
              child: widget.accessory!,
            ),
        ],
      ),
    );
  }

  Widget _stateDot() => CardStateDot(
    activity: widget.activity,
    onRetry: _isAgent ? widget.onRetry : null,
  );

  Widget _titles(EgeonColors c, Color id) {
    final maestro = _isAgent && widget.maestro;
    final title = _passive(
      widget.titleTooltip,
      Text(
        widget.title,
        key: const ValueKey('card-title'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: EgeonType.label.copyWith(
          fontSize: _isAgent ? 14 : 13,
          height: 18 / (_isAgent ? 14 : 13),
          fontWeight: FontWeight.w600,
          color: _isAgent ? id : c.textPrimary,
          decoration: TextDecoration.none,
        ),
      ),
    );
    final lines = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: title),
            if (maestro) ...[
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'Maestro: monta o time, define quem fala com quem e '
                    'aprova as permissões',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: id.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: SizedBox(
                    height: 20,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Center(
                        child: Text(
                          'maestro',
                          style: EgeonType.caption.copyWith(
                            color: id,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        SubtitleLink(text: widget.subtitle, onOpen: widget.onOpenFolder),
      ],
    );
    final lead = _isAgent
        ? _stateDot()
        : widget.kind == NodeKind.queue
        // A fila não tem estado de terminal: só o ícone da lista (14).
        ? EgIcon(_kindIcon(widget.kind), size: 14, color: c.textSecondary)
        : Stack(
            clipBehavior: Clip.none,
            children: [
              EgIcon(_kindIcon(widget.kind), color: c.textSecondary),
              Positioned(
                right: -3,
                bottom: -3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: c.graphite, spreadRadius: 2)],
                  ),
                  child: StatusDot(
                    CardState.of(widget.activity).status,
                    size: StatusDotSize.sm,
                    animated: true,
                  ),
                ),
              ),
            ],
          );
    return Row(
      children: [
        lead,
        const SizedBox(width: 10),
        Expanded(child: lines),
      ],
    );
  }

  static EgIconData _kindIcon(NodeKind kind) => switch (kind) {
    NodeKind.shell => EgIcons.terminal,
    NodeKind.agent => EgIcons.agent,
    NodeKind.web => EgIcons.globe,
    NodeKind.queue => EgIcons.queue,
  };

  /// Texto do cabeçalho: não pega gesto (o arrasto do card passa por ele), mas
  /// mostra a dica se houver.
  Widget _passive(String? tooltip, Widget text) => switch (tooltip) {
    final message? when message.isNotEmpty => Tooltip(
      message: message,
      child: IgnorePointer(child: text),
    ),
    _ => IgnorePointer(child: text),
  };

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onDragEnd();
  }

  Widget _grip(EgeonColors c) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (e) {
        if (e.buttons == kPrimaryButton) widget.onResize(e.delta);
      },
      onPointerUp: (_) => widget.onResizeEnd(),
      onPointerCancel: (_) => widget.onResizeEnd(),
      child: CustomPaint(painter: _GripPainter(c.textDisabled)),
    ),
  );
}

class _GripPainter extends CustomPainter {
  _GripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var offset = 4.0; offset <= 12; offset += 4) {
      canvas.drawLine(
        Offset(size.width - offset, size.height - 2),
        Offset(size.width - 2, size.height - offset),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}

/// Um botão do cabeçalho (`.nb` do DS): 26, raio 6, ícone de 14 em `textMuted`
/// que acende no hover.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final EgIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onPressed: onTap,
          semanticLabel: tooltip,
          builder: (context, s) => DecoratedBox(
            decoration: BoxDecoration(
              color: s.pressed
                  ? c.steelActive
                  : s.hovered
                  ? c.steel
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: EgIcon(
                  icon,
                  size: 14,
                  color: s.hovered || s.pressed ? c.textPrimary : c.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// O `+` na borda direita do terminal, como no n8n: diz que dali sai conexão, e
/// é de onde você arrasta para criar uma.
class _Port extends StatefulWidget {
  const _Port({
    required this.onDrag,
    required this.onRelease,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onCancel;
  final ValueChanged<Offset> onDrag;
  final ValueChanged<Offset> onRelease;

  @override
  State<_Port> createState() => _PortState();
}

class _PortState extends State<_Port> {
  var _hovering = false;
  var _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _dragging;
    final c = context.eg;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        key: const ValueKey('card-port'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (e.buttons == kPrimaryButton) setState(() => _dragging = true);
        },
        onPointerMove: (e) {
          if (_dragging) widget.onDrag(e.position);
        },
        onPointerUp: (e) {
          if (!_dragging) return;
          setState(() => _dragging = false);
          widget.onRelease(e.position);
        },
        onPointerCancel: (e) {
          if (!_dragging) return;
          setState(() => _dragging = false);
          // Avisa quem desenha a linha tracejada: sem isto ela fica presa.
          widget.onCancel();
        },
        child: CustomPaint(
          painter: _PortPainter(
            active: active,
            fill: active ? c.accent : c.steelActive,
            plus: active ? c.onAccent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PortPainter extends CustomPainter {
  _PortPainter({required this.active, required this.fill, required this.plus});

  final bool active;
  final Color fill;
  final Color plus;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = (Offset.zero & size).deflate(2);
    canvas.drawOval(circle, Paint()..color = fill);
    final inset = circle.deflate(4);
    canvas.drawPath(
      Path()
        ..moveTo(inset.left, inset.center.dy)
        ..lineTo(inset.right, inset.center.dy)
        ..moveTo(inset.center.dx, inset.top)
        ..lineTo(inset.center.dx, inset.bottom),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = plus,
    );
  }

  @override
  bool shouldRepaint(_PortPainter old) =>
      old.active != active || old.fill != fill || old.plus != plus;
}
