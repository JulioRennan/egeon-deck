import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';
import '../../../../../theme/app_theme.dart';
import '../../../../../commons/widgets/app_tooltip.dart';
import '../../../../../commons/widgets/attention_ring.dart';
import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../core/domain/entities/workbench_node.dart';
import 'card_accent.dart';
import 'subtitle_link.dart';

/// A moldura de todo nó do canvas: cabeçalho (área de arrasto), corpo, alça de
/// resize e, nos terminais, o `+` de onde sai a ligação.
///
/// Todos os pontos que sobem são GLOBAIS (pixels de tela): o card vive num
/// documento magnificado, e quem divide pelo zoom é o canvas.
class CardFrame extends StatefulWidget {
  const CardFrame({
    required this.id,
    required this.kind,
    required this.title,
    this.titleTooltip,
    this.onOpenFolder,
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
    this.status,
    this.titleColor,
    this.maestro = false,
    this.accent,
    this.accessory,
    this.needsAttention = false,
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

  /// O canto direito da primeira linha: o que está acontecendo agora.
  final Widget? status;

  /// O título leva a cor do estado quando ele tem tom; sem, a do tipo.
  final Color? titleColor;

  /// O maestro se distingue no card inteiro: borda mais forte e grossa (ADR-066).
  final bool maestro;
  final Color? accent;

  /// Uma faixa embaixo do cabeçalho — o modelo e o esforço do agente. Faixa à
  /// parte, com fundo próprio: ao lado dos ícones ela disputava largura com o
  /// nome do nó. Sem ela, o cabeçalho fica como sempre foi.
  final Widget? accessory;

  /// Alguém espera você neste card. A borda acende, e gira, como a bancada na
  /// barra lateral: com zoom out o cabeçalho fica ilegível muito antes de o
  /// card sumir, e é aí que você mais precisa achar quem parou.
  final bool needsAttention;

  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  /// Delta do mouse, em pixels de tela.
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onClose;

  /// A cor da bancada: a borda do card em que você está digitando a leva,
  /// a mesma do brilho do canvas (ADR-086). Sem ela, o foco não muda a borda.
  final Color? focusColor;

  /// O lápis do cabeçalho: configurar este nó. Sem ele, o nó não se configura
  /// por aqui (só terminal tem).
  final VoidCallback? onConfigure;

  /// "Nova worktree para este terminal…": só quem abre pasta (shell e
  /// agente). Botão no cabeçalho e item do botão direito.
  final VoidCallback? onWorktree;
  final ValueChanged<Offset> onPortDrag;
  final ValueChanged<Offset> onPortRelease;
  final VoidCallback onPortCancel;

  /// Duas linhas no cabeçalho: nome em cima, pasta embaixo.
  static const headerHeight = 46.0;
  static const radius = 10.0;
  static const gripSize = 16.0;
  static const portSize = 18.0;
  static const accessoryHeight = 46.0;

  @override
  State<CardFrame> createState() => _CardFrameState();
}

class _CardFrameState extends State<CardFrame> {
  var _dragging = false;

  /// O foco do teclado está em algo dentro do card (o terminal, um campo).
  var _focused = false;

  /// Onde o cabeçalho acaba: a linha do nome mais a faixa, quando há.
  double get _headerExtent =>
      CardFrame.headerHeight +
      (widget.accessory == null ? 0 : CardFrame.accessoryHeight);

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? CardAccent.of(widget.kind);
    final alert = widget.needsAttention;
    final focus = _focused ? widget.focusColor : null;
    // Alerta ganha de foco: quem espera você é mais urgente do que onde você
    // está.
    final (borderColor, borderWidth) = alert
        // Apagada por baixo do giro: cheia, o traço laranja sumia sobre ela.
        ? (AppColors.attention.withValues(alpha: 0.35), 2.0)
        : focus != null
        ? (focus.withValues(alpha: 0.95), 2.0)
        : (accent.withValues(alpha: 0.55), 1.0);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (inside) => setState(() => _focused = inside),
      child: AttentionRing(
        tone: alert ? AttentionTone.asking : null,
        radius: CardFrame.radius,
        lineWidth: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(CardFrame.radius),
            // Alerta ganha da cor do tipo: apagada por baixo do giro, cheia o traço
            // laranja sumia sobre ela.
            border: Border.all(color: borderColor, width: borderWidth),
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
                  child: _header(accent),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: CardFrame.gripSize,
                  height: CardFrame.gripSize,
                  child: _grip(),
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
      ),
    );
  }

