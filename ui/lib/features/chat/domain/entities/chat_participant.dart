import '../../../node/card/domain/entities/card_activity.dart'
    show ActivityTone;

/// Quem está na conversa: o agente ou o terminal, com o que faz agora.
class ChatParticipantInfo {
  const ChatParticipantInfo({
    required this.id,
    required this.address,
    required this.isAgent,
    this.role,
    this.activity = 'waiting',
    this.tone,
    this.needsAttention = false,
  });

  final String id;

  /// `bancada/id`: o endereço de dispatch.
  final String address;
  final bool isAgent;
  final String? role;

  /// O nome do estado em minúsculas, como o core o manda: `working`, `waiting`,
  /// `asking`, `done`…
  final String activity;

  /// A cor da bolinha e se o participante pede você: o core decide e manda
  /// pronto; sem tom, sem cor.
  final ActivityTone? tone;
  final bool needsAttention;

  bool get isWorking => activity == 'working' || activity == 'starting';

  factory ChatParticipantInfo.fromMap(Map<String, Object?> map) =>
      ChatParticipantInfo(
        id: map['id']! as String,
        address: map['address']! as String,
        isAgent: map['isAgent'] as bool? ?? false,
        role: map['role'] as String?,
        activity: map['activity'] as String? ?? 'waiting',
        tone: ActivityTone.parse(map['tone']),
        needsAttention: map['needsAttention'] as bool? ?? false,
      );
}
