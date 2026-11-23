import 'package:flutter/widgets.dart';

import '../../../theme/egeon_tokens.dart';
import 'checkbox.dart';
import 'pressable.dart';

/// Botão de opção: escolhe-se uma; quem agrupa guarda qual (o [onSelected] de
/// cada uma diz que foi ela).
class Radio extends StatelessWidget {
  const Radio({
    required this.checked,
    required this.onSelected,
    this.label,
    this.autofocus = false,
    super.key,
  });

  final bool checked;

  /// Nulo desabilita (40%).
  final VoidCallback? onSelected;
  final Widget? label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onSelected != null;
    return Semantics(
      checked: checked,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onPressed: enabled ? onSelected : null,
        autofocus: autofocus,
        builder: (context, s) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Marcado: anel `accent` de 5px em volta de `carbon` (no ControlBox).
            ControlBox(on: checked, state: s, shape: BoxShape.circle),
            if (label != null) ...[
              const SizedBox(width: EgeonSpace.s2),
              Flexible(child: ControlLabel(label!, enabled: enabled)),
            ],
          ],
        ),
      ),
    );
  }
}
