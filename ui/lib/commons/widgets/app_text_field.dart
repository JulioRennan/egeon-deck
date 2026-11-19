import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// Campo de texto de uma linha, ou de várias com [maxLines] maior. Sem Material:
/// o fundo e o foco são desenhados aqui.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    this.placeholder,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.onKeyEvent,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool autofocus;
  final int maxLines;

  /// Linhas mínimas; abaixo de [maxLines] o campo cresce com o texto.
  final int? minLines;

  /// Tecla antes do campo: devolver `handled` come o evento (o Enter que manda
  /// em vez de quebrar a linha).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// De fora, para quem compõe pôr o teclado no campo depois de um gesto.
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    // Depois do primeiro quadro: quem hospeda (a janela) já tomou o foco, e o
    // campo o pede de volta para quem digita.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 13,
      color: Color(0xFFFFFFFF),
      decoration: TextDecoration.none,
    );
    return ListenableBuilder(
      listenable: Listenable.merge([_focus, widget.controller]),
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.black(0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _focus.hasFocus ? AppColors.accent : AppColors.white(0.14),
            width: _focus.hasFocus ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            if (widget.controller.text.isEmpty && widget.placeholder != null)
              IgnorePointer(
                child: Text(
                  widget.placeholder!,
                  style: style.copyWith(color: AppColors.white(0.3)),
                ),
              ),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) =>
                  widget.onKeyEvent?.call(event) ?? KeyEventResult.ignored,
              child: EditableText(
                controller: widget.controller,
                focusNode: _focus,
                maxLines: widget.maxLines,
                minLines: widget.minLines ?? widget.maxLines,
                style: style,
                cursorColor: AppColors.accent,
                backgroundCursorColor: AppColors.white(0.2),
                selectionColor: AppColors.accent.withValues(alpha: 0.4),
                onSubmitted: (_) => widget.onSubmitted?.call(),
                onChanged: widget.onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
