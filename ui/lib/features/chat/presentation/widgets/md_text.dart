import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_markdown.dart';
import 'chat_palette.dart';

/// O texto da resposta: sans 14/22 em `textPrimary`.
TextStyle mdBase(EgeonColors c) => EgeonType.body.copyWith(
  fontSize: 14,
  height: 22 / 14,
  color: c.textPrimary,
  decoration: TextDecoration.none,
);

/// Os trechos de um bloco de prosa como texto com estilo. O link mostra o
/// rótulo e leva a URL no clique, que quem usa decide ([onLink]). O código
/// inline (`.ic`) é mono em `steel`.
List<InlineSpan> mdSpans(
  List<MdSpan> spans, {
  required TextStyle base,
  required EgeonColors colors,
  ValueChanged<String>? onLink,
  Set<String> mentions = const {},
}) => [
  for (final span in spans)
    switch (span) {
      MdText(:final text) when mentions.isNotEmpty => TextSpan(
        children: _mentioned(text, base, colors, mentions),
      ),
      MdText(:final text) => TextSpan(text: text, style: base),
      MdBold(:final text) => TextSpan(
        text: text,
        style: base.copyWith(fontWeight: FontWeight.w600),
      ),
      MdCode(:final text) => TextSpan(
        text: text,
        style: base.copyWith(
          fontFamily: EgeonType.mono,
          fontFamilyFallback: EgeonType.monoFallback,
          fontSize: 13,
          backgroundColor: colors.steel,
        ),
      ),
      MdLink(:final label, :final url) => TextSpan(
        text: label,
        style: base.copyWith(
          color: colors.accent,
          decoration: TextDecoration.underline,
          decorationColor: colors.accent,
        ),
        recognizer: onLink == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onLink(url)),
        mouseCursor: SystemMouseCursors.click,
      ),
    },
];

/// O texto com os nomes dos agentes da conversa na cor de cada um (a v3 pinta
/// "revisor" e "testes" no meio da frase). Só a palavra inteira conta.
List<InlineSpan> _mentioned(
  String text,
  TextStyle base,
  EgeonColors colors,
  Set<String> ids,
) {
  final names = ids.toList()..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?<![\\w-])(${names.map(RegExp.escape).join('|')})(?![\\w-])',
  );
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > at) {
      out.add(TextSpan(text: text.substring(at, m.start), style: base));
    }
    out.add(
      TextSpan(
        text: m.group(0),
        style: base.copyWith(
          color: ChatPalette.ofId(colors, m.group(1)!),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    at = m.end;
  }
  if (at < text.length) {
    out.add(TextSpan(text: text.substring(at), style: base));
  }
  return out;
}

/// A prosa de uma resposta: parágrafos, títulos, listas e blocos de código.
class MdColumn extends StatelessWidget {
  const MdColumn({
    required this.blocks,
    this.onLink,
    this.mentions = const {},
    super.key,
  });

  final List<MdBlock> blocks;
  final ValueChanged<String>? onLink;

  /// Os ids dos agentes da conversa: ficam na cor de cada um no texto.
  final Set<String> mentions;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final base = mdBase(c);
    Widget text(List<MdSpan> spans, {TextStyle? style}) => Text.rich(
      TextSpan(
        children: mdSpans(
          spans,
          base: style ?? base,
          colors: c,
          onLink: onLink,
          mentions: mentions,
        ),
      ),
    );
    Widget item(String marker, List<MdSpan> spans) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: Text(marker, style: base),
        ),
        Expanded(child: text(spans)),
      ],
    );
    Widget block(MdBlock b) => switch (b) {
      MdParagraph(:final spans) => text(spans),
      MdHeading(:final level, :final spans) => text(
        spans,
        style: base.copyWith(
          fontSize: level == 1 ? 18 : (level == 2 ? 16 : 15),
          fontWeight: FontWeight.w600,
        ),
      ),
      MdBullet(:final spans) => item('•', spans),
      MdNumbered(:final spans) => text(spans),
      MdCodeBlock(:final text) => CodeBox(code: text),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, b) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: block(b),
          ),
      ],
    );
  }
}

/// A cor de cada tipo de trecho de código (`syn-*` do DS): o core classifica, e
/// aqui só se pinta pelo `kind`.
Color syntaxColor(EgeonColors c, String kind) => switch (kind) {
  'keyword' => c.synKeyword,
  'type' => c.synType,
  'string' => c.synString,
  'comment' => c.synComment,
  'number' => c.synNumber,
  'tag' => c.synTag,
  'attribute' => c.synConstant,
  _ => c.synText,
};

/// Código na sua caixa (`obsidian`, fio de 6%, raio 12, mono 13/20). A seleção
/// é da thread inteira (`SelectableRegion`), não de cada texto. Uma caixa que
/// abre com "$ " é uma sessão de comando e se pinta como a v3: o `$` em
/// `accent`, o andamento em `textMuted`, o que passou em `success` e o que
/// falhou em `danger`.
class CodeBox extends StatelessWidget {
  const CodeBox({required this.code, this.lines, super.key});

  final String code;

  /// O código em trechos coloridos pelo core, uma lista por linha.
  final List<List<CodeToken>>? lines;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.obsidian,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.lineSubtle),
      ),
      child: Text.rich(
        TextSpan(
          children: lines == null
              ? (isShellSession(code)
                    ? shellSession(code, c)
                    : [TextSpan(text: code)])
              : [
                  for (final (i, line) in lines!.indexed) ...[
                    for (final token in line)
                      TextSpan(
                        text: token.text,
                        style: TextStyle(color: syntaxColor(c, token.kind)),
                      ),
                    if (i < lines!.length - 1) const TextSpan(text: '\n'),
                  ],
                ],
        ),
        style: EgeonType.code.copyWith(
          height: 20 / 13,
          color: c.termFg,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// A caixa abre com "$ ": o que o agente rodou e o que o terminal respondeu.
bool isShellSession(String code) => code.startsWith(r'$ ');

final _passed = RegExp(
  r'(all tests passed|passed!|\bok\b|\bpassed\b|success|done|✓)',
  caseSensitive: false,
);
final _failed = RegExp(
  r'(failed|\berror\b|exception|✗|\[E\])',
  caseSensitive: false,
);

/// Uma sessão de comando em trechos: o prompt, o andamento esmaecido, o
/// resultado verde ou vermelho. É só pintura sobre o texto que veio: nada é
/// dito além do que a saída escreveu.
List<InlineSpan> shellSession(String code, EgeonColors c) {
  final lines = code.replaceAll(RegExp(r'\n$'), '').split('\n');
  return [
    for (final (i, line) in lines.indexed) ...[
      if (line.startsWith(r'$ ')) ...[
        TextSpan(
          text: r'$',
          style: TextStyle(color: c.accent),
        ),
        TextSpan(text: line.substring(1)),
      ] else
        TextSpan(
          text: line,
          style: TextStyle(
            color: _failed.hasMatch(line)
                ? c.danger
                : _passed.hasMatch(line)
                ? c.success
                : c.textMuted,
          ),
        ),
      if (i < lines.length - 1) const TextSpan(text: '\n'),
    ],
  ];
}
