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
    this.screen,
    this.status = '',
    this.statusTone,
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

  /// O id da tela do terminal, que se assina em `screen/<id>`: o mesmo do nó
  /// no canvas. O core o monta; a UI não junta bancada e nó.
  final String? screen;

  /// A linha embaixo do nome, pronta do core: o que faz agora ("precisa de
  /// você", "falhou — motivo"…) ou, parado, o papel. Vazia, não se desenha.
  final String status;

  /// A cor dessa linha; sem ela, o cinza de sempre.
  final StatusTone? statusTone;

  bool get isWorking => activity == 'working' || activity == 'starting';

  /// Terminal fechado: fica na coluna, mas não recebe nem entra no Tab.
  bool get isDead => activity == 'dead';

  factory ChatParticipantInfo.fromMap(Map<String, Object?> map) =>
      ChatParticipantInfo(
        id: map['id']! as String,
        address: map['address']! as String,
        isAgent: map['isAgent'] as bool? ?? false,
        role: map['role'] as String?,
        activity: map['activity'] as String? ?? 'waiting',
        tone: ActivityTone.parse(map['tone']),
        needsAttention: map['needsAttention'] as bool? ?? false,
        screen: map['screen'] as String?,
        status: map['status'] as String? ?? '',
        statusTone: StatusTone.parse(map['statusTone']),
      );
}

/// A cor da linha de estado como o core a nomeia: laranja pede você, vermelho
/// falhou, `agent` é a cor do próprio agente (trabalhando).
enum StatusTone {
  orange,
  red,
  agent;

  static StatusTone? parse(Object? raw) => switch (raw) {
    'orange' => orange,
    'red' => red,
    'agent' => agent,
    _ => null,
  };
}
