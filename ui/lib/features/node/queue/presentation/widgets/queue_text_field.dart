import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';

/// Campo de texto corrido da fila: várias linhas, Enter confirma e ⇧Enter
/// quebra a linha, Esc sai. Não é o `TextField` do Material — o app não o usa.
class QueueTextField extends StatefulWidget {
  const QueueTextField({
    required this.text,
    required this.onChanged,
    this.hint = '',
    this.onSubmit,
    this.onEscape,
    this.readOnly = false,
    this.autofocus = false,
    this.fontSize = 13,
    this.focusNode,
    super.key,
  });

  final String text;
  final String hint;
  final bool readOnly;
  final bool autofocus;
  final double fontSize;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  /// Enter sem ⇧.
  final VoidCallback? onSubmit;
  final VoidCallback? onEscape;

  @override
  State<QueueTextField> createState() => _QueueTextFieldState();
}

class _QueueTextFieldState extends State<QueueTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void didUpdateWidget(QueueTextField old) {
    super.didUpdateWidget(old);
    // A fila grava e avisa a cada tecla; recriar o texto com o cursor dentro
    // tiraria o teclado de você. Só vale de fora quando o campo não tem foco.
    if (widget.text != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.enter && !shift) {
      widget.onSubmit?.call();
      return widget.onSubmit == null
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onEscape?.call();
      return widget.onEscape == null
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppColors.white(0.9),
      fontSize: widget.fontSize,
      height: 1.3,
      decoration: TextDecoration.none,
    );
    return Focus(
      onKeyEvent: _onKey,
      skipTraversal: true,
      child: Stack(
        children: [
          if (widget.hint.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _controller.text.isEmpty
                      ? Text(
                          widget.hint,
                          style: style.copyWith(color: AppColors.white(0.3)),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          MouseRegion(
            cursor: SystemMouseCursors.text,
            child: EditableText(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              readOnly: widget.readOnly,
              style: style,
              cursorColor: AppColors.white(0.9),
              backgroundCursorColor: AppColors.white(0.2),
              selectionColor: AppColors.accent.withValues(alpha: 0.4),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
