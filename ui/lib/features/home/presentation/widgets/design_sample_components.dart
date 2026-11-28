import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/button.dart';
import '../../../../commons/widgets/eg/dialog.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/icon_button.dart';
import '../../../../commons/widgets/eg/identity.dart';
import '../../../../commons/widgets/eg/layer.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../commons/widgets/eg/toast.dart';
import '../../../../commons/widgets/eg/tool_button.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import 'design_sample_sections.dart';

/// Galeria dos ícones: todos, em 16, 14 e 12, na cor do texto ao redor.
class SampleIcons extends StatelessWidget {
  const SampleIcons({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return SampleWrap([
      for (final icon in EgIcons.all)
        Container(
          width: 132,
          padding: const EdgeInsets.all(EgeonSpace.s3),
          decoration: BoxDecoration(
            color: c.carbon,
            borderRadius: BorderRadius.circular(EgeonRadius.md),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EgIcon(icon, color: c.textPrimary),
                  const SizedBox(width: EgeonSpace.s3),
                  EgIcon(icon, size: 14, color: c.textPrimary),
                  const SizedBox(width: EgeonSpace.s3),
                  EgIcon(icon, size: 12, color: c.textPrimary),
                ],
              ),
              const SizedBox(height: EgeonSpace.s2),
              Text(
                icon.name,
                style: EgeonType.monoMeta.copyWith(
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
    ]);
  }
}

/// Galeria dos botões: quatro tipos em três tamanhos, com ícone, desabilitado
/// e carregando; botões só de ícone e da barra de ferramentas.
class SampleButtons extends StatelessWidget {
  const SampleButtons({super.key});

  @override
  Widget build(BuildContext context) {
    void noop() {}
    Widget row(String name, Widget Function(ButtonKind kind) cell) => Padding(
      padding: const EdgeInsets.only(bottom: EgeonSpace.s3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              name,
              style: EgeonType.monoMeta.copyWith(
                color: context.eg.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          for (final kind in ButtonKind.values) ...[
            cell(kind),
            const SizedBox(width: EgeonSpace.s2),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final size in ButtonSize.values)
          row(
            size.name,
            (kind) => Button(
              label: kind.name,
              kind: kind,
              size: size,
              icon: EgIcons.plus,
              onPressed: noop,
            ),
          ),
        row(
          'desabilitado',
          (kind) => Button(label: kind.name, kind: kind, onPressed: null),
        ),
        row(
          'carregando',
          (kind) => Button(
            label: kind.name,
            kind: kind,
            icon: EgIcons.check,
            loading: true,
            onPressed: noop,
          ),
        ),
        const SizedBox(height: EgeonSpace.s3),
        Row(
          children: [
            IconButton(
              icon: EgIcons.search,
              tooltip: 'Buscar',
              onPressed: noop,
            ),
            IconButton(
              icon: EgIcons.more,
              tooltip: 'Mais ações',
              compact: true,
              onPressed: noop,
            ),
            const IconButton(
              icon: EgIcons.trash,
              tooltip: 'Remover',
              onPressed: null,
            ),
            const SizedBox(width: EgeonSpace.s6),
            ToolButton(
              icon: EgIcons.pointer,
              tooltip: 'Selecionar',
              selected: true,
              onPressed: noop,
            ),
            ToolButton(
              icon: EgIcons.hand,
              tooltip: 'Mover',
              shortcut: 'H',
              onPressed: noop,
            ),
            ToolButton(
              icon: EgIcons.agent,
              tooltip: 'Terminal de agente',
              shortcut: '⌘3',
              onPressed: noop,
            ),
          ],
        ),
      ],
    );
  }
}

/// Galeria do que flutua: menu, popover, diálogo, toast e a peça de vidro.
class SampleFloating extends StatelessWidget {
  const SampleFloating({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => Button(
            label: 'Menu',
            icon: EgIcons.chevronDown,
            onPressed: () => showMenu(
              context,
              anchor: globalRectOf(context),
              items: [
                MenuItem('Renomear', icon: EgIcons.edit, onSelected: () {}),
                MenuItem('Duplicar', shortcut: '⌘D', onSelected: () {}),
                const MenuItem('Em breve'),
                const MenuSeparator(),
                MenuItem(
                  'Remover',
                  icon: EgIcons.trash,
                  danger: true,
                  onSelected: () {},
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: EgeonSpace.s2),
        Builder(
          builder: (context) => Button(
            label: 'Popover',
            onPressed: () => showPopover(
              context,
              anchor: globalRectOf(context),
              width: 260,
              builder: (context, close) => Text(
                'Cor da bancada',
                style: EgeonType.body.copyWith(
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: EgeonSpace.s2),
        Builder(
          builder: (context) => Button(
            label: 'Diálogo',
            onPressed: () => showEgDialog<void>(
              context,
              builder: (context, close) => Dialog(
                title: 'Limpar o contexto?',
                actions: [
                  Button(label: 'Cancelar', onPressed: () => close()),
                  Button(
                    label: 'Limpar',
                    kind: ButtonKind.danger,
                    onPressed: () => close(),
                  ),
                ],
                child: const Text('O agente começa do zero.'),
              ),
            ),
          ),
        ),
        const SizedBox(width: EgeonSpace.s2),
        Builder(
          builder: (context) => Button(
            label: 'Toast',
            onPressed: () => showToast(
              context,
              tone: ToastTone.success,
              agent: const Person('maestro', identity: Identity.iris),
              title: 'terminou',
              description: 'A bancada loja/front está pronta.',
              actions: (close) => [
                Button(label: 'Ver', size: ButtonSize.sm, onPressed: close),
              ],
            ),
          ),
        ),
        const SizedBox(width: EgeonSpace.s6),
        const GlassSurface(
          radius: EgeonRadius.lg,
          padding: EdgeInsets.all(EgeonSpace.s4),
          child: Text('Vidro'),
        ),
      ],
    );
  }
}
