import '../../../core/adapters/injector.dart';
import '../domain/repository/chat_repository.dart';
import '../domain/repository/socket_chat_repository.dart';
import '../domain/usecase/chat_actions.dart';
import '../domain/usecase/watch_chat.dart';
import '../presentation/cubit/chat_cubit.dart';
import '../presentation/cubit/queue_panel_width.dart';

void registerChatRepositories() {
  Injector.factory<ChatRepository>(() => SocketChatRepository(inject()));
}

/// Única: a largura do painel da fila, uma só para todas as bancadas.
void registerChatDomain() {
  Injector.lazySingleton(
    QueuePanelWidth.new,
    dispose: (width) => width.dispose(),
  );

  Injector.factory(() => WatchChat(inject()));
  Injector.factory(() => ChatActions(inject()));
  Injector.factoryParam<ChatCubit, String>(
    (workbenchId) =>
        ChatCubit(workbenchId: workbenchId, watch: inject(), actions: inject()),
  );
}
