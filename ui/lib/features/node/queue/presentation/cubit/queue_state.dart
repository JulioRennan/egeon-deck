import '../../domain/entities/prompt_queue.dart';

class QueueState {
  const QueueState({
    this.queue = const PromptQueue(),
    this.expanded,
    this.notice,
    this.draft,
    this.draftSerial = 0,
  });

  final PromptQueue queue;

  /// A tarefa aberta — uma por vez, como no Things.
  final String? expanded;

  /// O erro do último envio; some sozinho e deixa o que a fila diz de si.
  final String? notice;

  /// Rascunho vindo de fora para a linha de baixo. O [draftSerial] muda a cada
  /// um, para o mesmo texto de novo também valer.
  final String? draft;
  final int draftSerial;

  /// O que mostrar acima da lista: o erro recente, senão por que a fila não anda.
  String? get shownNotice => notice ?? queue.blocker;

  QueueState copyWith({
    PromptQueue? queue,
    String? Function()? expanded,
    String? Function()? notice,
    String? draft,
  }) => QueueState(
    queue: queue ?? this.queue,
    expanded: expanded != null ? expanded() : this.expanded,
    notice: notice != null ? notice() : this.notice,
    draft: draft ?? this.draft,
    draftSerial: draft != null ? draftSerial + 1 : draftSerial,
  );
}
