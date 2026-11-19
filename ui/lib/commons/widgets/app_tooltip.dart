import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// A dica de um controle: o texto aparece perto do cursor depois que ele para
/// um instante sobre [child], e some ao sair ou clicar — como o `toolTip` do
/// AppKit. Precisa de um `Overlay` acima; sem ele, só mostra [child].
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    required this.message,
    required this.child,
    this.passThrough = false,
    super.key,
  });

  final String message;
  final Widget child;

  /// Para texto sem gesto próprio (o título do card): a dica aparece mesmo com
  /// [child] ignorando o ponteiro, e o gesto segue para o que está atrás (o
  /// arrasto do cabeçalho).
  final bool passThrough;

  /// Quanto o cursor espera parado antes da dica aparecer.
  static const delay = Duration(milliseconds: 600);

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  Timer? _timer;
  OverlayEntry? _entry;
  Offset _pointer = Offset.zero;

  void _wait(Offset position) {
    _pointer = position;
    if (_entry != null) return;
    _timer?.cancel();
    _timer = Timer(AppTooltip.delay, _show);
  }

  void _show() {
    final overlay = Overlay.maybeOf(context);
    if (!mounted || overlay == null || widget.message.isEmpty) return;
    final box = overlay.context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final at = box.globalToLocal(_pointer);
    final bounds = box.size;
    _entry = OverlayEntry(
      builder: (_) => _Bubble(message: widget.message, at: at, bounds: bounds),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void didUpdateWidget(AppTooltip old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  HitTestBehavior get _behavior => widget.passThrough
      ? HitTestBehavior.translucent
      : HitTestBehavior.deferToChild;

  @override
  Widget build(BuildContext context) => MouseRegion(
    // A dica não decide o ponteiro nem pega toque além do controle: o cursor
    // é o do controle de dentro. Opaca, senão o toque atravessa para o que
    // está atrás dele (o arrasto do cabeçalho do card).
    hitTestBehavior: _behavior,
    onHover: (e) => _wait(e.position),
    onExit: (_) => _hide(),
    child: Listener(
      behavior: _behavior,
      onPointerDown: (_) => _hide(),
      child: widget.child,
    ),
  );
}

/// A dica desenhada abaixo do cursor, sem passar da borda da janela e sem
/// pegar clique.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.at,
    required this.bounds,
  });

  final String message;
  final Offset at;
  final Size bounds;

  static const maxWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    final left = at.dx.clamp(
      8.0,
      (bounds.width - maxWidth - 8).clamp(8.0, double.infinity),
    );
    final below = at.dy + 20;
    final top = below + 60 > bounds.height ? at.dy - 44 : below;
    return Positioned(
      left: left,
      top: top.clamp(4.0, bounds.height),
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Container(
            key: const ValueKey('app-tooltip'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xF0262626),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.white(0.14)),
            ),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: AppColors.white(0.9),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
