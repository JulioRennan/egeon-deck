import 'dart:async';

import '../entities/chat_thread.dart';
import '../entities/chat_update.dart';
import '../repository/chat_repository.dart';

/// A thread de uma bancada, sempre inteira. Aplica o diff do core e, se uma
/// revisão se perdeu pelo caminho, pede a thread de novo em vez de seguir com
/// uma lista torta.
class WatchChat {
  const WatchChat(this._repository);

  final ChatRepository _repository;

  /// Controller em vez de `async*`: cancelar um gerador parado num `await for`
  /// só termina quando ele acorda, e o `close()` do cubit esperaria.
  Stream<ChatThread> call(String workbenchId) {
    late final StreamController<ChatThread> out;
    StreamSubscription<ChatUpdate>? updates;
    var thread = const ChatThread();
    var healing = false;

    Future<void> heal() async {
      if (healing) return;
      healing = true;
      try {
        thread = await _repository.snapshot(workbenchId);
        if (!out.isClosed) out.add(thread);
      } on Object {
        // O próximo evento tenta de novo.
      } finally {
        healing = false;
      }
    }

    void onUpdate(ChatUpdate update) {
      final resets = update.ops.any((op) => op is ResetOp);
      if (!resets) {
        // Evento velho (já veio no instantâneo): descarta.
        if (update.rev <= thread.rev) return;
        // Buraco: o diff não vale em cima de uma lista que não é a base dele.
        if (update.rev != thread.rev + 1) {
          unawaited(heal());
          return;
        }
      }
      thread = thread.apply(update);
      out.add(thread);
    }

    out = StreamController<ChatThread>(
      onListen: () => updates = _repository
          .watch(workbenchId)
          .listen(onUpdate, onError: out.addError),
      onCancel: () => updates?.cancel(),
    );
    return out.stream;
  }
}
