import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/edit_links.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/place_node.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/remove_node.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/save_frames.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/set_ui_focus.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/watch_canvas.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_memory.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_tool_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/canvas_cubit_for.dart';
import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump.dart';

/// Trocar de aba, ou ir ao chat e voltar, desmonta o canvas da bancada: a
/// vista e a ferramenta armada voltam como estavam (auditoria, item 63).
void main() {
  late InMemoryCanvasRepository repository;
  late CanvasMemory memory;

  Future<CanvasCubit> mount(String bench) async {
    final cubit = CanvasCubit(
      workbenchId: bench,
      watch: WatchCanvas(repository),
      saveFrames: SaveFrames(repository),
      links: EditLinks(repository),
      removeNode: RemoveNode(repository),
      setFocus: SetUiFocus(repository),
      memory: memory,
    );
    await pump();
    cubit.resize(const Size(1000, 700));
    return cubit;
  }

  setUp(() {
    repository = InMemoryCanvasRepository(cards: seedCards);
    memory = CanvasMemory();
  });

  test('a primeira vez enquadra; ao voltar, a vista é a que ficou', () async {
    final first = await mount('b1');
    final fitted = first.state.viewport;
    first.stepZoom(1);
    first.stepZoom(1);
    final left = first.state.viewport;
    expect(left.zoom, isNot(fitted.zoom));
    await first.close();

    final back = await mount('b1');
    await pump();
    expect(back.state.viewport.zoom, left.zoom, reason: 'não reenquadra');
    expect(back.state.viewport.origin, left.origin);
    await back.close();

    final other = await mount('b2');
    expect(
      other.state.viewport.zoom,
      fitted.zoom,
      reason: 'outra bancada abre enquadrada',
    );
    await other.close();
  });

  test('a ferramenta armada continua armada; o aviso, não', () async {
    CanvasToolCubit tools() => CanvasToolCubit(
      workbenchId: 'b1',
      placeNode: PlaceNode(repository),
      memory: memory,
    );
    final first = tools()..selectTool(CanvasTool.web);
    await first.close();
    final back = tools();
    expect(back.tool, CanvasTool.web);

    back.pickComponent('revisor');
    expect(back.state, isA<CanvasAnnouncing>());
    await back.close();
    final again = tools();
    expect(
      again.state,
      isA<CanvasComponentArmed>().having((s) => s.component, 'c', 'revisor'),
    );
    await again.close();
  });
}
