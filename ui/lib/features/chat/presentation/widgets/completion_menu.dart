import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/chat_completion.dart';

/// O menu de @menção e /slash acima da caixa de mensagem. A linha escolhida
/// (setas) vai com Enter ou Tab; o clique também escolhe.
class CompletionMenu extends StatelessWidget {
  const CompletionMenu({
    required this.items,
    required this.selected,
    required this.onPick,
    super.key,
  });

  final List<CompletionItem> items;
  final int selected;
  final ValueChanged<CompletionItem> onPick;

  static const rowHeight = 30.0;
  static const maxRows = 7;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('completion-menu'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xF7141926),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.white(0.12)),
    ),
    constraints: const BoxConstraints(maxHeight: rowHeight * maxRows + 8),
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final (i, item) in items.indexed)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('completion-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(item),
              child: Container(
                height: rowHeight,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: i == selected
                      ? AppColors.accent.withValues(alpha: 0.35)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      item.isSlash ? '/${item.label}' : '@${item.label}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (item.detail != null)
                      Expanded(
                        child: Text(
                          item.detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.white(0.5),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
