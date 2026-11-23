import 'package:flutter/widgets.dart';

import '../../../../commons/utils/agent_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/identity.dart';
import '../../../../commons/widgets/eg/layer.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../../../commons/widgets/bench_color_grid.dart';
import '../../domain/entities/canvas_component.dart';

/// V3 — o menu do botão de terminal de agente: "Componentes salvos" (nome e a
/// linha "CLI · modelo · esforço") e "Configurar novo terminal…".
Layer showComponentsMenu(
  BuildContext context, {
  required Rect anchor,
  required List<CanvasComponent> components,
  required ValueChanged<String?> onPick,
  required VoidCallback? onConfigure,
  VoidCallback? onClosed,
}) => showPopover(
  context,
  anchor: anchor,
  onClosed: onClosed,
  width: 280,
  padding: const EdgeInsets.all(6),
  builder: (context, close) {
    final c = context.eg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (components.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
              'Componentes salvos',
              style: EgeonType.caption.copyWith(
                color: c.textMuted,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          for (final component in components)
            _ComponentRow(
              component,
              onPressed: () {
                close();
                onPick(component.name);
              },
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: EgeonColors.overlay6),
            ),
          ),
        ],
        _RowButton(
          icon: EgIcons.plus,
          label: 'Configurar novo terminal…',
          onPressed: onConfigure == null
              ? null
              : () {
                  close();
                  onConfigure();
                },
        ),
      ],
    );
  },
);

class _ComponentRow extends StatelessWidget {
  const _ComponentRow(this.component, {required this.onPressed});

  final CanvasComponent component;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Pressable(
        onPressed: onPressed,
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: s.hovered ? c.steelActive : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  component.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EgeonType.label.copyWith(
                    // A v3 pinta o nome na cor do componente; o core ainda
                    // não guarda cor por componente, então vale a do agente.
                    color: agentIdentity(component.name).color(c),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (component.meta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    component.meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.monoMeta.copyWith(
                      color: c.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final EgIconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      onPressed: onPressed,
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.hovered ? c.steelActive : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                EgIcon(icon, color: c.textSecondary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.label.copyWith(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
}

/// V4 — o menu Template ▾: salvar como template e atualizar o de origem. Sem
/// origem, "Atualizar" fica desabilitado (não há o que atualizar).
Layer showTemplateMenu(
  BuildContext context, {
  required Rect anchor,
  required VoidCallback onSave,
  String? origin,
  VoidCallback? onUpdate,
  VoidCallback? onClosed,
}) => showMenu(
  context,
  anchor: anchor,
  onClosed: onClosed,
  width: 300,
  items: [
    MenuItem('Salvar como template…', onSelected: onSave),
    MenuItem(
      origin == null ? 'Atualizar o template de origem' : 'Atualizar “$origin”',
      onSelected: origin == null ? null : onUpdate,
    ),
  ],
);

/// V5 — a cor da bancada: título, o nome da cor atual e a grade das 12
/// identidades (6 por linha); a escolhida leva o anel duplo.
Layer showBenchColorMenu(
  BuildContext context, {
  required Rect anchor,
  required String benchName,
  required Identity current,
  required ValueChanged<Identity> onPick,
  VoidCallback? onClosed,
}) => showPopover(
  context,
  anchor: anchor,
  onClosed: onClosed,
  width: 236,
  padding: const EdgeInsets.all(14),
  builder: (context, close) => BenchColorGrid(
    benchName: benchName,
    current: current,
    onPick: (identity) {
      close();
      onPick(identity);
    },
  ),
);

/// O quadradinho da cor no botão da barra: 16, raio 5, fio claro por dentro.
class BenchColorChip extends StatelessWidget {
  const BenchColorChip(this.identity, {super.key});

  final Identity identity;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: identity.color(context.eg),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: EgeonColors.overlay12),
    ),
    child: const SizedBox(width: 16, height: 16),
  );
}
