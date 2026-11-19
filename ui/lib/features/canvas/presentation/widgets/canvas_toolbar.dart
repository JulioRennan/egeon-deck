import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/hand_cursor.dart';

import '../../../../commons/widgets/app_tooltip.dart';
import '../../../../commons/widgets/context_menu.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/entities/canvas_tool.dart';
import 'canvas_bench_actions.dart';
import 'tool_glyphs.dart';

/// Barra flutuante no topo do canvas: ferramentas à esquerda, zoom no meio e
/// o "onde é que eu estou" à direita.
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({
    required this.tool,
    required this.zoom,
    required this.onSelect,
    required this.onZoom,
    required this.onResetZoom,
    required this.onFitAll,
    this.componentNames,
    this.onPickComponent,
    this.onConfigureTerminal,
    this.benchActions,
    super.key,
  });

  final CanvasTool tool;
  final double zoom;
  final ValueChanged<CanvasTool> onSelect;

  /// `+1` aproxima, `-1` afasta.
  final ValueChanged<int> onZoom;
  final VoidCallback onResetZoom;
  final VoidCallback onFitAll;

  /// Componentes salvos, para o menu da ferramenta de terminal.
  /// Os componentes salvos, pedidos na hora: salvar um no formulário e
  /// segurar o botão de novo já o mostra.
  final Future<List<String>> Function()? componentNames;

  /// Escolher com que componente o próximo terminal nasce. Nulo = shell padrão.
  final ValueChanged<String?>? onPickComponent;
  final VoidCallback? onConfigureTerminal;

  /// Template e worktree da bancada; nulo, a barra não os mostra.
  final CanvasBenchActions? benchActions;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE61E1E20),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.white(0.12)),
      boxShadow: [BoxShadow(color: AppColors.black(0.35), blurRadius: 14)],
    ),
    child: SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in CanvasTool.values) ...[
              _ToolButton(
                key: ValueKey('tool-${t.name}'),
                glyph: switch (t) {
                  CanvasTool.cursor => ToolGlyphKind.cursor,
                  CanvasTool.terminal => ToolGlyphKind.terminal,
                  CanvasTool.web => ToolGlyphKind.web,
                  CanvasTool.queue => ToolGlyphKind.queue,
                },
                tooltip: t.tooltip,
                selected: tool == t,
                onTap: () => onSelect(t),
                // Clique curto continua criando shell na hora. O menu só
                // aparece ao segurar, para escolher componente não custar o
                // caso simples.
                onLongPress: t == CanvasTool.terminal
                    ? (position) => unawaited(_componentMenu(context, position))
                    : null,
              ),
              const SizedBox(width: 2),
            ],
            const _Separator(),
            _ToolButton(
              key: const ValueKey('zoom-out'),
              glyph: ToolGlyphKind.minus,
              tooltip: 'Afastar (⌘−)',
              size: 28,
              onTap: () => onZoom(-1),
            ),
            _ZoomLabel(zoom: zoom, onTap: onResetZoom),
            _ToolButton(
              key: const ValueKey('zoom-in'),
              glyph: ToolGlyphKind.plus,
              tooltip: 'Aproximar (⌘+)',
              size: 28,
              onTap: () => onZoom(1),
            ),
            ..._benchButtons(),
            const _Separator(),
            _ToolButton(
              key: const ValueKey('fit-all'),
              glyph: ToolGlyphKind.fit,
              tooltip: 'Enquadrar todos os nós',
              onTap: onFitAll,
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _benchButtons() {
    final actions = benchActions;
    if (actions == null) return const [];
    final update = actions.onUpdateTemplate;
    return [
      const _Separator(),
      _ToolButton(
        key: const ValueKey('save-template'),
        glyph: ToolGlyphKind.saveTemplate,
        tooltip: 'Salvar este canvas como um template novo',
        onTap: actions.onSaveTemplate,
      ),
      if (actions.originTemplate != null && update != null)
        _ToolButton(
          key: const ValueKey('update-template'),
          glyph: ToolGlyphKind.updateTemplate,
          // Com a origem conhecida, a dica diz qual template (`showsUpdateTemplate`).
          tooltip:
              'Atualizar o template "${actions.originTemplate}" com este canvas',
          onTap: update,
        ),
      _ToolButton(
        key: const ValueKey('new-worktree'),
        glyph: ToolGlyphKind.branch,
        tooltip: 'Nova bancada numa worktree desta — nada aqui é reiniciado',
        onTap: actions.onNewWorktree,
      ),
    ];
  }

  Future<void> _componentMenu(BuildContext context, Offset position) async {
    final componentNames = await this.componentNames?.call() ?? const [];
    if (!context.mounted) return;
    showContextMenu(
      context,
      position: position,
      entries: [
        MenuEntry('Shell simples', () => onPickComponent?.call(null)),
        if (componentNames.isNotEmpty) const MenuEntry.separator(),
        for (final name in componentNames)
          MenuEntry(name, () => onPickComponent?.call(name)),
        const MenuEntry.separator(),
        MenuEntry(
          'Configurar novo terminal…',
          () => onConfigureTerminal?.call(),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: CanvasToolbar.height - 24,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: AppColors.white(0.18),
  );
}

/// Só o número é clicável fora dos botões: clicar nele volta para 100%.
class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.zoom, required this.onTap});

  final double zoom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppTooltip(
    message: 'Clique para voltar a 100% (⌘0)',
    child: HandCursor(
      child: GestureDetector(
        key: const ValueKey('zoom-label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Center(
            child: Text(
              '${(zoom * 100).round()}%',
              style: AppTheme.textStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.white(0.72),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ToolButton extends StatefulWidget {
  const _ToolButton({
    required this.glyph,
    required this.onTap,
    this.selected = false,
    this.size = 32,
    this.onLongPress,
    this.tooltip,
    super.key,
  });

  final ToolGlyphKind glyph;

  /// A dica, como o `toolTip` do botão no Swift.
  final String? tooltip;
  final bool selected;
  final double size;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPress;

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.selected;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPress == null
            ? null
            : (details) => widget.onLongPress!(details.globalPosition),
        // O botão direito abre o mesmo menu do segurar, como no Swift.
        onSecondaryTapDown: widget.onLongPress == null
            ? null
            : (details) => widget.onLongPress!(details.globalPosition),
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lit
                ? AppColors.white(0.18)
                : _hovering
                ? AppColors.white(0.09)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ToolGlyph(
            widget.glyph,
            color: lit ? const Color(0xFFFFFFFF) : AppColors.white(0.75),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null
        ? button
        : AppTooltip(message: tooltip, child: button);
  }
}
