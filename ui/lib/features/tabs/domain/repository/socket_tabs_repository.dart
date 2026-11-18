import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/organization.dart';
import '../entities/workbench_tab.dart';
import 'tabs_repository.dart';

/// As abas falando com o core Rust: saem do tópico `workspaces`, das bancadas
/// que têm posição de aba.
class SocketTabsRepository implements TabsRepository {
  const SocketTabsRepository(this._feed);

  final OrganizationFeed _feed;

  @override
  Stream<List<WorkbenchTab>> watch() => _feed.watch().map(WorkbenchTab.listOf);

  @override
  Future<void> pick(String id) =>
      _feed.command('activate_workbench', {'workbench': id});

  @override
  Future<void> close(String id) =>
      _feed.command('close_workbench', {'workbench': id});

  /// O arrasto entrega a ordem final; o core quer um movimento só. Acha qual
  /// aba mudou de lugar comparando com a ordem de agora.
  @override
  Future<void> reorder(List<String> ids) async {
    final now = <String>[
      for (final b in _feed.last?.openTabs ?? <OrgBench>[]) b.id,
    ];
    if (now.length != ids.length) return;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] == now[i]) continue;
      final moved = [...now]..remove(ids[i]);
      final candidate = [...moved]..insert(i, ids[i]);
      if (_same(candidate, ids)) {
        await _feed.command('move_tab', {'workbench': ids[i], 'to': i});
        return;
      }
    }
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
