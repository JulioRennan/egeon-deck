import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';

enum SidebarTab { all, active }

/// O seletor de duas abas — Todas e Ativas —, cada uma com a sua contagem.
class SidebarSegments extends StatelessWidget {
  const SidebarSegments({
    required this.selected,
    required this.allCount,
    required this.activeCount,
    required this.onSelect,
    super.key,
  });

  final SidebarTab selected;
  final int allCount;
  final int activeCount;
  final ValueChanged<SidebarTab> onSelect;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AppColors.black(0.22),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.white(0.07)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Segment(
            title: 'Todas',
            count: allCount,
            live: false,
            selected: selected == SidebarTab.all,
            onTap: () => onSelect(SidebarTab.all),
          ),
        ),
        Expanded(
          child: _Segment(
            title: 'Ativas',
            count: activeCount,
            live: true,
            selected: selected == SidebarTab.active,
            onTap: () => onSelect(SidebarTab.active),
          ),
        ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.title,
    required this.count,
    required this.live,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool live;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = live ? AppColors.done : const Color(0xFFFFFFFF);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.white(0.13) : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.white(selected ? 0.95 : 0.5),
                  decoration: TextDecoration.none,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 14,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: selected ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tint.withValues(alpha: selected ? 0.95 : 0.55),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
