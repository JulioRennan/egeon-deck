import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/glyphs.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../commons/widgets/standard_dialogs.dart';
import '../../../../../commons/widgets/web_surface.dart';
import '../../../../../core/adapters/injector.dart';
import '../../../../../theme/app_colors.dart';
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

  static const barHeight = 30.0;

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
          WebShown(:final node, :final page, :final address) => (
            node,
            page,
            address,
          ),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: WebBody.barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              color: const Color(0xFF262626),
              child: Row(
                children: [
                  _NavButton(
                    key: const ValueKey('web-back'),
                    glyph: const ChevronGlyph(
                      ChevronDirection.left,
                      color: Color(0xFFB0B0B0),
                      size: 14,
                    ),
                    enabled: page?.canGoBack ?? false,
                    onTap: cubit.back,
                  ),
                  _NavButton(
                    key: const ValueKey('web-forward'),
                    glyph: const ChevronGlyph(
                      ChevronDirection.right,
                      color: Color(0xFFB0B0B0),
                      size: 14,
                    ),
                    enabled: page?.canGoForward ?? false,
                    onTap: cubit.forward,
                  ),
                  _NavButton(
                    key: const ValueKey('web-reload'),
                    glyph: CustomPaint(
                      size: const Size.square(14),
                      painter: _ReloadPainter(loading: page?.loading ?? false),
                    ),
                    enabled: true,
                    onTap: cubit.reload,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: AddressField(
                      address: address,
                      onSubmit: cubit.submit,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ProfilePicker(node: node, cubit: cubit),
                ],
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.glyph,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final Widget glyph;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    enabled: enabled,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: SizedBox(width: 24, height: 24, child: Center(child: glyph)),
      ),
    ),
  );
}

class _ReloadPainter extends CustomPainter {
  _ReloadPainter({required this.loading});

  final bool loading;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2.5);
    final paint = Paint()
      ..color = loading ? AppColors.accent : const Color(0xFFB0B0B0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -1.2, 5.0, false, paint);
    final tip = Offset(rect.right - 0.5, rect.center.dy - 3.5);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 3, tip.dy - 1)
        ..lineTo(tip.dx + 0.5, tip.dy + 1.5)
        ..lineTo(tip.dx + 2.5, tip.dy - 2.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ReloadPainter old) => old.loading != loading;
}

/// O perfil de navegação: cookies e bancada isolados por nome.
class _ProfilePicker extends StatelessWidget {
  const _ProfilePicker({required this.node, required this.cubit});

  /// Nulo até o core mandar o nó: sem perfil, sem menu.
  final WebNode? node;
  final WebCubit cubit;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node == null) return const SizedBox.shrink();
    return HandCursor(
      child: GestureDetector(
        key: const ValueKey('web-profile'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          final at = box.localToGlobal(Offset(0, box.size.height + 4));
          showContextMenu(
            context,
            position: at,
            entries: [
              for (final name in node.menu)
                MenuEntry(
                  name,
                  () => cubit.setProfile(name),
                  leading: SizedBox(
                    width: 10,
                    child: name == node.profile
                        ? const Text(
                            '✓',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 11,
                              decoration: TextDecoration.none,
                            ),
                          )
                        : null,
                  ),
                ),
              const MenuEntry.separator(),
              MenuEntry('Novo perfil…', () async {
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
              }),
            ],
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              node.profile,
              style: TextStyle(
                color: AppColors.white(0.7),
                fontSize: 10,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 3),
            ChevronGlyph(
              ChevronDirection.down,
              color: AppColors.white(0.5),
              size: 9,
            ),
          ],
        ),
      ),
    );
  }
}
