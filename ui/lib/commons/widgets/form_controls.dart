import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import 'context_menu.dart';

TextStyle _label(double opacity) => TextStyle(
  fontSize: 12,
  color: AppColors.white(opacity),
  decoration: TextDecoration.none,
);

/// Abas lado a lado, uma marcada: o "Shell × Agente" e o "Criar do zero ×
/// Começar de outro".
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.keyPrefix = 'segment',
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// As abas se chamam `<prefixo>-<n>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.black(0.22),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppColors.white(0.08)),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('$keyPrefix-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.white(0.14) : null,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    labels[i],
                    style: _label(i == selected ? 0.95 : 0.6),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Uma opção de um grupo: só uma marcada por vez.
class FormRadio extends StatelessWidget {
  const FormRadio({
    required this.label,
    required this.selected,
    required this.onTap,
    this.monospace = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool monospace;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 20,
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.white(0.4),
                ),
              ),
              child: selected
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _label(0.85).copyWith(
                  fontFamily: monospace ? 'Menlo' : null,
                  fontSize: monospace ? 11 : 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Uma caixa de marcar com o texto ao lado.
class FormCheckbox extends StatelessWidget {
  const FormCheckbox({
    required this.label,
    required this.on,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!on),
      child: SizedBox(
        height: 20,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.accent : null,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: on ? AppColors.accent : AppColors.white(0.4),
                ),
              ),
              child: on
                  ? const Text(
                      '✓',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFFFF),
                        decoration: TextDecoration.none,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 7),
            Flexible(child: Text(label, style: _label(0.85))),
          ],
        ),
      ),
    ),
  );
}

/// Um popup: mostra o item escolhido e, no clique, a lista para trocar.
class PopupField extends StatelessWidget {
  const PopupField({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Builder(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          showContextMenu(
            context,
            position: box.localToGlobal(Offset(0, box.size.height + 2)),
            entries: [
              for (var i = 0; i < items.length; i++)
                MenuEntry(items[i], () => onSelect(i)),
            ],
          );
        },
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.black(0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.white(0.14)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  items.isEmpty
                      ? ''
                      : items[selected.clamp(0, items.length - 1)],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(0.85),
                ),
              ),
              Text('⌄', style: _label(0.5)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// O "escolher outro" de um campo: um + ao lado do título, igual em todos.
class PlusButton extends StatelessWidget {
  const PlusButton({required this.tooltip, required this.onTap, super.key});

  /// O que o + escolhe ("Outra pasta").
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
          child: const Text(
            '+',
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
