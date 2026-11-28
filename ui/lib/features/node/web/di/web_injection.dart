import '../../../../core/adapters/injector.dart';
import '../../../../commons/widgets/web_surface_channel.dart';
import '../domain/repository/socket_web_repository.dart';
import '../domain/repository/web_repository.dart';
import '../domain/usecase/edit_web.dart';
import '../domain/usecase/watch_web.dart';
import '../presentation/cubit/web_capture_registry.dart';
import '../presentation/cubit/web_cubit.dart';

/// Cada comando da página leva a bancada: um repositório por bancada. A página
/// nativa também é do mundo real: o teste registra a falsa.
void registerWebRepositories() {
  Injector.factoryParam<WebRepository, String>(
    (workbenchId) => SocketWebRepository(inject(), workbenchId),
  );
  Injector.singleton<WebControllerFactory>(
    (profile, profileId) => createChannelWebSurfaceController(
      profile: profile,
      profileId: profileId,
    ),
  );
}

/// Único: o registro das páginas vivas, para o `/shot` de um nó web incluí-las.
/// Os usecases são da bancada, como o repositório: pedem o id dela.
void registerWebDomain() {
  Injector.lazySingleton(WebCaptureRegistry.new);

  Injector.factoryParam<WatchWeb, String>(
    (workbenchId) => WatchWeb(inject(workbenchId)),
  );
  Injector.factoryParam<EditWeb, String>(
    (workbenchId) => EditWeb(inject(workbenchId)),
  );
  Injector.factoryParam<WebCubit, BenchNode>(
    (node) => WebCubit(
      nodeId: node.nodeId,
      watch: inject(node.workbenchId),
      edit: inject(node.workbenchId),
      createController: inject(),
      captures: inject(),
    ),
  );
}
