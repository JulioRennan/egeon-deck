import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// O que o controle está vivendo agora; o [Pressable] entrega ao `builder`.
class PressState {
  const PressState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
  });

  final bool hovered;
  final bool pressed;

  /// Foco por teclado, só onde o controle pede o destaque (o item de menu
  /// andado pelas setas); botão nenhum desenha anel.
  final bool focused;
  final bool enabled;
}

/// A base de todo controle clicável do design system: hover, pressionado,
/// foco por teclado (Enter e Espaço ativam), desabilitado e a mão no ponteiro
/// (ADR-048). Sem ripple: quem desenha reage ao [PressState]. Clicar não toma
/// o foco: no macOS o Flutter conta o mouse como modo de teclado, e o anel
/// ficava preso no botão clicado.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.builder,
    this.onPressed,
    this.onSecondaryPressed,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.showsFocus = false,
    this.semanticLabel,
    super.key,
  });

  final Widget Function(BuildContext context, PressState state) builder;

  /// Nulo desabilita o controle.
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool canRequestFocus;

  /// Entrega o foco ao `builder` para ele destacar (item de menu).
  final bool showsFocus;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _set({bool? hovered, bool? pressed, bool? focused}) {
    final h = hovered ?? _hovered;
    final p = pressed ?? _pressed;
    final f = focused ?? _focused;
    if (h == _hovered && p == _pressed && f == _focused) return;
    setState(() {
      _hovered = h;
      _pressed = p;
      _focused = f;
    });
  }

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    if (!_enabled && (_pressed || _hovered)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(
      context,
      PressState(
        hovered: _hovered && _enabled,
        pressed: _pressed && _enabled,
        focused: _focused && _enabled && widget.showsFocus,
        enabled: _enabled,
      ),
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled && widget.canRequestFocus,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (v) => _set(focused: v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _set(hovered: true),
          onExit: (_) => _set(hovered: false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => _set(pressed: true) : null,
            onTapUp: _enabled ? (_) => _set(pressed: false) : null,
            onTapCancel: _enabled ? () => _set(pressed: false) : null,
            onTap: widget.onPressed,
            onSecondaryTap: widget.onSecondaryPressed,
            child: child,
          ),
        ),
      ),
    );
  }
}
