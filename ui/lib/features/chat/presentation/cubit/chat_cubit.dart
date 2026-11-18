import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_completion.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_queue.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/permission_request.dart';
import '../../domain/errors/chat_error.dart';
import '../../domain/usecase/chat_actions.dart';
import '../../domain/usecase/watch_chat.dart';

part 'chat_state.dart';

/// O chat de uma bancada. É dono da assinatura: abre ao nascer e cancela no
/// `close()`. As linhas vêm do core inteiras; aqui só se guarda o que é da
/// tela — quem está sendo citado e quantas vezes o usuário mandou.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    required this.workbenchId,
    required WatchChat watch,
    required this._actions,
  }) : super(const ChatState()) {
    _subscription = watch(workbenchId).listen(_onThread);
  }

  final String workbenchId;
  final ChatActions _actions;
  StreamSubscription<ChatThread>? _subscription;

  void _onThread(ChatThread thread) => emit(
    state.copyWith(
      blocks: thread.blocks,
      participants: thread.participants,
      queues: thread.queues,
      permission: thread.permission,
      clearPermission: thread.permission == null,
    ),
  );

  /// Clicar numa fila abre a lista dela ao lado da conversa; clicar na que já
  /// está aberta a fecha.
  void toggleQueue(String id) => emit(
    state.shownQueue == id
        ? state.copyWith(clearShownQueue: true)
        : state.copyWith(shownQueue: id),
  );

  void closeQueue() => emit(state.copyWith(clearShownQueue: true));

  /// "+ Nova fila": o core cria e liga ao agente em foco (que só a tela sabe);
  /// a nova abre no painel. A recusa vira um aviso de uma linha.
  Future<void> newQueue() async {
    try {
      final node = await _actions.newQueue(workbenchId, agent: _queueAgent());
      if (!isClosed) emit(state.copyWith(shownQueue: node));
    } on ChatError catch (failure) {
      _warn(failure);
    }
  }

  /// A fila nova liga a um agente: o que está em foco, e na falta dele o
  /// primeiro. Terminal em foco não vale — fila só fala com agente.
  String? _queueAgent() {
    final agents = state.agents;
    final focused = agents.where((a) => a.id == state.focus).firstOrNull;
    return (focused ?? agents.firstOrNull)?.id;
  }

  Timer? _noticeTimer;

  void _warn(ChatError failure) {
    if (isClosed) return;
    emit(state.copyWith(queueFailure: failure));
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (!isClosed) emit(state.copyWith(clearQueueFailure: true));
    });
  }

  /// Clicar num participante o põe em foco: é para ele que o composer manda.
  void focusOn(String id) => emit(state.copyWith(focus: id));

  /// Tab no composer alterna entre os agentes.
  void focusNext() {
    final agents = state.agents;
    if (agents.length < 2) return;
    final at = agents.indexWhere((a) => a.id == state.target?.id);
    emit(state.copyWith(focus: agents[(at + 1) % agents.length].id));
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

  /// As sugestões do menu do composer para o texto e o cursor; falha vira
  /// "sem sugestões" — o menu é conforto, não pode atrapalhar quem digita.
  Future<ChatCompletion> complete(String text, int caret, {String? search}) =>
      _actions
          .complete(
            workbenchId,
            text,
            caret,
            to: state.target?.id,
            search: search,
          )
          .catchError(
            (_) => ChatCompletion.none(caret),
            test: (error) => error is ChatError,
          );

  /// Arquiva a conversa; quem chama já confirmou.
  void clear() => _fire(_actions.clear(workbenchId));

  void quote(ChatBlock block) => emit(state.copyWith(quote: block));

  void clearQuote() => emit(state.copyWith(clearQuote: true));

  /// Manda a mensagem. Texto vazio não vai; a citação sai junto e se esvazia.
  /// A thread passa a descer até o fim, de onde quer que esteja.
  void send(String text) {
    final typed = text.trim();
    final target = state.target;
    if (typed.isEmpty || target == null) return;
    _fire(
      _actions.send(
        workbenchId,
        to: [target.id],
        text: typed,
        quoteKey: state.quote?.messageKey,
      ),
    );
    emit(state.copyWith(sends: state.sends + 1, clearQuote: true));
  }

  /// Gesto é "mande e siga": o que vale é a thread que o core devolve.
  void _fire(Future<void> future) =>
      unawaited(future.catchError((_) {}, test: (error) => error is ChatError));

  @override
  Future<void> close() async {
    _noticeTimer?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
