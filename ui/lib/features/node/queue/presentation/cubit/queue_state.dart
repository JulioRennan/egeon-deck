part of 'queue_cubit.dart';

/// O último envio que não foi: o que se tentou e o erro do core.
final class QueueSendFailure {
  const QueueSendFailure(this.error, {required this.reply});

  final QueueError error;

  /// Era uma resposta ao agente, não um envio.
  final bool reply;
}

/// O que a linha de aviso segue do [QueueCubit].
typedef QueueNoticeSource = ({
  Stream<PromptQueue> queues,
  Stream<QueueSendFailure?> deliveries,
});

/// A fila como o core a manda e, por cima, qual tarefa está aberta.
sealed class QueueState {
  const QueueState(this.queue);

  final PromptQueue queue;
}

/// Antes do primeiro estado do core.
final class QueueWaiting extends QueueState {
  const QueueWaiting() : super(const PromptQueue());
}

/// A lista sem nenhuma tarefa aberta.
final class QueueBrowsing extends QueueState {
  const QueueBrowsing(super.queue);
}

/// Uma tarefa aberta — uma por vez, como no Things.
final class QueueEditing extends QueueState {
  const QueueEditing(super.queue, {required this.open});

  final String open;
}
