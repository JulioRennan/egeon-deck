/// Uma fila da bancada na coluna do chat. O resumo ("2 pendentes · com front",
/// "? pergunta") e se há pergunta em aberto vêm prontos do core.
class ChatQueueInfo {
  const ChatQueueInfo({
    required this.id,
    required this.summary,
    this.asking = false,
  });

  factory ChatQueueInfo.fromMap(Map<String, Object?> map) => ChatQueueInfo(
    id: map['id']! as String,
    summary: map['summary'] as String? ?? '',
    asking: map['asking'] as bool? ?? false,
  );

  final String id;
  final String summary;

  /// A fila tem uma pergunta esperando você: o resumo vai em laranja.
  final bool asking;
}
