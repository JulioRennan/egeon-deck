import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/permission_request.dart';
import '../../domain/errors/chat_error.dart';
import '../../domain/usecase/chat_actions.dart';
import '../../domain/usecase/watch_chat.dart';

part 'chat_conversation_state.dart';

/// A conversa de uma bancada: as linhas, quem está nela e os pedidos de
/// permissão, inteiros como o core os manda. É dono da assinatura do chat:
/// abre ao nascer e cancela no `close()`; o composer e o painel da fila seguem
/// [threads] em vez de assinar de novo.
class ChatConversationCubit extends Cubit<ChatConversationState> {
  ChatConversationCubit({
    required this.workbenchId,
    required WatchChat watch,
    required this._actions,
  }) : super(const ChatOpening()) {
    _subscription = watch(workbenchId).listen(_onThread);
  }

  final String workbenchId;
  final ChatActions _actions;
  StreamSubscription<ChatThread>? _subscription;
  var _thread = const ChatThread();
  final _changes = StreamController<ChatThread>.broadcast();

  void _onThread(ChatThread thread) {
    _thread = thread;
    emit(
      ChatShown(
        blocks: thread.blocks,
        participants: thread.participants,
        permissions: thread.permissions,
      ),
    );
    _changes.add(thread);
  }

  /// A thread a cada mudança, começando pela de agora: quem chega depois não
  /// espera o próximo evento do core para saber quem está na conversa.
  Stream<ChatThread> get threads {
    late final StreamController<ChatThread> out;
    StreamSubscription<ChatThread>? changes;
    out = StreamController<ChatThread>(
      onListen: () {
        out.add(_thread);
        changes = _changes.stream.listen(out.add);
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  /// Os botões da bandeja: permitir, sempre ou negar.
  void answer(String request, String answer) =>
      _fire(_actions.answerPermission(workbenchId, request, answer: answer));

  /// Uma opção escolhida de uma pergunta de uma só.
  void choose(String request, String choice) =>
      _fire(_actions.answerPermission(workbenchId, request, choice: choice));

  /// As respostas de várias perguntas, juntas.
  void answerAll(String request, Map<String, List<String>> answers) =>
      _fire(_actions.answerPermission(workbenchId, request, answers: answers));

  /// Abre ou fecha um passo: o clique no título dele.
  void toggleStep(String blockId) =>
      _fire(_actions.toggleStep(workbenchId, blockId));

  /// Avança o nível da capa de uma sequência de passos.
  void cycleGroup(String blockId) =>
      _fire(_actions.cycleGroup(workbenchId, blockId));

  /// A janela de histórico cresce quando se rola até o começo. Devolve o
  /// futuro para quem rola saber se o pedido falhou e poder repetir.
  Future<void> loadMore() => _actions.loadMore(workbenchId);

  /// Arquiva a conversa; quem chama já confirmou.
  void clear() => _fire(_actions.clear(workbenchId));

  /// O link da resposta, no navegador; recusa do sistema não tem o que mostrar.
  void openLink(String url) => _fire(_actions.openLink(url));

  /// Gesto é "mande e siga": o que vale é a thread que o core devolve.
  void _fire(Future<void> future) =>
      unawaited(future.catchError((_) {}, test: (error) => error is ChatError));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _changes.close();
    return super.close();
  }
}
