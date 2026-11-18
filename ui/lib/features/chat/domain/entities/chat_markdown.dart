import '../../../../commons/utils/wire.dart';

/// Um trecho de texto com estilo, como o core o parte.
sealed class MdSpan {
  const MdSpan();

  factory MdSpan.fromMap(Map<String, Object?> map) => switch (map['kind']) {
    'bold' => MdBold(map['text']! as String),
    'code' => MdCode(map['text']! as String),
    'link' => MdLink(map['label']! as String, map['url']! as String),
    _ => MdText(map['text'] as String? ?? ''),
  };

  /// O que o olho lê, sem estilo.
  String get plain;
}

class MdText extends MdSpan {
  const MdText(this.text);

  final String text;

  @override
  String get plain => text;
}

class MdBold extends MdSpan {
  const MdBold(this.text);

  final String text;

  @override
  String get plain => text;
}

class MdCode extends MdSpan {
  const MdCode(this.text);

  final String text;

  @override
  String get plain => text;
}

class MdLink extends MdSpan {
  const MdLink(this.label, this.url);

  final String label;
  final String url;

  @override
  String get plain => label;
}

/// Um bloco de prosa: parágrafo, título, item de lista ou código.
sealed class MdBlock {
  const MdBlock();

  factory MdBlock.fromMap(Map<String, Object?> map) {
    List<MdSpan> spans() => mapList(map['spans'], MdSpan.fromMap);
    return switch (map['kind']) {
      'heading' => MdHeading(map['level'] as int? ?? 1, spans()),
      'bullet' => MdBullet(spans()),
      'numbered' => MdNumbered(spans()),
      'code' => MdCodeBlock(
        map['language'] as String?,
        map['text'] as String? ?? '',
      ),
      _ => MdParagraph(spans()),
    };
  }
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);

  final List<MdSpan> spans;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.spans);

  final int level;
  final List<MdSpan> spans;
}

class MdBullet extends MdBlock {
  const MdBullet(this.spans);

  final List<MdSpan> spans;
}

class MdNumbered extends MdBlock {
  const MdNumbered(this.spans);

  final List<MdSpan> spans;
}

class MdCodeBlock extends MdBlock {
  const MdCodeBlock(this.language, this.text);

  final String? language;
  final String text;
}
