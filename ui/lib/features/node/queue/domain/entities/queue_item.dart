/// Uma mensagem na thread de uma tarefa — do agente ou sua.
enum MessageKind {
  /// O agente perguntou e espera você.
  question,

  /// O agente comentou — andamento, achado, o que fez.
  note,

  /// O agente marcou a tarefa como feita.
  done,

  /// Você, respondendo ou comentando.
  reply;

  static MessageKind parse(Object? raw) =>
      values.firstWhere((k) => k.name == raw, orElse: () => MessageKind.note);
}

/// Instante no fio: ISO 8601 em UTC (`2026-11-18T03:12:00.000Z`).
DateTime? parseWireTime(Object? raw) => switch (raw) {
  final String text => DateTime.tryParse(text),
  final num seconds => DateTime.fromMillisecondsSinceEpoch(
    seconds.toInt() * 1000,
    isUtc: true,
  ),
  _ => null,
};

String? wireTime(DateTime? time) => time?.toUtc().toIso8601String();

class QueueMessage {
  const QueueMessage({
    required this.kind,
    required this.text,
    required this.at,
    this.author,
  });

  /// O nó do agente; nulo é você.
  final String? author;
  final MessageKind kind;
  final String text;
  final DateTime at;

  factory QueueMessage.fromMap(Map<String, Object?> map) => QueueMessage(
    author: map['author'] as String?,
    kind: MessageKind.parse(map['kind']),
    text: map['text'] as String? ?? '',
    at: parseWireTime(map['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, Object?> toMap() => {
    'author': author,
    'kind': kind.name,
    'text': text,
    'at': wireTime(at),
  };
}

enum ItemStatus {
  /// Anotado, ainda não foi.
  pending,

  /// Entregue ao agente, e o turno dele ainda não fechou.
  sent,

  /// O agente fechou o turno em que recebeu este item.
  done;

  static ItemStatus parse(Object? raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => ItemStatus.pending);
}

/// Uma tarefa da fila: um texto corrido e os prints — juntos, o prompt — e a
/// thread do que o agente e você disseram sobre ela.
class QueueItem {
  const QueueItem({
    required this.id,
    this.text = '',
    this.images = const [],
    this.status = ItemStatus.pending,
    this.sentTo,
    this.sentAt,
    this.thread = const [],
    this.awaiting = false,
    this.locked = false,
    this.empty = false,
  });

  final String id;

  /// Um texto só, como numa nota: não há título separado do corpo.
  final String text;

  /// Nomes dos arquivos na pasta da fila.
  final List<String> images;
  final ItemStatus status;

  /// O nó que recebeu, e quando.
  final String? sentTo;
  final DateTime? sentAt;
  final List<QueueMessage> thread;

  /// O agente perguntou e você ainda não respondeu: a fila não anda.
  final bool awaiting;

  /// Já foi a um agente: o texto e os prints são o registro do que foi pedido,
  /// e a partir daqui a conversa segue pela thread.
  final bool locked;

  /// Sem texto (aparado) e sem imagem: não há o que mandar.
  final bool empty;

  factory QueueItem.fromMap(Map<String, Object?> map) => QueueItem(
    id: map['id']! as String,
    text: map['text'] as String? ?? '',
    images: [
      for (final i in (map['images'] as List<Object?>? ?? const []))
        i! as String,
    ],
    status: ItemStatus.parse(map['status']),
    sentTo: map['sent_to'] as String?,
    sentAt: parseWireTime(map['sent_at']),
    thread: [
      for (final m in (map['thread'] as List<Object?>? ?? const []))
        QueueMessage.fromMap(m! as Map<String, Object?>),
    ],
    awaiting: map['awaiting'] as bool? ?? false,
    locked: map['locked'] as bool? ?? false,
    empty: map['empty'] as bool? ?? false,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'text': text,
    'images': images,
    'status': status.name,
    'sent_to': ?sentTo,
    'sent_at': ?wireTime(sentAt),
    'thread': [for (final m in thread) m.toMap()],
    'awaiting': awaiting,
    'locked': locked,
    'empty': empty,
  };
}
