import '../../../../core/adapters/injector.dart';
import '../domain/repository/queue_repository.dart';
import '../domain/repository/socket_queue_repository.dart';
import '../domain/usecase/edit_queue.dart';
import '../domain/usecase/watch_queue.dart';
import '../domain/usecase/watch_queue_effects.dart';
import '../presentation/cubit/queue_cubit.dart';

/// Cada comando da fila leva a bancada: um repositório por bancada.
void registerQueueRepositories() {
  Injector.factoryParam<QueueRepository, String>(
    (workbenchId) => SocketQueueRepository(inject(), workbenchId),
  );
}

/// Os usecases são da bancada, como o repositório: pedem o id dela.
void registerQueueDomain() {
  Injector.factoryParam<WatchQueue, String>(
    (workbenchId) => WatchQueue(inject(workbenchId)),
  );
  Injector.factoryParam<EditQueue, String>(
    (workbenchId) => EditQueue(inject(workbenchId)),
  );
  Injector.factoryParam<WatchQueueEffects, String>(
    (workbenchId) => WatchQueueEffects(inject(workbenchId)),
  );
  Injector.factoryParam<QueueCubit, BenchNode>(
    (node) => QueueCubit(
      nodeId: node.nodeId,
      watch: inject(node.workbenchId),
      edit: inject(node.workbenchId),
      effects: inject(node.workbenchId),
    ),
  );
}
