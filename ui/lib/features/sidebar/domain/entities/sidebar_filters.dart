import 'sidebar_bench.dart';

/// O que uma bancada está pedindo, para o filtro "Mostrar".
enum BenchSituation {
  needsYou('Esperando você'),
  working('Em trabalho'),
  done('Terminou'),
  idle('Paradas');

  const BenchSituation(this.label);

  final String label;

  bool matches(SidebarBench b) => switch (this) {
    needsYou => b.activity.attention > 0,
    working => b.activity.isWorking,
    done => b.activity.done > 0,
    idle =>
      !b.activity.isWorking &&
          b.activity.attention == 0 &&
          b.activity.done == 0,
  };
}

/// Os filtros do painel: quais situações mostrar e de qual workspace. É estado
/// passageiro da tela; quem filtra a árvore é [SidebarTree.narrowed].
class SidebarFilters {
  const SidebarFilters({this.situations = const {}, this.workspaceId});

  static const none = SidebarFilters();

  final Set<BenchSituation> situations;
  final String? workspaceId;

  /// Quantos filtros estão ligados: o número do botão.
  int get count => situations.length + (workspaceId == null ? 0 : 1);
  bool get isEmpty => count == 0;

  bool matches(SidebarBench b) =>
      situations.isEmpty || situations.any((s) => s.matches(b));

  SidebarFilters toggled(BenchSituation s) => SidebarFilters(
    situations: situations.contains(s)
        ? ({...situations}..remove(s))
        : {...situations, s},
    workspaceId: workspaceId,
  );

  SidebarFilters inWorkspace(String? id) =>
      SidebarFilters(situations: situations, workspaceId: id);
}
