import 'queue_item.dart';

/// Um destino possível da fila: um nó ligado por aresta.
class QueueTarget {
  const QueueTarget({required this.id, required this.label});

  final String id;
  final String label;

  factory QueueTarget.fromMap(Map<String, Object?> map) => QueueTarget(
    id: map['id']! as String,
    label: map['label'] as String? ?? map['id']! as String,
  );

  Map<String, Object?> toMap() => {'id': id, 'label': label};
}

/// A fila de um nó: os itens na ordem de envio, o modo automático e para quem.
class PromptQueue {
  const PromptQueue({
    this.items = const [],
    this.auto = false,
    this.target,
    this.targets = const [],
    this.blocker,
    this.destination,
    this.pending = 0,
    this.asking = false,
    this.summary = '',
    this.subtitle = '',
    this.imageExtensions = const [],
  });

  final List<QueueItem> items;

  /// Manda o próximo sozinha quando o agente fecha o turno.
  final bool auto;

  /// O destino escolhido entre os ligados. Nulo, ou um que não está mais
  /// ligado, cai no primeiro ligado.
  final String? target;

  /// Os nós ligados por aresta, com nome de gente.
  final List<QueueTarget> targets;

  /// Por que a fila não anda ("Ligue a fila a um agente…"), ou nulo.
  final String? blocker;

  /// O destino em vigor, como o core resolveu: o escolhido se ainda está ligado,
  /// senão o primeiro. Nulo é "ninguém ligado".
  final String? destination;

  /// Quantas tarefas esperam para ir (a em branco não conta).
  final int pending;

  /// O agente perguntou numa tarefa e espera você.
  final bool asking;

  /// A linha da coluna do chat, já escrita.
  final String summary;

  /// O subtítulo do card.
  final String subtitle;

  /// As extensões de arquivo que viram print da tarefa.
  final List<String> imageExtensions;

  factory PromptQueue.fromMap(Map<String, Object?> map) => PromptQueue(
    items: [
      for (final i in (map['items'] as List<Object?>? ?? const []))
        QueueItem.fromMap(i! as Map<String, Object?>),
    ],
    auto: map['auto'] as bool? ?? false,
    target: map['target'] as String?,
    targets: [
      for (final t in (map['targets'] as List<Object?>? ?? const []))
        QueueTarget.fromMap(t! as Map<String, Object?>),
    ],
    blocker: map['blocker'] as String?,
    destination: map['destination'] as String?,
    pending: (map['pending'] as num?)?.toInt() ?? 0,
    asking: map['asking'] as bool? ?? false,
    summary: map['summary'] as String? ?? '',
    subtitle: map['subtitle'] as String? ?? '',
    imageExtensions: [
      for (final e in (map['image_extensions'] as List<Object?>? ?? const []))
        e! as String,
    ],
  );

  Map<String, Object?> toMap() => {
    'items': [for (final i in items) i.toMap()],
    'auto': auto,
    'target': target,
    'targets': [for (final t in targets) t.toMap()],
    'blocker': blocker,
    'destination': destination,
    'pending': pending,
    'asking': asking,
    'summary': summary,
    'subtitle': subtitle,
    'image_extensions': imageExtensions,
  };

  int? indexOf(String id) {
    final index = items.indexWhere((i) => i.id == id);
    return index < 0 ? null : index;
  }

  /// Leva o item para a posição [index] da lista SEM ele — a conta que o
  /// arrasto faz, contando só as linhas que ficaram no lugar.
  PromptQueue moved(String id, {required int to}) {
    final from = indexOf(id);
    if (from == null) return this;
    final next = [...items];
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
    return _withItems(next);
  }

  /// Sobe ou desce um item, sem sair da lista.
  PromptQueue movedBy(String id, int offset) {
    final from = indexOf(id);
    if (from == null) return this;
    final to = (from + offset).clamp(0, items.length - 1);
    if (to == from) return this;
    final next = [...items];
    next.insert(to, next.removeAt(from));
    return _withItems(next);
  }

  PromptQueue _withItems(List<QueueItem> next) => PromptQueue(
    items: next,
    auto: auto,
    target: target,
    targets: targets,
    blocker: blocker,
  );
}
