import '../../../core/adapters/injector.dart';
import '../domain/repository/chat_repository.dart';
import '../domain/repository/socket_chat_repository.dart';
import '../domain/usecase/chat_actions.dart';
import '../domain/usecase/watch_chat.dart';
import '../domain/entities/chat_thread.dart';
import '../presentation/cubit/chat_composer_cubit.dart';
import '../presentation/cubit/chat_conversation_cubit.dart';
import '../presentation/cubit/chat_queue_panel_cubit.dart';
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
  Injector.factoryParam<ChatConversationCubit, String>(
    (workbenchId) => ChatConversationCubit(
      workbenchId: workbenchId,
      watch: inject(),
      actions: inject(),
    ),
  );
  // O composer e o painel seguem a thread da conversa da mesma bancada.
  Injector.factoryParam<ChatComposerCubit, ChatFeed>(
    (feed) => ChatComposerCubit(
      workbenchId: feed.workbenchId,
      threads: feed.threads,
      actions: inject(),
    ),
  );
  Injector.factoryParam<ChatQueuePanelCubit, ChatFeed>(
    (feed) => ChatQueuePanelCubit(
      workbenchId: feed.workbenchId,
      threads: feed.threads,
      actions: inject(),
    ),
  );
}

/// A thread de uma bancada para quem a segue sem assiná-la de novo.
typedef ChatFeed = ({String workbenchId, Stream<ChatThread> threads});
