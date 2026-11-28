import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../core/domain/entities/workbench_clock.dart';

/// De qual workspace uma linha da aba Ativas vem: a pastilha com a inicial.
class BenchOwner {
  const BenchOwner({required this.id, required this.name, this.icon});

  final String id;
  final String name;
  final String? icon;

  String get initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.substring(0, 1).toUpperCase();
  }
}

/// Uma linha de bancada na barra lateral, como o core a monta.
class SidebarBench {
  const SidebarBench({
    required this.id,
    required this.name,
    required this.path,
    this.pathExists = true,
    this.color,
    this.selected = false,
    this.live = false,
    this.removing = false,
    this.activity = ActivitySummary.none,
    this.clock,
    this.owner,
    this.project,
  });

  final String id;
  final String name;

  /// O caminho como o usuário o vê (com `~`).
  final String path;
  final bool pathExists;
  final String? color;

  /// A bancada na tela.
  final bool selected;

  /// De pé: tem terminais rodando.
  final bool live;

  /// Saindo: a limpeza está em curso.
  final bool removing;
  final ActivitySummary activity;

  /// O cronômetro da bancada; ausente até ela ter rodado.
  final WorkbenchClock? clock;

  /// Só nas linhas da aba Ativas, que mostram de onde a bancada vem.
  final BenchOwner? owner;
  final String? project;

  String get initial => name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
}
