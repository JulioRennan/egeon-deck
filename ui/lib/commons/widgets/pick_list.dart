import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// Uma lista curta de textos em caixa com rolagem, de linhas selecionáveis. Um
/// toque marca ou desmarca a linha; o duplo toque avisa por [onOpen].
class PickList extends StatelessWidget {
  const PickList({
    required this.items,
    required this.selected,
    required this.onToggle,
    this.onOpen,
    this.height = 100,
    this.emptyText,
    this.keyPrefix = 'pick',
    super.key,
  });

  final List<String> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<int>? onOpen;
  final double height;
  final String? emptyText;

  /// As linhas se chamam `<prefixo>-<n>`: duas listas na mesma janela não se
  /// confundem.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: AppColors.black(0.25),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.white(0.14)),
    ),
    child: items.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              emptyText ?? '',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.white(0.35),
                decoration: TextDecoration.none,
              ),
            ),
          )
        : ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('$keyPrefix-$index'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onToggle(index),
                onDoubleTap: onOpen == null ? null : () => onOpen!(index),
                child: Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  color: selected.contains(index)
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : null,
                  child: Text(
                    items[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFFFFFF),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
