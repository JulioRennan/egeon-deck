import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';

enum DiffSign { added, removed }

/// Uma célula do diff: número da linha, o sinal (nulo é contexto) e o texto.
/// No texto, `[+palavra]` e `[-palavra]` realçam a palavra mudada.
class DiffCell {
  const DiffCell(this.n, this.text, {this.sign});

  final int n;
  final String text;
  final DiffSign? sign;
}

/// Uma linha do diff: esquerda (antes) e direita (depois), ou uma dobra
/// (`fold`: "⋯ 12 linhas sem mudança").
class DiffRow {
  const DiffRow({this.left, this.right}) : fold = null;

  const DiffRow.fold(String this.fold) : left = null, right = null;

  final DiffCell? left;
  final DiffCell? right;
  final String? fold;
}

enum DiffMode { sideBySide, unified }

final _marks = RegExp(r'(\[\+[^\]]*\]|\[-[^\]]*\])');

/// O texto de uma célula, com as palavras `[+x]`/`[-x]` realçadas.
List<InlineSpan> diffSpans(String text, EgeonColors c) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _marks.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    final token = m.group(0)!;
    final added = token.startsWith('[+');
    spans.add(
      TextSpan(
        text: token.substring(2, token.length - 1),
        style: TextStyle(
          backgroundColor: added ? c.diffAddWord : c.diffDelWord,
        ),
      ),
    );
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Diff de um arquivo (DS `.eg-diff`): `carbon`, raio 12, mono 13/20; cabeçalho
/// de 34 em `obsidian` (arquivo, `+n`, `−n`); duas colunas separadas por fio
/// `lineSubtle`, ou uma só no unificado. Linha adicionada/removida leva o fundo
/// `diff-*` e número e sinal na cor do sinal; o vazio é hachurado; a dobra é
/// uma faixa `obsidian` em sans 12.
class DiffView extends StatelessWidget {
  const DiffView({
    required this.filename,
    required this.rows,
    this.added = 0,
    this.removed = 0,
    this.mode = DiffMode.sideBySide,
    super.key,
  });

  final String filename;
  final List<DiffRow> rows;
  final int added;
  final int removed;
  final DiffMode mode;

  /// Linhas do modo unificado: remoção, depois adição; contexto uma vez só.
  static List<DiffRow> unify(List<DiffRow> rows) {
    final out = <DiffRow>[];
    for (final r in rows) {
      if (r.fold != null) {
        out.add(r);
        continue;
      }
      final l = r.left, rt = r.right;
      if (l != null && l.sign != null) out.add(DiffRow(left: l));
      if (rt != null && rt.sign != null) {
        out.add(DiffRow(right: rt));
      } else if (rt != null && (l == null || l.sign == null)) {
        out.add(DiffRow(right: rt));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final code = EgeonType.code.copyWith(
      height: 20 / 13,
      color: c.synText,
      decoration: TextDecoration.none,
    );
    Widget cell(DiffCell? cell) {
      if (cell == null) {
        return SizedBox(
          height: 20,
          child: CustomPaint(painter: _Hatch(c.lineSubtle)),
        );
      }
      final sign = cell.sign;
      final signColor = switch (sign) {
        DiffSign.added => c.diffAddFg,
        DiffSign.removed => c.diffDelFg,
        null => c.textDisabled,
      };
      return ColoredBox(
        color: switch (sign) {
          DiffSign.added => c.diffAddBg,
          DiffSign.removed => c.diffDelBg,
          null => EgeonColors.clear,
        },
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${cell.n}',
                  textAlign: TextAlign.right,
                  style: code.copyWith(color: signColor),
                ),
              ),
            ),
            SizedBox(
              width: 16,
              child: Text(switch (sign) {
                DiffSign.added => '+',
                DiffSign.removed => '−',
                null => ' ',
              }, style: code.copyWith(color: signColor)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: EgeonSpace.s3),
                child: Text.rich(
                  TextSpan(children: diffSpans(cell.text, c)),
                  style: code,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget fold(String text) => ColoredBox(
      color: c.obsidian,
      child: SizedBox(
        height: 20,
        child: Padding(
          padding: const EdgeInsets.only(left: 40 + 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: EgeonType.caption.copyWith(
                fontWeight: FontWeight.w400,
                color: c.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );

    Widget column(List<DiffRow> list, DiffCell? Function(DiffRow) pick) =>
        Column(
          children: [
            for (final r in list)
              r.fold != null ? fold(r.fold!) : cell(pick(r)),
          ],
        );

    final Widget body = mode == DiffMode.unified
        ? column(unify(rows), (r) => r.left ?? r.right)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: column(rows, (r) => r.left)),
              SizedBox(width: 1, child: ColoredBox(color: c.lineSubtle)),
              Expanded(child: column(rows, (r) => r.right)),
            ],
          );
    TextStyle head(Color color) => EgeonType.monoMeta.copyWith(
      fontWeight: FontWeight.w400,
      color: color,
      decoration: TextDecoration.none,
    );
    return DecoratedBox(
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
            ColoredBox(
              color: c.obsidian,
              child: SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EgeonSpace.s3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(filename, style: head(c.textSecondary)),
                      ),
                      Text('+$added', style: head(c.diffAddFg)),
                      const SizedBox(width: EgeonSpace.s3),
                      Text('−$removed', style: head(c.diffDelFg)),
                    ],
                  ),
                ),
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

/// O vazio do diff: hachura diagonal de 1px a cada 5.
class _Hatch extends CustomPainter {
  _Hatch(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Hatch old) => old.color != color;
}
