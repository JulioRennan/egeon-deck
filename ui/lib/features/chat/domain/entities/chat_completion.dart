import '../../../../commons/utils/wire.dart';

/// Uma sugestão do menu do composer.
class CompletionItem {
  const CompletionItem({
    required this.label,
    required this.insert,
    required this.kind,
    this.detail,
  });

  final String label;

  /// O texto que entra no lugar do trecho digitado.
  final String insert;

  /// `mention` (@agente) ou `slash` (/comando).
  final String kind;
  final String? detail;

  bool get isSlash => kind == 'slash';

  factory CompletionItem.fromMap(Map<String, Object?> map) => CompletionItem(
    label: map['label']! as String,
    insert: map['insert']! as String,
    kind: map['kind'] as String? ?? 'mention',
    detail: map['detail'] as String?,
  );
}

/// A resposta do core ao texto e à posição do cursor: as sugestões e o trecho
/// (em unidades UTF-16, como o `String` do Dart) que o `insert` substitui.
class ChatCompletion {
  const ChatCompletion({this.items = const [], this.start = 0, this.end = 0});

  /// Sem gatilho antes do cursor.
  const ChatCompletion.none(int caret) : this(start: caret, end: caret);

  final List<CompletionItem> items;
  final int start;
  final int end;

  bool get isEmpty => items.isEmpty;

  factory ChatCompletion.fromMap(Map<String, Object?> map) {
    final range = (map['range'] as List<Object?>? ?? const [0, 0]).cast<int>();
    return ChatCompletion(
      items: mapList(map['items'], CompletionItem.fromMap),
      start: range[0],
      end: range[1],
    );
  }

  /// O [text] com a sugestão [item] no lugar do trecho, e onde fica o cursor.
  ({String text, int caret}) apply(String text, CompletionItem item) {
    final from = start.clamp(0, text.length);
    final to = end.clamp(from, text.length);
    return (
      text: text.replaceRange(from, to, item.insert),
      caret: from + item.insert.length,
    );
  }
}
