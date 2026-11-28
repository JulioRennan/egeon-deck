import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import 'eg_icon.dart';
import 'motion.dart';
import 'pressable.dart';
import 'tooltip.dart';
import '../../utils/app_shortcut.dart';

enum ViewSwitchMode { canvas, chat }

/// O ícone de Canvas da barra de topo (o do header da v3): dois cartões e a
/// ligação entre eles. Não é o `EgIcons.canvas` (a grade de quatro).
const _canvasIcon = EgIconData('view-canvas', [
  EgRect(1.75, 2.75, 5.5, 4.5, 1),
  EgRect(8.75, 8.75, 5.5, 4.5, 1),
  EgPath('M7.25 5h1.5a2 2 0 0 1 2 2v1.75'),
]);

/// A troca Canvas | Chat da barra de topo, só ícones (o `role="group"` da v3):
/// botões de 32, raio 8, num grupo de respiro 2, vão 2, raio 10 sobre
/// `overlay2`. Repouso `textSecondary` (como voltar e avançar); hover
/// `overlay6` e `textPrimary`; ligado `overlay8` e `textPrimary`. O nome e o
/// atalho (⌥⌘1 / ⌥⌘2) vão na dica.
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({required this.value, required this.onChanged, super.key});

  final ViewSwitchMode value;

  /// Nulo desabilita.
  final ValueChanged<ViewSwitchMode>? onChanged;

  static final _options = [
    (
      ViewSwitchMode.canvas,
      'Canvas',
      appShortcutLabel('1', alt: true, macOnly: true),
      _canvasIcon,
    ),
    (
      ViewSwitchMode.chat,
      'Chat',
      appShortcutLabel('2', alt: true, macOnly: true),
      EgIcons.message,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = onChanged != null;
    return Semantics(
      container: true,
      label: 'Visualização',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EgeonColors.overlay2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, (mode, name, shortcut, icon))
                  in _options.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Tooltip(
                  message: name,
                  shortcut: shortcut,
                  child: Semantics(
                    selected: mode == value,
                    child: Pressable(
                      onPressed: enabled ? () => onChanged!(mode) : null,
                      semanticLabel: name,
                      builder: (context, s) {
                        final selected = mode == value;
                        final foreground = !enabled
                            ? c.textDisabled
                            : selected || s.hovered || s.pressed
                            ? c.textPrimary
                            : c.textSecondary;
                        final background = selected
                            ? EgeonColors.overlay8
                            : enabled && (s.hovered || s.pressed)
                            ? EgeonColors.overlay6
                            : EgeonColors.clear;
                        return AnimatedContainer(
                          key: ValueKey('view-${mode.name}'),
                          duration: egDuration(context, EgeonMotion.fast),
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(EgeonRadius.md),
                            border: Border.all(
                              color: s.focused ? c.accent : EgeonColors.clear,
                              width: EgeonBorder.focus,
                            ),
                          ),
                          child: EgIcon(icon, color: foreground),
                        );
                      },
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
