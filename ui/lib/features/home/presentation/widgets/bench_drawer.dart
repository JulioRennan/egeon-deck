import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/motion.dart';
import '../../../../theme/egeon_tokens.dart';
import 'drawer_hover.dart';

/// A gaveta de bancadas: a barra lateral aberta a partir do trilho, num painel
/// de vidro que flutua sobre o canvas. Só abre e fecha — com Esc, ao clicar
/// fora, ao escolher uma bancada ou no botão de recolher — em 200 ms (sem
/// animação com movimento reduzido).
class BenchDrawer extends StatefulWidget {
  const BenchDrawer({
    required this.open,
    required this.onClose,
    required this.child,
    this.group,
    this.hover,
    super.key,
  });

  final bool open;
  final VoidCallback onClose;

  /// O que a gaveta guarda: a barra lateral.
  final Widget child;

  /// O grupo do clique fora: o que estiver nele (o botão do trilho) não conta
  /// como fora.
  final Object? group;

  /// O mouse dentro da gaveta a mantém aberta quando foi ele quem a abriu.
  final DrawerHover? hover;

  static const width = 340.0;

  @override
  State<BenchDrawer> createState() => _BenchDrawerState();
}

class _BenchDrawerState extends State<BenchDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: EgeonMotion.base,
    value: widget.open ? 1 : 0,
  );

  /// O foco da gaveta: entra nela ao abrir, e é por ele que o Esc chega.
  final _focus = FocusNode(debugLabel: 'gaveta de bancadas');

  @override
  void didUpdateWidget(BenchDrawer old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    // Movimento reduzido: troca direta.
    _controller.duration = egDuration(context, EgeonMotion.base);
    if (widget.open) {
      _controller.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) _focus.requestFocus();
      });
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Um só corpo, do começo ao fim da animação: a barra lateral dentro dele
    // tem chaves globais e não pode existir duas vezes.
    return AnimatedBuilder(
      animation: _controller,
      child: _Body(
        onClose: widget.onClose,
        group: widget.group,
        focus: _focus,
        child: widget.child,
      ),
      builder: (context, body) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        final t =
            (widget.open ? EgeonMotion.easeStandard : EgeonMotion.easeExit)
                .transform(_controller.value);
        // Só desliza, sem esmaecer: o vidro (BackdropFilter) dentro de um
        // Opacity é refeito a cada quadro e pisca. A gaveta sai de trás do
        // trilho, recortada na sua faixa.
        return IgnorePointer(
          ignoring: !widget.open,
          child: ClipRect(
            child: FractionalTranslation(
              translation: Offset(-(1 - t), 0),
              child: DrawerHoverRegion(hover: widget.hover, child: body!),
            ),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.onClose,
    required this.group,
    required this.focus,
    required this.child,
  });

  final FocusNode focus;
  final VoidCallback onClose;
  final Object? group;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Sem título nem fechar: o cabeçalho é o da barra lateral, numa linha só
    // (abas, buscar, filtrar, novo e recolher); fecha com Esc ou clicando fora.
    return TapRegion(
      groupId: group,
      onTapOutside: (_) => onClose(),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
        child: Focus(
          focusNode: focus,
          child: GlassSurface(child: child),
        ),
      ),
    );
  }
}
