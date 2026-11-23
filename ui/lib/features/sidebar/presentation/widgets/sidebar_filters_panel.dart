import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_filters.dart';
import '../../domain/entities/sidebar_tab.dart';
import '../../domain/entities/sidebar_tree.dart';

/// Largura do popover de filtros (o `.sb-mo` do v3).
const filtersPanelWidth = 264.0;

/// O conteúdo do popover de filtros, uma lista de menu: **Mostrar** (situações,
/// cada uma com a contagem), **Agrupar por** e **Workspace**. "Recolher paradas
/// há mais de" espera a idade da última atividade, que o core ainda não manda.
class SidebarFiltersPanel extends StatelessWidget {
  const SidebarFiltersPanel({
    required this.filters,
    required this.onFilters,
    required this.tab,
    required this.onTab,
    required this.tree,
    super.key,
  });

  final SidebarFilters filters;
  final ValueChanged<SidebarFilters> onFilters;
  final SidebarTab tab;
  final ValueChanged<SidebarTab> onTab;

  /// A árvore inteira, sem filtro: as contagens e a lista de workspaces vêm dela.
  final SidebarTree tree;

  int _count(BenchSituation s) {
    final benches = [
      for (final w in tree.workspaces)
        for (final p in w.projects) ...p.benches,
      ...tree.orphans,
    ];
    return benches.where(s.matches).length;
  }

  Color? _dot(EgeonColors c, BenchSituation s) => switch (s) {
    BenchSituation.needsYou => c.attention,
    BenchSituation.working => c.running,
    BenchSituation.done => c.success,
    BenchSituation.idle => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Title('Mostrar'),
        for (final s in BenchSituation.values)
          _Option(
            label: s.label,
            check: filters.situations.contains(s),
            dot: _dot(c, s),
            count: _count(s),
            onPressed: () => onFilters(filters.toggled(s)),
          ),
        const _Rule(),
        const _Title('Agrupar por'),
        _Option(
          label: 'Workspace › projeto',
          radio: tab == SidebarTab.all,
          onPressed: () => onTab(SidebarTab.all),
        ),
        _Option(
          label: 'Última atividade',
          radio: tab == SidebarTab.active,
          onPressed: () => onTab(SidebarTab.active),
        ),
        const _Rule(),
        const _Title('Workspace'),
        _Option(
          label: 'Todos os workspaces',
          mark: const _Initial('∗'),
          picked: filters.workspaceId == null,
          onPressed: () => onFilters(filters.inWorkspace(null)),
        ),
        for (final w in tree.workspaces)
          _Option(
            label: w.name,
            mark: _Initial(
              w.name.trim().isEmpty ? '' : w.name.trim()[0].toUpperCase(),
            ),
            picked: filters.workspaceId == w.id,
            onPressed: () => onFilters(filters.inWorkspace(w.id)),
          ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
    child: Text(
      text,
      style: EgeonType.caption.copyWith(
        color: context.eg.textMuted,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: SizedBox(height: 1, child: ColoredBox(color: context.eg.lineSubtle)),
  );
}

/// A inicial do workspace: quadrado de 18, raio 5.
class _Initial extends StatelessWidget {
  const _Initial(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return SizedBox(
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.steelActive,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Center(
          child: Text(
            letter,
            style: EgeonType.caption.copyWith(
              color: c.textSecondary,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma linha do painel (32, padding 0 10, vão 10, raio 6, hover steel): caixa
/// de marcar, botão de opção ou a inicial de um workspace (com o ✓ à direita
/// no escolhido), o rótulo, o ponto do estado e a contagem na ponta.
class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.onPressed,
    this.check,
    this.radio,
    this.mark,
    this.picked = false,
    this.dot,
    this.count,
  });

  final String label;
  final VoidCallback onPressed;
  final bool? check;
  final bool? radio;
  final Widget? mark;
  final bool picked;
  final Color? dot;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final on = check ?? radio ?? picked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Semantics(
        checked: on,
        label: label,
        child: Pressable(
          onPressed: onPressed,
          builder: (context, s) => DecoratedBox(
            decoration: BoxDecoration(
              color: s.hovered ? c.steel : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    if (check != null)
                      _Box(on: on, circle: false)
                    else if (radio != null)
                      _Box(on: on, circle: true)
                    else
                      ?mark,
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.label.copyWith(
                          color: c.textPrimary,
                          fontSize: 13,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (dot != null) ...[
                      const SizedBox(width: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 6, height: 6),
                      ),
                    ],
                    const Spacer(),
                    if (count != null)
                      Text(
                        '$count',
                        style: EgeonType.monoMeta.copyWith(
                          color: c.textMuted,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    if (mark != null && picked)
                      EgIcon(EgIcons.check, size: 14, color: c.accent),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A caixa de marcar (14, raio 4) ou o botão de opção (14): ligada em `accent`.
class _Box extends StatelessWidget {
  const _Box({required this.on, required this.circle});

  final bool on;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final Border border;
    if (circle) {
      border = on
          ? Border.all(color: c.accent, width: 4)
          : Border.all(color: c.controlBorder, width: 1.5);
    } else {
      border = Border.all(color: on ? c.accent : c.controlBorder, width: 1.5);
    }
    return SizedBox(
      width: 14,
      height: 14,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: !circle && on ? c.accent : null,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(4),
          border: border,
        ),
        child: !circle && on
            ? Center(
                child: EgIcon(
                  EgIcons.check,
                  size: 10,
                  strokeWidth: 2,
                  color: c.onAccent,
                ),
              )
            : null,
      ),
    );
  }
}

/// A linha do filtro ativo, abaixo do cabeçalho: quantos estão ligados e o
/// "Limpar", visível com o painel fechado.
class SidebarFilterSummary extends StatelessWidget {
  const SidebarFilterSummary({
    required this.count,
    required this.onClear,
    super.key,
  });

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Padding(
      // 10 do painel e 10 da linha (a v3).
      padding: const EdgeInsets.fromLTRB(20, 0, 20, EgeonSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 filtro ligado' : '$count filtros ligados',
              style: EgeonType.caption.copyWith(
                color: c.textSecondary,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Pressable(
            onPressed: onClear,
            semanticLabel: 'Limpar filtros',
            builder: (context, s) => Text(
              'Limpar',
              style: EgeonType.caption.copyWith(
                color: s.hovered ? c.accentHover : c.accent,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
