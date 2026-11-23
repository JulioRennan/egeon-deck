import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'icon_button.dart';

final _keywords = RegExp(
  r'^(const|let|var|function|return|if|else|for|while|import|from|export|default|class|new|await|async|try|catch|throw|type|interface|extends|implements|final|void|static|this|super|of|in)$',
);

final _token = RegExp(
  r'''(//.*$)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`[^`]*`)|(\b\d+(?:\.\d+)?\b|\btrue\b|\bfalse\b|\bnull\b)|([A-Za-z_$][\w$]*)(?=\s*\()|([A-Z][\w$]*)|([A-Za-z_$][\w$]*)|([{}()\[\];,.:=<>+\-*/!?&|]+)|(\s+)''',
);

/// Realça uma linha de código com as cores `syn-*` (o realçador do DS: não
/// entende a linguagem, só comentários, textos, números, palavras-chave,
/// funções e tipos). Comentário em itálico.
List<TextSpan> highlightLine(String line, EgeonColors c) {
  final spans = <TextSpan>[];
  for (final m in _token.allMatches(line)) {
    final text = m.group(0)!;
    TextStyle? style;
    if (m.group(1) != null) {
      style = TextStyle(color: c.synComment, fontStyle: FontStyle.italic);
    } else if (m.group(2) != null) {
      style = TextStyle(color: c.synString);
    } else if (m.group(3) != null) {
      style = TextStyle(color: c.synNumber);
    } else if (m.group(4) != null) {
      style = TextStyle(
        color: _keywords.hasMatch(text) ? c.synKeyword : c.synFunction,
      );
    } else if (m.group(5) != null) {
      style = TextStyle(color: c.synType);
    } else if (m.group(6) != null) {
      style = _keywords.hasMatch(text) ? TextStyle(color: c.synKeyword) : null;
    } else if (m.group(7) != null) {
      style = TextStyle(color: c.synPunct);
    }
    spans.add(TextSpan(text: text, style: style));
  }
  return spans;
}

/// Bloco de código (DS `.eg-code`): `carbon`, raio 12; cabeçalho de 34 em
/// `obsidian` com o arquivo (mono, `textSecondary`), a linguagem e "Copiar" (que
/// só aparece com o cursor no bloco); linhas mono 13/20 com números de 44 em
/// `textDisabled` e sintaxe `syn-*`.
class CodeBlock extends StatefulWidget {
  const CodeBlock(
    this.code, {
    this.filename,
    this.lang,
    this.start = 1,
    this.lineNumbers = true,
    super.key,
  });

  final String code;
  final String? filename;
  final String? lang;
  final int start;
  final bool lineNumbers;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final lines = widget.code.replaceAll(RegExp(r'\n$'), '').split('\n');
    final style = EgeonType.code.copyWith(
      height: 20 / 13,
      color: c.synText,
      decoration: TextDecoration.none,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.carbon,
          borderRadius: BorderRadius.circular(EgeonRadius.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(EgeonRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.filename != null || widget.lang != null)
                ColoredBox(
                  color: c.obsidian,
                  child: SizedBox(
                    height: 34,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: EgeonSpace.s3,
                        right: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.filename ?? '',
                              style: EgeonType.monoMeta.copyWith(
                                fontWeight: FontWeight.w400,
                                color: c.textSecondary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (widget.lang != null)
                            Text(
                              widget.lang!,
                              style: EgeonType.caption.copyWith(
                                fontWeight: FontWeight.w400,
                                color: c.textMuted,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          const SizedBox(width: EgeonSpace.s2),
                          Opacity(
                            opacity: _hovered ? 1 : 0,
                            child: IconButton(
                              icon: EgIcons.copy,
                              tooltip: 'Copiar',
                              compact: true,
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: widget.code),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: EgeonSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: EgeonSpace.s4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.lineNumbers)
                              SizedBox(
                                width: 44,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: EgeonSpace.s3,
                                  ),
                                  child: Text(
                                    '${widget.start + i}',
                                    textAlign: TextAlign.right,
                                    style: style.copyWith(
                                      color: c.textDisabled,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: EgeonSpace.s4),
                            Text.rich(
                              TextSpan(children: highlightLine(lines[i], c)),
                              style: style,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
