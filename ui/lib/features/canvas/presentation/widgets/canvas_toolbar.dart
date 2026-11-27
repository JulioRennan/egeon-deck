import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/layer.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/tool_button.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../commons/widgets/shell_layers.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/canvas_component.dart';
import '../../domain/entities/canvas_tool.dart';
import 'canvas_bench_actions.dart';
import 'canvas_menus.dart';
import '../../../../commons/utils/app_shortcut.dart';

/// A barra de ações do canvas, em vidro, no topo e ao centro: ferramentas,
/// zoom, a bancada (template e worktree) e enquadrar. É o único desfoque do
/// canvas; a superfície por baixo não leva nenhum.
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({
    required this.tool,
    required this.zoom,
    required this.onSelect,
    required this.onZoom,
    required this.onResetZoom,
    required this.onFitAll,
    this.components,
    this.onPickComponent,
    this.onConfigureTerminal,
    this.benchActions,
    this.benchName = '',
    this.benchColor,
    this.onPickColor,
    super.key,
  });

  final CanvasTool tool;
  final double zoom;
  final ValueChanged<CanvasTool> onSelect;

  /// `+1` aproxima, `-1` afasta.
  final ValueChanged<int> onZoom;
  final VoidCallback onResetZoom;
  final VoidCallback onFitAll;

  /// Os componentes salvos, pedidos na hora: salvar um no formulário e segurar
  /// o botão de novo já o mostra.
  final Future<List<CanvasComponent>> Function()? components;

  /// Escolher com que componente o próximo terminal nasce. Nulo = shell padrão.
  final ValueChanged<String?>? onPickComponent;
  final VoidCallback? onConfigureTerminal;

  /// Template e worktree da bancada; nulo, a barra não os mostra.
  final CanvasBenchActions? benchActions;

  /// A cor da bancada (nome gravado) e quem a troca; sem [onPickColor] o botão
  /// de cor não aparece.
  final String benchName;
  final String? benchColor;
  final ValueChanged<String>? onPickColor;

  /// 36 do botão, 4 de respiro e a borda de 1px do vidro de cada lado.
  static const height = 46.0;

  static EgIconData _icon(CanvasTool t) => switch (t) {
    CanvasTool.cursor => EgIcons.pointer,
    CanvasTool.shell => EgIcons.terminal,
    CanvasTool.agent => EgIcons.agent,
    CanvasTool.web => EgIcons.globe,
    CanvasTool.queue => EgIcons.queue,
  };

  static String _name(CanvasTool t) => switch (t) {
    CanvasTool.cursor => 'Cursor',
    CanvasTool.shell => 'Shell',
    CanvasTool.agent => 'Terminal de agente',
    CanvasTool.web => 'Web',
    CanvasTool.queue => 'Fila de prompts',
  };

  @override
  Widget build(BuildContext context) {
    final actions = benchActions;
    final update = actions?.onUpdateTemplate;
    return GlassSurface(
      radius: EgeonRadius.xl,
      padding: const EdgeInsets.all(EgeonSpace.s1 + 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in CanvasTool.values) ...[
            if (t != CanvasTool.cursor) const SizedBox(width: 2),
            t == CanvasTool.agent
                ? _AgentButton(
                    selected: tool == t,
                    onPressed: () => onSelect(t),
                    components: components,
                    onPickComponent: onPickComponent,
                    onConfigureTerminal: onConfigureTerminal,
                  )
                : ToolButton(
                    key: ValueKey('tool-${t.name}'),
                    icon: _icon(t),
                    tooltip: _name(t),
                    selected: tool == t,
                    onPressed: () => onSelect(t),
                  ),
          ],
          const _Separator(),
          ToolButton(
            key: const ValueKey('zoom-out'),
            icon: EgIcons.minus,
            tooltip: 'Afastar',
            shortcut: appShortcutLabel('−', macOnly: true),
            onPressed: () => onZoom(-1),
          ),
          _ZoomLabel(zoom: zoom, onPressed: onResetZoom),
          ToolButton(
            key: const ValueKey('zoom-in'),
            icon: EgIcons.plus,
            tooltip: 'Aproximar',
            shortcut: appShortcutLabel('=', macOnly: true),
            onPressed: () => onZoom(1),
          ),
          if (actions != null || onPickColor != null) ...[
            const _Separator(),
            if (actions != null)
              _MenuButton(
                key: const ValueKey('template-menu'),
                tooltip: 'Template da bancada',
                icon: EgIcons.template,
                chevron: true,
                onPressed: (anchor, onClosed) => showTemplateMenu(
                  context,
                  anchor: anchor,
                  onClosed: onClosed,
                  onSave: actions.onSaveTemplate,
                  origin: actions.originTemplate,
                  onUpdate: update,
                ),
              ),
            if (onPickColor != null)
              _MenuButton(
                key: const ValueKey('bench-color'),
                tooltip: 'Cor da bancada',
                leading: BenchColorChip(BenchIdentity.of(benchColor)),
                onPressed: (anchor, onClosed) => showBenchColorMenu(
                  context,
                  anchor: anchor,
                  onClosed: onClosed,
                  benchName: benchName,
                  current: BenchIdentity.of(benchColor),
                  onPick: (identity) =>
                      onPickColor!(BenchIdentity.nameOf(identity)),
                ),
              ),
            if (actions != null)
              ToolButton(
                key: const ValueKey('new-worktree'),
                icon: EgIcons.worktree,
                tooltip: 'Nova bancada numa worktree desta',
                onPressed: actions.onNewWorktree,
              ),
          ],
          const _Separator(),
          ToolButton(
            key: const ValueKey('fit-all'),
            icon: EgIcons.fit,
            tooltip: 'Enquadrar todos os nós',
            onPressed: onFitAll,
          ),
        ],
      ),
    );
  }
}

