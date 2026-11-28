import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/icon_button.dart' as eg;
import '../../../../../commons/widgets/eg/menu.dart';
import '../../../../../commons/widgets/eg/popover.dart';
import '../../../../../commons/widgets/eg/pressable.dart';
import '../../../../../commons/widgets/eg/tooltip.dart';
import '../../../../../commons/widgets/form_dialog.dart';
import '../../../../../commons/widgets/web_surface.dart';
import '../../../../../core/adapters/injector.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_type.dart';
import '../../../card/presentation/widgets/card_motion.dart';
import '../../domain/entities/web_node.dart';
import '../cubit/web_cubit.dart';
import 'address_field.dart';

/// O corpo de um card web: a barra de navegação em cima e a página embaixo. Um
/// cubit por nó, que é também o dono da página nativa.
class WebBody extends StatelessWidget {
  const WebBody({required this.workbenchId, required this.nodeId, super.key});

  /// A bancada do nó: os comandos da página vão por ela.
  final String workbenchId;
  final String nodeId;

  static const barHeight = 44.0;

  // A fábrica da página nativa e o registro do `/shot` vêm do injector: o nó
  // não conhece a biblioteca por trás da página.
  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey((workbenchId, nodeId)),
    create: (_) => inject<WebCubit>((workbenchId: workbenchId, nodeId: nodeId)),
    child: const _WebView(),
  );
}

class _WebView extends StatelessWidget {
  const _WebView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WebCubit>();
    return BlocBuilder<WebCubit, WebState>(
      builder: (context, state) {
        final controller = cubit.controller;
        final (node, page, address) = switch (state) {
          WebWaiting() => (null, null, ''),
          // Antes de a página dizer onde está, a barra mostra o que o core
          // guardou; depois, a página.
          WebOpening(:final node) => (node, null, node.url),
          WebShown(:final node, :final page) => (node, page, page.url),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.eg.lineSubtle),
                ),
              ),
              child: SizedBox(
                height: WebBody.barHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      eg.IconButton(
                        key: const ValueKey('web-back'),
                        icon: EgIcons.chevronLeft,
                        tooltip: 'Voltar',
                        compact: true,
                        onPressed: (page?.canGoBack ?? false)
                            ? cubit.back
                            : null,
                      ),
                      eg.IconButton(
                        key: const ValueKey('web-forward'),
                        icon: EgIcons.chevronRight,
                        tooltip: 'Avançar',
                        compact: true,
                        onPressed: (page?.canGoForward ?? false)
                            ? cubit.forward
                            : null,
                      ),
                      eg.IconButton(
                        key: const ValueKey('web-reload'),
                        icon: EgIcons.rotateCcw,
                        tooltip: 'Recarregar',
                        compact: true,
                        onPressed: cubit.reload,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: AddressField(
                          address: address,
                          loading: page?.loading ?? false,
                          onSubmit: cubit.submit,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ProfilePicker(node: node, cubit: cubit),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: controller == null
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: WebSurface(
                        // O controlador novo (troca de perfil) remonta a vista.
                        key: ObjectKey(controller),
                        controller: controller,
                        live: CardMotion.liveOf(context),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// O perfil de navegação: cookies e bancada isolados por nome. Uma pastilha com
/// o nome do perfil que abre o menu.
class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.node, required this.cubit});

  /// Nulo até o core mandar o nó: sem perfil, sem menu.
  final WebNode? node;
  final WebCubit cubit;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node == null) return const SizedBox.shrink();
    final c = context.eg;
    return Tooltip(
      message: 'Perfil de navegação (cookies e bancada isolados)',
      child: Pressable(
        key: const ValueKey('web-profile'),
        semanticLabel: 'Perfil ${node.profile}',
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          showMenu(
            context,
            anchor: box.localToGlobal(Offset.zero) & box.size,
            placement: PopoverPlacement.bottomEnd,
            items: [
              for (final name in node.menu)
                MenuItem(
                  name,
                  checked: name == node.profile,
                  onSelected: () => cubit.setProfile(name),
                ),
              const MenuSeparator(),
              MenuItem(
                'Novo perfil…',
                icon: EgIcons.plus,
                onSelected: () async {
                  final name = await promptDialog(
                    context,
                    title: 'Novo perfil de navegação',
                    message: 'Cookies e bancada ficam isolados por perfil.',
                    confirmLabel: 'Criar',
                    placeholder: 'trabalho',
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    cubit.setProfile(name.trim());
                  }
                },
              ),
            ],
          );
        },
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: s.hovered ? c.steel : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            height: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    node.profile,
                    style: EgeonType.caption.copyWith(
                      color: s.hovered ? c.textPrimary : c.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 6),
                  EgIcon(EgIcons.chevronDown, size: 12, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
