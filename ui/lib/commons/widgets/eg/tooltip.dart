import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'kbd.dart';
import 'motion.dart';

/// A dica de um controle só de ícone: aparece sob ele depois de 500 ms com o
/// cursor parado (ou na hora, com foco por teclado) e some ao sair, clicar ou
/// perder o foco. Precisa de um `Overlay` acima; sem ele, só mostra [child].
class Tooltip extends StatefulWidget {
  const Tooltip({
    required this.message,
    required this.child,
    this.shortcut,
    super.key,
  });

  final String message;

  /// Atalho em chip à direita do texto (ex.: `⌘3`).
  final String? shortcut;
  final Widget child;

  static const delay = Duration(milliseconds: 500);

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  Timer? _timer;
  OverlayEntry? _entry;

  void _schedule() {
    if (_entry != null) return;
    _timer?.cancel();
    _timer = Timer(Tooltip.delay, _show);
  }

  void _show() {
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject();
    if (!mounted || overlay == null || box is! RenderBox || !box.attached) {
      return;
    }
    if (_entry != null || widget.message.isEmpty) {
      return;
    }
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final target =
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
    _entry = OverlayEntry(
      builder: (_) => _TooltipBubble(
        target: target,
        message: widget.message,
        shortcut: widget.shortcut,
      ),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _timer?.cancel();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // Translúcida: a dica não rouba o clique de quem está atrás (o título do
      // card é a alça de arrasto).
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) => _schedule(),
      onExit: (_) => _hide(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _hide(),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) {
            if (!focused) {
              _hide();
            } else if (FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional) {
              _show();
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _TooltipBubble extends StatelessWidget {
  const _TooltipBubble({
    required this.target,
    required this.message,
    required this.shortcut,
  });

  final Rect target;
  final String message;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: _TooltipLayout(target),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: egDuration(context, EgeonMotion.fast),
          curve: EgeonMotion.easeStandard,
          builder: (_, t, child) => Opacity(opacity: t, child: child),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.carbon,
                borderRadius: BorderRadius.circular(EgeonRadius.sm),
                boxShadow: EgeonShadow.float,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        message,
                        style: EgeonType.caption.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (shortcut != null) ...[
                      const SizedBox(width: EgeonSpace.s2),
                      Kbd(shortcut!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  _TooltipLayout(this.target);

  final Rect target;
  static const _gap = 6.0;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = target.center.dx - childSize.width / 2;
    x = x.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    var y = target.bottom + _gap;
    if (y + childSize.height > size.height - _margin) {
      y = target.top - _gap - childSize.height;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.target != target;
}