/// O fio vertical entre os grupos: 1 de largura, 18 de altura, a 8% de branco.
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(
      width: 1,
      height: 18,
      child: ColoredBox(color: EgeonColors.overlay8),
    ),
  );
}

/// O número do zoom, em mono 12: clicar volta a 100%.
class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.zoom, required this.onPressed});

  final double zoom;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: 'Voltar para 100%',
      shortcut: appShortcutLabel('0', macOnly: true),
      child: Pressable(
        key: const ValueKey('zoom-label'),
        onPressed: onPressed,
        semanticLabel: 'Voltar para 100%',
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: s.pressed
                ? c.steelActive
                : s.hovered
                ? c.steel
                : null,
            borderRadius: BorderRadius.circular(EgeonRadius.md),
          ),
          child: SizedBox(
            height: 36,
            width: 52,
            child: Center(
              child: Text(
                '${(zoom * 100).round()}%',
                style: EgeonType.monoMeta.copyWith(
                  fontWeight: FontWeight.w500,
                  color: s.hovered ? c.textPrimary : c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ferramenta de terminal de agente: clique liga; segurar (380 ms) ou o
/// botão direito abre o menu de componentes. O canto ◢ avisa que há menu.
class _AgentButton extends StatefulWidget {
  const _AgentButton({
    required this.selected,
    required this.onPressed,
    this.components,
    this.onPickComponent,
    this.onConfigureTerminal,
  });

  final bool selected;
  final VoidCallback onPressed;
  final Future<List<CanvasComponent>> Function()? components;
  final ValueChanged<String?>? onPickComponent;
  final VoidCallback? onConfigureTerminal;

  @override
  State<_AgentButton> createState() => _AgentButtonState();
}

class _AgentButtonState extends State<_AgentButton> {
  final _key = GlobalKey();

  Future<void> _menu() async {
    final components = await widget.components?.call() ?? const [];
    if (!mounted) return;
    final box = _key.currentContext!.findRenderObject()! as RenderBox;
    showComponentsMenu(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      components: components,
      onPick: (name) => widget.onPickComponent?.call(name),
      onConfigure: widget.onConfigureTerminal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return RawGestureDetector(
      key: _key,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 380),
              ),
              (r) => r.onLongPressStart = (_) => unawaited(_menu()),
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) => r.onSecondaryTapDown = (_) => unawaited(_menu()),
            ),
      },
      child: Stack(
        children: [
          ToolButton(
            key: const ValueKey('tool-agent'),
            icon: EgIcons.agent,
            tooltip: 'Terminal de agente',
            selected: widget.selected,
            onPressed: widget.onPressed,
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(5, 5),
                painter: _Corner(widget.selected ? c.accent : c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão da barra que abre um menu: ícone (ou [leading]) e, se quiser, o
/// chevron ▾. Fica "ligado" enquanto o menu está aberto.
class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.leading,
    this.chevron = false,
    super.key,
  });

  final String tooltip;
  final EgIconData? icon;
  final Widget? leading;
  final bool chevron;
  final Layer Function(Rect anchor, VoidCallback onClosed) onPressed;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  final _box = GlobalKey();
  bool _open = false;

  void _show() {
    final box = _box.currentContext!.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    widget.onPressed(box.localToGlobal(Offset.zero) & box.size, () {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: widget.tooltip,
      child: Pressable(
        key: _box,
        onPressed: _show,
        semanticLabel: widget.tooltip,
        builder: (context, s) {
          final lit = _open;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: s.pressed
                  ? c.steelActive
                  : s.hovered
                  ? c.steel
                  : lit
                  ? c.accentSoft
                  : null,
              borderRadius: BorderRadius.circular(EgeonRadius.md),
            ),
            child: SizedBox(
              width: widget.chevron ? 46 : 36,
              height: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.leading ??
                      EgIcon(
                        widget.icon!,
                        color: lit
                            ? c.accent
                            : s.hovered
                            ? c.textPrimary
                            : c.textSecondary,
                      ),
                  if (widget.chevron) ...[
                    const SizedBox(width: 3),
                    EgIcon(
                      EgIcons.chevronDown,
                      size: 8,
                      color: lit ? c.accent : c.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Corner extends CustomPainter {
  _Corner(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_Corner old) => old.color != color;
}

/// A dica abaixo da barra enquanto uma ferramenta de criar está ligada: vidro
/// de raio 8, 32 de altura, padding 0 14. É o desfoque dela, só enquanto está à
/// vista.
class ToolHint extends StatelessWidget {
  const ToolHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return GlassSurface(
      radius: EgeonRadius.md,
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: EgeonType.small.copyWith(
                  color: c.textPrimary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Esc cancela',
                style: EgeonType.monoMeta.copyWith(
                  color: c.textMuted,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Onde a barra de ações fica no topo: ao centro, sem passar por baixo do
/// canto direito (o chip de consumo), cuja largura `ShellLayers` mede e publica
/// em [cornerInset]. Quando o centro não deixa passar, a barra anda para a
/// esquerda até encostar nele; sem nada no canto, fica no centro.
class ToolbarSlot extends StatelessWidget {
  const ToolbarSlot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: cornerInset,
    builder: (context, reserved, child) => CustomSingleChildLayout(
      delegate: _SlotDelegate(reserved),
      child: child,
    ),
    child: child,
  );
}

class _SlotDelegate extends SingleChildLayoutDelegate {
  const _SlotDelegate(this.reserved);

  /// O que o canto direito toma da largura: o chip, a margem dele e um respiro.
  final double reserved;

  static const _edge = EgeonSpace.s4;

  @override
  Size getSize(BoxConstraints constraints) =>
      Size(constraints.maxWidth, CanvasToolbar.height);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - _edge - reserved).clamp(
          0.0,
          double.infinity,
        ),
        maxHeight: CanvasToolbar.height,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final centered = (size.width - childSize.width) / 2;
    final beforeCorner = size.width - reserved - childSize.width;
    final x = centered < beforeCorner ? centered : beforeCorner;
    return Offset(x < _edge ? _edge : x, 0);
  }

  @override
  bool shouldRelayout(_SlotDelegate old) => old.reserved != reserved;
}
