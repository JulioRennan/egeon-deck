import 'package:flutter/widgets.dart';

import '../../theme/egeon_colors.dart';
import '../../theme/egeon_type.dart';
import 'eg/identity.dart';
import 'eg/pressable.dart';
import 'eg/tooltip.dart';

/// A grade das 12 identidades do DS para escolher a cor de uma bancada (6 por
/// linha); a escolhida leva o anel duplo e o título mostra o nome dela.
/// A ordem da grade do v3, que não é a da atribuição automática.
const _gridOrder = [
  Identity.sky,
  Identity.slate,
  Identity.iris,
  Identity.orchid,
  Identity.mauve,
  Identity.rose,
  Identity.clay,
  Identity.sand,
  Identity.olive,
  Identity.moss,
  Identity.jade,
  Identity.teal,
];

String identityLabel(Identity identity) =>
    '${identity.name[0].toUpperCase()}${identity.name.substring(1)}';

class BenchColorGrid extends StatelessWidget {
  const BenchColorGrid({
    required this.benchName,
    required this.current,
    required this.onPick,
    this.showTitle = true,
    super.key,
  });

  final String benchName;
  final Identity current;
  final ValueChanged<Identity> onPick;

  /// "Cor da bancada" em cima, à esquerda; a janela já tem esse título, e aí
  /// só o nome da bancada fica.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final shown = current.color(c);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (showTitle)
              Text(
                'Cor da bancada',
                style: EgeonType.label.copyWith(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                benchName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: showTitle ? TextAlign.end : TextAlign.start,
                style: EgeonType.caption.copyWith(
                  color: shown,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var row = 0; row < _gridOrder.length; row += 6) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var i = row; i < row + 6; i++) ...[
                if (i > row) const SizedBox(width: 8),
                Expanded(
                  child: _Swatch(
                    identity: _gridOrder[i],
                    checked: _gridOrder[i] == current,
                    onPressed: () => onPick(_gridOrder[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.identity,
    required this.checked,
    required this.onPressed,
  });

  final Identity identity;
  final bool checked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Semantics(
      checked: checked,
      inMutuallyExclusiveGroup: true,
      label: identityLabel(identity),
      child: Tooltip(
        message: identityLabel(identity),
        child: Pressable(
          onPressed: onPressed,
          builder: (context, s) => DecoratedBox(
            decoration: BoxDecoration(
              color: identity.color(c),
              borderRadius: BorderRadius.circular(6),
              boxShadow: checked
                  // Anel duplo fino: de baixo para cima, o fio claro (até 4) e o
                  // fundo (até 2) por cima dele — sobra 2px de folga e 2px de
                  // fio.
                  ? [
                      BoxShadow(color: c.textPrimary, spreadRadius: 4),
                      BoxShadow(color: c.carbon, spreadRadius: 2),
                    ]
                  : null,
            ),
            child: const SizedBox(height: 28),
          ),
        ),
      ),
    );
  }
}
