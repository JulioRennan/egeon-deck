import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/glyphs.dart';
import '../../../../theme/app_colors.dart';

/// A gaveta dos guardados: aparece sempre, mesmo vazia, porque é o alvo para
/// onde se arrasta o primeiro projeto.
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    required this.count,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final int count;
  final bool open;
  final VoidCallback onToggle;

  static const height = 26.0;

  String get _label => switch (count) {
    0 => 'gaveta vazia',
    1 => '1 guardado',
    _ => '$count guardados',
  };

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Vazia não abre nada: fica ali como alvo de queda.
    cursor: count > 0 ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: count > 0 ? onToggle : null,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(left: count == 0 ? 12 : 10, right: 10),
          child: Row(
            children: [
              if (count > 0) ...[
                ChevronGlyph(
                  open ? ChevronDirection.down : ChevronDirection.right,
                  color: AppColors.white(0.3),
                  size: 10,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white(0.38),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
