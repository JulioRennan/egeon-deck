/// Um efeito que o core manda no tópico da fila, fora do estado.
sealed class QueueEffect {
  const QueueEffect();

  /// O efeito, ou nulo para o que não é da fila.
  static QueueEffect? tryParse(Map<String, Object?> map) =>
      switch (map['effect']) {
        'draft' => QueueDraft(map['text'] as String? ?? ''),
        'open_item' => QueueOpenItem(map['item']! as String),
        _ => null,
      };
}

/// Um rascunho vindo de fora (o `egeon` do terminal): cai na linha de baixo.
class QueueDraft extends QueueEffect {
  const QueueDraft(this.text);
  final String text;
}

/// Abrir a tarefa [item] — a rota `/queue?open=` faz o clique.
class QueueOpenItem extends QueueEffect {
  const QueueOpenItem(this.item);
  final String item;
}
