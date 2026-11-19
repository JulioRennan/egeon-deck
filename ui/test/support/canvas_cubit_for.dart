import 'package:egeon_deck/core/domain/entities/workbench_node.dart';

import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';

import 'in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/canvas/domain/usecase/edit_links.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/place_node.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/remove_node.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/save_frames.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/set_ui_focus.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/watch_canvas.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_tool_cubit.dart';

import 'pump.dart';

/// Canvas com dois terminais lado a lado e um web, numa janela 1000×700.
const seedCards = [
  CanvasCard(
    id: 'a',
    kind: NodeKind.shell,
    frame: Rect.fromLTWH(100, 100, 720, 460),
  ),
  CanvasCard(
    id: 'b',
    kind: NodeKind.agent,
    frame: Rect.fromLTWH(900, 100, 720, 460),
  ),
  CanvasCard(
    id: 'w',
    kind: NodeKind.web,
    frame: Rect.fromLTWH(100, 700, 720, 460),
  ),
];

Future<({CanvasCubit cubit, InMemoryCanvasRepository repository})>
canvasCubitFor({
  List<CanvasCard> cards = seedCards,
  List<EdgeLink> links = const [],
  Size size = const Size(1000, 700),
}) async {
  final repository = InMemoryCanvasRepository(cards: cards, links: links);
  final cubit = CanvasCubit(
    workbenchId: 'bancada',
    watch: WatchCanvas(repository),
    saveFrames: SaveFrames(repository),
    links: EditLinks(repository),
    removeNode: RemoveNode(repository),
    setFocus: SetUiFocus(repository),
  );
  await pump();
  cubit.resize(size);
  return (cubit: cubit, repository: repository);
}

/// A ferramenta do canvas da mesma bancada, criando no mesmo repositório.
CanvasToolCubit toolCubitFor(InMemoryCanvasRepository repository) =>
    CanvasToolCubit(workbenchId: 'bancada', placeNode: PlaceNode(repository));
