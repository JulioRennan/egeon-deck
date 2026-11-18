import 'dart:async';

import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/features/tabs/domain/repository/tabs_repository.dart';

/// As abas falsas: o teste empurra listas e lê os gestos que a UI mandou.
class FakeTabsRepository implements TabsRepository {
  final _tabs = StreamController<List<WorkbenchTab>>.broadcast();
  final picked = <String>[];
  final closed = <String>[];
  final reordered = <List<String>>[];
  var watchers = 0;

  void push(List<WorkbenchTab> tabs) => _tabs.add(tabs);

  @override
  Stream<List<WorkbenchTab>> watch() {
    late StreamController<List<WorkbenchTab>> controller;
    StreamSubscription<List<WorkbenchTab>>? inner;
    controller = StreamController<List<WorkbenchTab>>(
      onListen: () {
        watchers++;
        inner = _tabs.stream.listen(controller.add);
      },
      onCancel: () {
        watchers--;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> pick(String id) async => picked.add(id);

  @override
  Future<void> close(String id) async => closed.add(id);

  @override
  Future<void> reorder(List<String> ids) async => reordered.add(ids);
}
