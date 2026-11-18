import 'package:flutter/widgets.dart';

import '../../../../core/domain/entities/view_mode.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/workbench_palette.dart';

/// A barra de cima: o nome da bancada na tela à esquerda e, no meio, a pílula
/// que alterna canvas e chat.
class ViewToolbar extends StatelessWidget {
  const ViewToolbar({
    required this.bench,
    required this.onSelect,
    required this.onPickColor,
    this.titleInset = 16,
    this.trailing,
    super.key,
  });

  final Workbench? bench;
  final ValueChanged<ViewMode> onSelect;
  final VoidCallback onPickColor;

  /// Onde o título começa; o legado deixava 82 para os botões da janela.
  final double titleInset;

  /// O que fica no canto direito (a pastilha de consumo).
  final Widget? trailing;

  static const height = 46.0;

  @override
  Widget build(BuildContext context) {
    final bench = this.bench;
    final mode = bench?.view ?? ViewMode.canvas;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        border: Border(bottom: BorderSide(color: AppColors.white(0.09))),
      ),
      child: Stack(
        children: [
          Center(
            child: _Pill(selected: mode, onSelect: onSelect),
          ),
          if (bench != null)
            Positioned(
              left: titleInset,
              top: 0,
              bottom: 0,
              right: 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.34,
                  child: _Title(bench: bench, onPickColor: onPickColor),
                ),
              ),
            ),
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mode == ViewMode.chat)
                    Text(
                      'os terminais continuam rodando',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.white(0.35),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  if (mode == ViewMode.chat && trailing != null)
                    const SizedBox(width: 12),
                  ?trailing,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.bench, required this.onPickColor});

  final Workbench bench;
  final VoidCallback onPickColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (bench.color != null) ...[
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPickColor,
            child: Container(
              key: const ValueKey('bench-swatch'),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: WorkbenchPalette.of(bench.color),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white(0.18), width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(
          bench.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.white(0.95),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.selected, required this.onSelect});

  final ViewMode selected;
  final ValueChanged<ViewMode> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AppColors.white(0.06),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in ViewMode.values) ...[
          _ModeButton(
            mode: mode,
            selected: mode == selected,
            onTap: () => onSelect(mode),
          ),
          if (mode != ViewMode.values.last) const SizedBox(width: 3),
        ],
      ],
    ),
  );
}

class _ModeButton extends StatefulWidget {
  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ViewMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final alpha = _hovering ? 0.95 : 0.6;
    final ink = widget.selected
        ? const Color(0xFFFFFFFF)
        : AppColors.white(alpha);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accent.withValues(alpha: 0.9)
                : (_hovering ? AppColors.white(0.08) : null),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            widget.mode.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ink,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
