import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_actions.dart';
import 'bench_row.dart';

/// A aba Ativas: as bancadas de pé, da que rodou por último para a que rodou há
/// mais tempo, separadas pela janela de 24 horas.
class SidebarActiveView extends StatelessWidget {
  const SidebarActiveView({
    required this.tree,
    required this.benches,
    this.compact = false,
    super.key,
  });

  final SidebarTree tree;
  final BenchActions benches;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      compact ? 2 : 8,
      compact ? 0 : 4,
      compact ? 2 : 8,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Últimas 24 horas', tree.recent),
        _section('Paradas há mais de 24 horas', tree.stale),
      ],
    ),
  );

  Widget _section(String title, List<SidebarBench> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          const SizedBox(height: 10)
        else
          _SectionLabel(title, list.length),
        for (final bench in list)
          Padding(
            key: ValueKey('active-${bench.id}'),
            padding: EdgeInsets.only(bottom: compact ? 2 : 6),
            child: SidebarBenchRow(
              bench: bench,
              actions: benches,
              compact: compact,
            ),
          ),
        if (!compact) const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.white(0.42),
              ),
            ),
            TextSpan(
              text: '  $count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.white(0.3),
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(decoration: TextDecoration.none),
      ),
    ),
  );
}
