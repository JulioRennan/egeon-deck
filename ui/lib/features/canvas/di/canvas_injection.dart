import '../../../core/adapters/injector.dart';
import '../domain/entities/canvas_probe.dart';
import '../domain/repository/canvas_repository.dart';
import '../domain/repository/socket_canvas_repository.dart';
import '../domain/usecase/edit_links.dart';
import '../domain/usecase/open_node_folder.dart';
import '../domain/usecase/place_node.dart';
import '../domain/usecase/remove_node.dart';
import '../domain/usecase/save_frames.dart';
import '../domain/usecase/set_ui_focus.dart';
import '../domain/usecase/watch_canvas.dart';
import '../presentation/cubit/canvas_commands.dart';
import '../presentation/cubit/canvas_cubit.dart';
import '../presentation/cubit/canvas_memory.dart';
import '../presentation/cubit/canvas_motion_cubit.dart';
import '../presentation/cubit/canvas_tool_cubit.dart';

/// Único: o [SocketCanvasRepository] guarda os frames que o core tem para só
/// mandar o que mudou — o `watch` de um cubit e o `saveFrames` precisam ver o
/// mesmo cache.
void registerCanvasRepositories() {
  Injector.lazySingleton<CanvasRepository>(
    () => SocketCanvasRepository(inject()),
  );
}

/// Únicos: os registros que a casca reparte com o canvas na tela — onde ele se
/// registra para `/geometry` e `/shot`, e as ferramentas e o zoom do menu.
void registerCanvasDomain() {
  Injector.lazySingleton(CanvasProbeRegistry.new);
  Injector.lazySingleton(CanvasCommands.new);
  // Única: a vista e a ferramenta de cada bancada sobrevivem à troca de aba.
  Injector.lazySingleton(CanvasMemory.new);

  Injector.factory(() => WatchCanvas(inject()));
  Injector.factory(() => SaveFrames(inject()));
  Injector.factory(() => PlaceNode(inject()));
  Injector.factory(() => EditLinks(inject()));
  Injector.factory(() => RemoveNode(inject()));
  Injector.factory(() => OpenNodeFolder(inject()));
  Injector.factory(() => SetUiFocus(inject()));
  Injector.factoryParam<CanvasCubit, String>(
    (workbenchId) => CanvasCubit(
      workbenchId: workbenchId,
      watch: inject(),
      saveFrames: inject(),
      links: inject(),
      removeNode: inject(),
      setFocus: inject(),
      memory: inject(),
    ),
  );
  Injector.factoryParam<CanvasToolCubit, String>(
    (workbenchId) => CanvasToolCubit(
      workbenchId: workbenchId,
      placeNode: inject(),
      memory: inject(),
    ),
  );
  // O movimento segue o canvas da mesma bancada: o stream é dele.
  Injector.factoryParam<CanvasMotionCubit, Stream<bool>>(CanvasMotionCubit.new);
}
