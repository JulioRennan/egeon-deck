import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';

/// O atalho de teclado (`⌘3`, `⇧Enter`) como o DS desenha: mono 11/16 em
/// `textMuted`, respiro de 4, raio xs e um fio de 1px em `line`; sem fundo.
class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EgeonRadius.xs),
        border: Border.all(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: EgeonType.monoMeta.copyWith(
            fontSize: 11,
            height: 16 / 11,
            fontWeight: FontWeight.w400,
            color: c.textMuted,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