  /// O botão direito no cabeçalho, e só nele: o corpo é do terminal e da
  /// página, cada um com o menu dele.
  void _headerMenu(Offset position) {
    final configure = widget.onConfigure;
    final worktree = widget.onWorktree;
    if (configure == null && worktree == null) return;
    showContextMenu(
      context,
      position: position,
      entries: [
        if (configure != null) MenuEntry('Configurar ${widget.id}…', configure),
        if (worktree != null)
          MenuEntry('Nova worktree para este terminal…', worktree),
        const MenuEntry.separator(),
        MenuEntry('Remover ${widget.id}…', widget.onClose),
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
  Widget _header(Color accent) => MouseRegion(
    cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
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
                const SizedBox(
                  height: CardFrame.headerHeight,
                  width: double.infinity,
                  child: ColoredBox(color: Color(0xFF292929)),
                ),
                if (widget.accessory != null)
                  Expanded(
                    child: Column(
                      children: [
                        Container(height: 1, color: AppColors.white(0.07)),
                        const Expanded(
                          child: SizedBox(
                            width: double.infinity,
                            child: ColoredBox(color: Color(0xFF202020)),
                          ),
                        ),
                        Container(height: 1, color: AppColors.black(0.35)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 0,
          height: CardFrame.headerHeight,
          child: Row(
            children: [
              Expanded(child: _titles(accent)),
              // Estava só no menu do botão direito, e menu de contexto é onde
              // funcionalidade vai morrer: quem não sabe que existe não clica
              // com o direito para descobrir.
              if (widget.onWorktree != null)
                _HeaderButton(
                  key: const ValueKey('card-worktree'),
                  tooltip: 'Nova worktree para este terminal…',
                  painter: (lit) => _BranchPainter(lit),
                  onTap: widget.onWorktree!,
                ),
              if (widget.onConfigure != null)
                _HeaderButton(
                  key: const ValueKey('card-configure'),
                  tooltip: 'Configurar este nó',
                  painter: (lit) => _PencilPainter(lit),
                  onTap: widget.onConfigure!,
                ),
              _HeaderButton(
                key: const ValueKey('card-close'),
                tooltip: 'Remover nó',
                painter: (lit) => _CrossPainter(lit),
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        if (widget.accessory != null)
          Positioned(
            left: 12,
            right: 12,
            top: CardFrame.headerHeight,
            height: CardFrame.accessoryHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: widget.accessory,
            ),
          ),
      ],
    ),
  );

  Widget _titles(Color accent) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: _passive(
              widget.titleTooltip,
              Text(
                widget.title,
                key: const ValueKey('card-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.textStyle.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  // O título do maestro é dourado sempre: o estado já tem cor
                  // na linha ao lado, e o dourado é o que o acha na tela.
                  color: widget.maestro ? accent : widget.titleColor ?? accent,
                ),
              ),
            ),
          ),
          if (widget.status != null) ...[
            const SizedBox(width: 8),
            Flexible(child: widget.status!),
          ],
        ],
      ),
      const SizedBox(height: 3),
      SubtitleLink(text: widget.subtitle, onOpen: widget.onOpenFolder),
    ],
  );

  /// Texto do cabeçalho: não pega gesto (o arrasto do card passa por ele), mas
  /// mostra a dica se houver.
  Widget _passive(String? tooltip, Widget text) => switch (tooltip) {
    final message? when message.isNotEmpty => AppTooltip(
      message: message,
      passThrough: true,
      child: IgnorePointer(child: text),
    ),
    _ => IgnorePointer(child: text),
  };

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onDragEnd();
  }

  Widget _grip() => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (e) {
        if (e.buttons == kPrimaryButton) widget.onResize(e.delta);
      },
      onPointerUp: (_) => widget.onResizeEnd(),
      onPointerCancel: (_) => widget.onResizeEnd(),
      child: CustomPaint(painter: _GripPainter()),
    ),
  );
}

class _GripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white(0.25)
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
  bool shouldRepaint(_GripPainter old) => false;
}

/// Um botão do cabeçalho: o lápis e o X.
class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.painter,
    required this.onTap,
    required this.tooltip,
    super.key,
  });

  final CustomPainter Function(bool lit) painter;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: widget.tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hovering ? AppColors.white(0.10) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: CustomPaint(painter: widget.painter(_hovering)),
        ),
      ),
    ),
  );
}

/// Lápis, e não os controles deslizantes: o botão edita o nó, e ninguém lê
/// controles deslizantes como "editar".
class _PencilPainter extends CustomPainter {
  _PencilPainter(this.lit);

  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white(lit ? 0.9 : 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final c = size.center(Offset.zero);
    final tip = c + const Offset(-5, 5);
    final top = c + const Offset(4, -4);
    canvas
      ..drawLine(tip, top, paint)
      ..drawLine(top, top + const Offset(1.5, 1.5), paint)
      ..drawLine(tip, tip + const Offset(3, 0), paint);
  }

  @override
  bool shouldRepaint(_PencilPainter old) => old.lit != lit;
}

/// O galho de branch (o `arrow.triangle.branch` do Swift): um tronco e um
/// ramo que sai dele.
class _BranchPainter extends CustomPainter {
  _BranchPainter(this.lit);

  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white(lit ? 0.9 : 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final c = size.center(Offset.zero);
    final base = c + const Offset(-3, 6);
    final top = c + const Offset(-3, -6);
    final tip = c + const Offset(4, -4);
    canvas
      ..drawLine(base, top, paint)
      ..drawPath(
        Path()
          ..moveTo(base.dx, c.dy + 2)
          ..quadraticBezierTo(tip.dx, c.dy + 2, tip.dx, tip.dy),
        paint,
      )
      ..drawCircle(tip, 1.6, paint)
      ..drawCircle(top, 1.6, paint);
  }

  @override
  bool shouldRepaint(_BranchPainter old) => old.lit != lit;
}

class _CrossPainter extends CustomPainter {
  _CrossPainter(this.lit);

  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white(lit ? 0.9 : 0.6)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    canvas
      ..drawLine(c + const Offset(-5, -5), c + const Offset(5, 5), paint)
      ..drawLine(c + const Offset(5, -5), c + const Offset(-5, 5), paint);
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.lit != lit;
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
        child: CustomPaint(painter: _PortPainter(active)),
      ),
    );
  }
}

class _PortPainter extends CustomPainter {
  _PortPainter(this.active);

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = (Offset.zero & size).deflate(2);
    canvas.drawOval(
      circle,
      Paint()..color = active ? AppColors.attention : const Color(0xFF404040),
    );
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
        ..color = active ? const Color(0xFF000000) : AppColors.white(0.6),
    );
  }

  @override
  bool shouldRepaint(_PortPainter old) => old.active != active;
}
