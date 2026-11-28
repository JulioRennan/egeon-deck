import '../../../../commons/utils/wire.dart';
import 'chat_markdown.dart';

/// Um pedaço de uma linha de código, classificado pelo core.
class CodeToken {
  const CodeToken(this.kind, this.text);

  /// `plain`, `keyword`, `type`, `string`, `comment`, `number`, `tag`,
  /// `attribute`.
  final String kind;
  final String text;

  factory CodeToken.fromMap(Map<String, Object?> map) => CodeToken(
    map['kind'] as String? ?? 'plain',
    map['text'] as String? ?? '',
  );
}

/// Quem fala: o usuário não tem `Who`; cada agente tem o id, o endereço de
/// dispatch e, às vezes, o papel.
class ChatWho {
  const ChatWho({
    required this.id,
    required this.address,
    required this.isAgent,
    this.role,
  });

  final String id;
  final String address;
  final bool isAgent;
  final String? role;

  factory ChatWho.fromMap(Map<String, Object?> map) => ChatWho(
    id: map['id']! as String,
    address: map['address']! as String,
    isAgent: map['isAgent'] as bool? ?? false,
    role: map['role'] as String?,
  );
}

/// Um passo que o agente deu: comando, edição, leitura ou envio.
class ChatStep {
  const ChatStep({
    required this.glyph,
    required this.text,
    this.sendTo,
    this.detail,
    this.diff,
    this.output,
    this.isError = false,
  });

  /// `$` comando · `±` edição · `→` outra ferramenta · `⇄` egeon send.
  final String glyph;
  final String text;
  final String? sendTo;
  final String? detail;
  final List<String>? diff;
  final String? output;
  final bool isError;

  /// Tem mais que o título: comando ou saída. Diff não conta, ele nunca recolhe.
  bool get isExpandable => detail != null || output != null;

  factory ChatStep.fromMap(Map<String, Object?> map) => ChatStep(
    glyph: map['glyph'] as String? ?? '→',
    text: map['text'] as String? ?? '',
    sendTo: map['sendTo'] as String?,
    detail: map['detail'] as String?,
    diff: map['diff'] == null
        ? null
        : [for (final l in map['diff']! as List<Object?>) l! as String],
    output: map['output'] as String?,
    isError: map['isError'] as bool? ?? false,
  );
}

/// A mensagem citada por uma resposta.
class ChatQuote {
  const ChatQuote({
    required this.text,
    required this.at,
    required this.targetKey,
    this.authorId,
  });

  /// `null` é o usuário.
  final String? authorId;
  final String text;
  final DateTime at;

  /// A `messageKey` da linha citada: é o alvo da rolagem ao clicar.
  final String targetKey;

  factory ChatQuote.fromMap(Map<String, Object?> map) => ChatQuote(
    authorId: map['authorId'] as String?,
    text: map['text']! as String,
    at: DateTime.parse(map['at']! as String),
    targetKey: map['targetKey']! as String,
  );
}

class ChatCost {
  const ChatCost({required this.text, required this.detail});

  final String text;
  final String detail;

  factory ChatCost.fromMap(Map<String, Object?> map) =>
      ChatCost(text: map['text']! as String, detail: map['detail']! as String);
}

/// O que o agente está fazendo agora, na linha de status da bolha ao vivo.
sealed class ChatLive {
  const ChatLive();

  factory ChatLive.fromMap(Map<String, Object?> map) => switch (map['state']) {
    'thinking' => const LiveThinking(),
    'asking' => const LiveAsking(),
    'step' => LiveStep(ChatStep.fromMap(map['step']! as Map<String, Object?>)),
    _ => const LiveWorking(),
  };

  String get label;
}

class LiveWorking extends ChatLive {
  const LiveWorking();

  @override
  String get label => 'trabalhando…';
}

class LiveThinking extends ChatLive {
  const LiveThinking();

  @override
  String get label => 'pensando…';
}

class LiveAsking extends ChatLive {
  const LiveAsking();

  @override
  String get label => 'precisa de você';
}

class LiveStep extends ChatLive {
  const LiveStep(this.step);

  final ChatStep step;

  @override
  String get label => '${step.glyph} ${step.text}';
}

/// Quanto de uma sequência de passos está à vista.
enum GroupLevel {
  summary,
  titles,
  details;

  static GroupLevel fromWire(Object? raw) =>
      values.firstWhere((l) => l.name == raw, orElse: () => GroupLevel.summary);
}

/// Uma linha da thread. A bolha é o conjunto de linhas com a mesma
/// [messageKey]: a primeira arredonda em cima, a última embaixo. O [id] é
/// estável entre montagens e é o alvo de rolagem de uma citação.
sealed class ChatBlock {
  const ChatBlock({
    required this.id,
    required this.messageKey,
    required this.first,
    required this.last,
    required this.depth,
    required this.raw,
  });

  final String id;
  final String messageKey;
  final bool first;
  final bool last;

  /// Um degrau de recuo por nível: o passo de uma capa entra um tab.
  final int depth;

  /// O mapa como veio: o core manda a linha inteira a cada `update`, e é por
  /// ele que se sabe se mudou.
  final Map<String, Object?> raw;

