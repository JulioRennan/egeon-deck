import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/hand_cursor.dart';

import '../../../../commons/widgets/context_menu.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/entities/canvas_tool.dart';
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
    this.componentNames = const [],
    this.onPickComponent,
    this.onConfigureTerminal,
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
  final List<String> componentNames;

  /// Escolher com que componente o próximo terminal nasce. Nulo = shell padrão.
  final ValueChanged<String?>? onPickComponent;
  final VoidCallback? onConfigureTerminal;

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
                selected: tool == t,
                onTap: () => onSelect(t),
                // Clique curto continua criando shell na hora. O menu só
                // aparece ao segurar, para escolher componente não custar o
                // caso simples.
                onLongPress: t == CanvasTool.terminal
                    ? (position) => _componentMenu(context, position)
                    : null,
              ),
              const SizedBox(width: 2),
            ],
            const _Separator(),
            _ToolButton(
              key: const ValueKey('zoom-out'),
              glyph: ToolGlyphKind.minus,
              size: 28,
              onTap: () => onZoom(-1),
            ),
            _ZoomLabel(zoom: zoom, onTap: onResetZoom),
            _ToolButton(
              key: const ValueKey('zoom-in'),
              glyph: ToolGlyphKind.plus,
              size: 28,
              onTap: () => onZoom(1),
            ),
            const _Separator(),
            _ToolButton(
              key: const ValueKey('fit-all'),
              glyph: ToolGlyphKind.fit,
              onTap: onFitAll,
            ),
          ],
        ),
      ),
    ),
  );

  void _componentMenu(BuildContext context, Offset position) {
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
  Widget build(BuildContext context) => HandCursor(
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
  );
}

class _ToolButton extends StatefulWidget {
  const _ToolButton({
    required this.glyph,
    required this.onTap,
    this.selected = false,
    this.size = 32,
    this.onLongPress,
    super.key,
  });

  final ToolGlyphKind glyph;
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPressStart: widget.onLongPress == null
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
  }
}
