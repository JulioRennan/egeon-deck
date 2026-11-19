import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_queue.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/errors/chat_error.dart';
import '../../domain/usecase/chat_actions.dart';

part 'chat_queue_panel_state.dart';

/// As filas da bancada na coluna e a que está aberta no painel ao lado da
/// conversa. A lista chega pela thread da conversa; a aberta é da tela e só
/// vale enquanto a fila continua na lista.
class ChatQueuePanelCubit extends Cubit<ChatQueuePanelState> {
  ChatQueuePanelCubit({
    required this.workbenchId,
    required Stream<ChatThread> threads,
    required this._actions,
  }) : super(const QueuePanelClosed()) {
    _subscription = threads.listen((thread) {
      _queues = thread.queues;
      _derive();
    });
  }

  final String workbenchId;
  final ChatActions _actions;
  StreamSubscription<ChatThread>? _subscription;
  final _refusals = StreamController<ChatError>.broadcast();

  var _queues = const <ChatQueueInfo>[];
  String? _shown;

  /// A recusa ao criar uma fila: um aviso de uma linha que some sozinho.
  Stream<ChatError> get refusals => _refusals.stream;

  void _derive() {
    if (isClosed) return;
    final open = _queues.where((q) => q.id == _shown).firstOrNull;
    emit(switch (open) {
      final queue? => QueuePanelOpen(_queues, queue),
      null => QueuePanelClosed(_queues),
    });
  }

  /// Clicar numa fila abre a lista dela ao lado da conversa; clicar na que já
  /// está aberta a fecha.
  void toggle(String id) {
    _shown = state is QueuePanelOpen && _shown == id ? null : id;
    _derive();
  }

  void closePanel() {
    _shown = null;
    _derive();
  }

  /// "+ Nova fila": o core cria e liga ao [agent] (o em foco, que só a tela
  /// sabe); a nova abre no painel.
  Future<void> newQueue({String? agent}) async {
    try {
      final node = await _actions.newQueue(workbenchId, agent: agent);
      if (isClosed) return;
      _shown = node;
      _derive();
    } on ChatError catch (failure) {
      if (!_refusals.isClosed) _refusals.add(failure);
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _refusals.close();
    return super.close();
  }
}