  factory ChatBlock.fromMap(Map<String, Object?> map) {
    final id = map['id']! as String;
    final key = map['messageKey']! as String;
    final first = map['first'] as bool? ?? false;
    final last = map['last'] as bool? ?? false;
    final depth = map['depth'] as int? ?? 0;
    ChatWho? who(String field) => map[field] is Map<String, Object?>
        ? ChatWho.fromMap(map[field]! as Map<String, Object?>)
        : null;
    final quote = map['quote'] == null
        ? null
        : ChatQuote.fromMap(map['quote']! as Map<String, Object?>);
    switch (map['kind']) {
      case 'prompt':
        return PromptBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          to: who('to')!,
          fromText: map['from'] as String?,
          text: map['text']! as String,
          at: DateTime.parse(map['at']! as String),
          quote: quote,
          pending: map['pending'] as bool? ?? false,
          mention: map['mention'] as bool? ?? false,
        );
      case 'header':
        return HeaderBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          at: map['at'] == null ? null : DateTime.parse(map['at']! as String),
          quote: quote,
          cost: map['cost'] == null
              ? null
              : ChatCost.fromMap(map['cost']! as Map<String, Object?>),
        );
      case 'prose':
        return ProseBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          blocks: mapList(map['blocks'], MdBlock.fromMap),
        );
      case 'code':
        return CodeBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          language: map['language'] as String?,
          code: map['code']! as String,
          lines: map['spans'] == null
              ? null
              : [
                  for (final line in map['spans']! as List<Object?>)
                    mapList(line, CodeToken.fromMap),
                ],
        );
      case 'step':
        return StepBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          step: ChatStep.fromMap(map['step']! as Map<String, Object?>),
          expanded: map['expanded'] as bool? ?? false,
        );
      case 'group':
        return GroupBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          count: map['count']! as int,
          lastStep: map['lastStep'] as String? ?? '',
          level: GroupLevel.fromWire(map['level']),
        );
      case 'diff':
        return DiffBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          file: map['file']! as String,
          lines: [for (final l in map['diff']! as List<Object?>) l! as String],
        );
      case 'status':
        return StatusBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
          live: ChatLive.fromMap(map['live']! as Map<String, Object?>),
        );
      case 'typing':
        return TypingBlock(
          id: id,
          messageKey: key,
          first: first,
          last: last,
          depth: depth,
          raw: map,
          from: who('from')!,
        );
    }
    throw FormatException('bloco de chat desconhecido: ${map['kind']}');
  }
}

/// Prompt do usuário (ou de outro agente, com [fromText]).
class PromptBlock extends ChatBlock {
  const PromptBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.to,
    required this.text,
    required this.at,
    required this.pending,
    required this.mention,
    this.fromText,
    this.quote,
  });

  final ChatWho to;

  /// Quem mandou, quando não foi o usuário: o id do agente ou o endereço cru.
  final String? fromText;
  final String text;
  final DateTime at;
  final ChatQuote? quote;

  /// Saiu agora e o transcript ainda não confirmou.
  final bool pending;

  /// Mostra `@destinatário` no começo: só quando a mensagem não é contínua.
  final bool mention;
}

/// Cabeçalho da resposta: nome, endereço, hora (`null` é "agora"), a citação e
/// o custo do turno.
class HeaderBlock extends ChatBlock {
  const HeaderBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    this.at,
    this.quote,
    this.cost,
  });

  final ChatWho from;
  final DateTime? at;
  final ChatQuote? quote;
  final ChatCost? cost;
}

class ProseBlock extends ChatBlock {
  const ProseBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.blocks,
  });

  final ChatWho from;
  final List<MdBlock> blocks;
}

class CodeBlock extends ChatBlock {
  const CodeBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.code,
    this.language,
    this.lines,
  });

  final ChatWho from;
  final String? language;
  final String code;

  /// O código linha a linha em trechos coloridos; ausente, vale o texto liso.
  final List<List<CodeToken>>? lines;
}

class StepBlock extends ChatBlock {
  const StepBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.step,
    required this.expanded,
  });

  final ChatWho from;
  final ChatStep step;
  final bool expanded;
}

/// A capa de uma sequência de passos: "3 passos · echo três".
class GroupBlock extends ChatBlock {
  const GroupBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.count,
    required this.lastStep,
    required this.level,
  });

  final ChatWho from;
  final int count;
  final String lastStep;
  final GroupLevel level;
}

class DiffBlock extends ChatBlock {
  const DiffBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.file,
    required this.lines,
  });

  final ChatWho from;
  final String file;
  final List<String> lines;
}

/// A linha de status no fim da bolha ao vivo.
class StatusBlock extends ChatBlock {
  const StatusBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
    required this.live,
  });

  final ChatWho from;
  final ChatLive live;
}

/// O agente trabalha e ainda não gravou nada.
class TypingBlock extends ChatBlock {
  const TypingBlock({
    required super.id,
    required super.messageKey,
    required super.first,
    required super.last,
    required super.depth,
    required super.raw,
    required this.from,
  });

  final ChatWho from;
}
