import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_actions.dart';
import 'sidebar_commands.dart';
import 'sidebar_item.dart';
import 'sidebar_menus.dart';

/// A visão Ativas: as bancadas de pé, da que rodou por último para a que rodou
/// há mais tempo, separadas pela janela de 24 horas. Cada linha diz de onde a
/// bancada vem (workspace › projeto).
class SidebarActiveView extends StatelessWidget {
  const SidebarActiveView({
    required this.tree,
    required this.benches,
    required this.commands,
    super.key,
  });

  final SidebarTree tree;
  final BenchActions benches;
  final SidebarCommands commands;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _section(context, 'Últimas 24 horas', tree.recent),
      _section(context, 'Paradas há mais de 24 horas', tree.stale),
    ],
  );

  Widget _section(BuildContext context, String title, List<SidebarBench> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    final c = context.eg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // O rótulo do grupo: 12 w500 em `textMuted`, a contagem em mono logo
        // depois do texto.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 2),
          child: Text.rich(
            TextSpan(
              text: '$title ',
              children: [
                TextSpan(
                  text: '${list.length}',
                  style: EgeonType.monoMeta.copyWith(
                    color: c.textMuted,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EgeonType.caption.copyWith(
              color: c.textMuted,
              letterSpacing: 0.12,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        // As bancadas no mesmo fio da árvore: 8 à esquerda, 10 de recuo, vão 4.
        Container(
          margin: const EdgeInsets.fromLTRB(8, 2, 0, 10),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.lineSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, bench) in list.indexed) ...[
                if (i > 0) const SizedBox(height: EgeonSpace.s1),
                KeyedSubtree(
                  key: ValueKey('active-${bench.id}'),
                  child: SidebarItem.bench(
                    bench: bench,
                    showOrigin: true,
                    onPressed: () => benches.onSelect(bench.id),
                    onMenu: (anchor) => showMenu(
                      context,
                      anchor: anchor,
                      placement: PopoverPlacement.bottomEnd,
                      width: 232,
                      items: benchMenu(
                        context,
                        bench: bench,
                        actions: benches,
                        commands: commands,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
