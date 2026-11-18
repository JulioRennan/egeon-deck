import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../core/domain/entities/organization.dart';

/// Uma aba: bancada aberta, na ordem em que foi aberta. Chega montada pelo
/// core Rust; a UI só desenha.
class WorkbenchTab {
  const WorkbenchTab({
    required this.id,
    required this.name,
    this.isActive = false,
    this.color,
    this.summary = ActivitySummary.none,
  });

  final String id;
  final String name;
  final bool isActive;

  /// Nome da cor da bancada (`blue`, `sand`…); quem resolve é o tema.
  final String? color;
  final ActivitySummary summary;

  /// As abas da organização: as bancadas com posição, na ordem delas.
  static List<WorkbenchTab> listOf(Organization org) => [
    for (final b in org.openTabs)
      WorkbenchTab(
        id: b.id,
        name: b.name,
        isActive: b.tabActive,
        color: b.color,
        summary: b.activity,
      ),
  ];

  @override
  bool operator ==(Object other) =>
      other is WorkbenchTab &&
      other.id == id &&
      other.name == name &&
      other.isActive == isActive &&
      other.color == color &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(id, name, isActive, color, summary);
}
