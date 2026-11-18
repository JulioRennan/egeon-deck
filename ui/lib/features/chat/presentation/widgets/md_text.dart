import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/code_palette.dart';
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_markdown.dart';
import 'chat_palette.dart';

/// Os trechos de um bloco de prosa como texto com estilo. O link mostra o
/// rótulo e leva a URL no clique, que quem usa decide ([onLink]).
List<InlineSpan> mdSpans(
  List<MdSpan> spans, {
  required TextStyle base,
  ValueChanged<String>? onLink,
}) => [
  for (final span in spans)
    switch (span) {
      MdText(:final text) => TextSpan(text: text, style: base),
      MdBold(:final text) => TextSpan(
        text: text,
        style: base.copyWith(fontWeight: FontWeight.w700),
      ),
      MdCode(:final text) => TextSpan(
        text: text,
        style: base.copyWith(
          fontFamily: 'Menlo',
          fontSize: (base.fontSize ?? 13) - 1,
          backgroundColor: AppColors.white(0.08),
        ),
      ),
      MdLink(:final label, :final url) => TextSpan(
        text: label,
        style: base.copyWith(
          color: ChatPalette.link,
          decoration: TextDecoration.underline,
        ),
        recognizer: onLink == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onLink(url)),
        mouseCursor: SystemMouseCursors.click,
      ),
    },
];

/// A prosa de uma resposta: parágrafos, títulos, listas e blocos de código.
class MdColumn extends StatelessWidget {
  const MdColumn({required this.blocks, this.onLink, super.key});

  final List<MdBlock> blocks;
  final ValueChanged<String>? onLink;

  static const _base = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: Color(0xFFE6E6E6),
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, block) in blocks.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
          child: _block(block),
        ),
    ],
  );

  Widget _block(MdBlock block) => switch (block) {
    MdParagraph(:final spans) => _text(spans),
    MdHeading(:final level, :final spans) => _text(
      spans,
      style: _base.copyWith(
        fontSize: level == 1 ? 17 : (level == 2 ? 15.5 : 14),
        fontWeight: FontWeight.w700,
      ),
    ),
    MdBullet(:final spans) => _item('•', spans),
    MdNumbered(:final spans) => _text(spans),
    MdCodeBlock(:final text) => CodeBox(code: text),
  };

  Widget _text(List<MdSpan> spans, {TextStyle? style}) => Text.rich(
    TextSpan(
      children: mdSpans(spans, base: style ?? _base, onLink: onLink),
    ),
  );

  Widget _item(String marker, List<MdSpan> spans) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Text(marker, style: _base),
      ),
      Expanded(child: _text(spans)),
    ],
  );
}

/// Código na sua caixa, em monoespaçado. A seleção é da thread inteira
/// (`SelectableRegion`), não de cada texto.
class CodeBox extends StatelessWidget {
  const CodeBox({required this.code, this.lines, super.key});

  final String code;

  /// O código em trechos coloridos pelo core, uma lista por linha.
  final List<List<CodeToken>>? lines;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.black(0.25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: ChatPalette.boxBorder),
    ),
    child: Text.rich(
      TextSpan(
        children: lines == null
            ? [TextSpan(text: code)]
            : [
                for (final (i, line) in lines!.indexed) ...[
                  for (final token in line)
                    TextSpan(
                      text: token.text,
                      style: TextStyle(color: CodePalette.of(token.kind)),
                    ),
                  if (i < lines!.length - 1) const TextSpan(text: '\n'),
                ],
              ],
      ),
      style: const TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        height: 1.4,
        color: Color(0xFFE6E6E6),
        decoration: TextDecoration.none,
      ),
    ),
  );
}
