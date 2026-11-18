part of 'queue_cubit.dart';

/// O último envio que não foi: o que se tentou e o erro do core.
final class QueueSendFailure {
  const QueueSendFailure(this.error, {required this.reply});

  final QueueError error;

  /// Era uma resposta ao agente, não um envio.
  final bool reply;
}

/// A fila como o core a manda e o que é só da tela: a tarefa aberta, a falha
/// do último envio e o rascunho vindo de fora.
final class QueueState {
  const QueueState({
    this.queue = const PromptQueue(),
    this.expanded,
    this.failure,
    this.draft,
    this.draftSerial = 0,
  });

  final PromptQueue queue;

  /// A tarefa aberta — uma por vez, como no Things.
  final String? expanded;

  /// O erro do último envio; some sozinho e deixa o que a fila diz de si.
  final QueueSendFailure? failure;

  /// Rascunho vindo de fora para a linha de baixo. O [draftSerial] muda a cada
  /// um, para o mesmo texto de novo também valer.
  final String? draft;
  final int draftSerial;

  QueueState copyWith({
    PromptQueue? queue,
    String? Function()? expanded,
    QueueSendFailure? Function()? failure,
    String? draft,
  }) => QueueState(
    queue: queue ?? this.queue,
    expanded: expanded != null ? expanded() : this.expanded,
    failure: failure != null ? failure() : this.failure,
    draft: draft ?? this.draft,
    draftSerial: draft != null ? draftSerial + 1 : draftSerial,
  );
}
