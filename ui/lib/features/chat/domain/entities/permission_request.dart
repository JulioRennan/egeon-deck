/// Uma pergunta do AskUserQuestion, que passa pela mesma bandeja.
class PermissionQuestion {
  const PermissionQuestion({
    required this.question,
    required this.options,
    this.header,
    this.multiSelect = false,
  });

  final String question;
  final String? header;
  final List<String> options;
  final bool multiSelect;

  factory PermissionQuestion.fromMap(Map<String, Object?> map) =>
      PermissionQuestion(
        question: map['question']! as String,
        header: map['header'] as String?,
        options: [
          for (final o in (map['options'] as List<Object?>? ?? const []))
            o is Map<String, Object?> ? o['label']! as String : o! as String,
        ],
        multiSelect: map['multiSelect'] as bool? ?? false,
      );
}

/// O pedido de permissão em aberto: o agente quer usar uma ferramenta, ou faz
/// perguntas.
class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.tool,
    this.summary = '',
    this.detail,
    this.canAlwaysAllow = false,
    this.questions = const [],
    this.agent,
  });

  final String id;
  final String tool;

  /// Uma linha: o comando, o arquivo, a URL — o que se aprova.
  final String summary;

  /// A descrição que o próprio agente deu, quando deu.
  final String? detail;

  /// O CLI sugeriu regras para o "sempre".
  final bool canAlwaysAllow;
  final List<PermissionQuestion> questions;

  /// Quem pediu (id do agente), se o core disser.
  final String? agent;

  /// Pergunta, e não permissão de ferramenta.
  bool get isQuestion => questions.isNotEmpty;

  /// As respostas só se enviam juntas, com "Responder": mais de uma pergunta ou
  /// alguma de múltipla escolha.
  bool get collects =>
      questions.length > 1 || questions.any((q) => q.multiSelect);

  factory PermissionRequest.fromMap(Map<String, Object?> map) =>
      PermissionRequest(
        id: map['id']! as String,
        tool: map['tool'] as String? ?? '',
        summary: map['summary'] as String? ?? '',
        detail: map['detail'] as String?,
        canAlwaysAllow:
            (map['always'] ?? map['canAlwaysAllow']) as bool? ?? false,
        questions: [
          for (final q in (map['questions'] as List<Object?>? ?? const []))
            PermissionQuestion.fromMap(q! as Map<String, Object?>),
        ],
        agent: (map['agent'] ?? map['node']) as String?,
      );
}
