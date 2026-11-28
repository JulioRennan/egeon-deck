import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'editable.dart';
import 'field.dart';

/// Campo de várias linhas: nasce com [rows] linhas (3) e cresce com o texto.
class TextArea extends StatefulWidget {
  const TextArea({
    this.controller,
    this.initialValue,
    this.label,
    this.placeholder,
    this.hint,
    this.error,
    this.rows = 3,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.width,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? placeholder;
  final String? hint;
  final String? error;
  final int rows;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final double? width;

  @override
  State<TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<TextArea> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  bool _hovered = false;

  TextEditingController get _controller =>
      widget.controller ??
      (_ownController ??= TextEditingController(text: widget.initialValue));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final style = EgeonType.body.copyWith(
      color: widget.enabled ? c.textPrimary : c.textDisabled,
      decoration: TextDecoration.none,
      height: 20 / 14,
    );
    return Field(
      label: widget.label,
      hint: widget.hint,
      error: widget.error,
      width: widget.width,
      child: ListenableBuilder(
        listenable: Listenable.merge([_focus, _controller]),
        builder: (context, _) => MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.text : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.enabled ? (_) => _focus.requestFocus() : null,
            child: InputShell(
              hovered: _hovered,
              focused: _focus.hasFocus,
              error: widget.error != null,
              enabled: widget.enabled,
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: EgeonSpace.s3,
                vertical: EgeonSpace.s2,
              ),
              child: Stack(
                children: [
                  if (_controller.text.isEmpty && widget.placeholder != null)
                    IgnorePointer(
                      child: Text(
                        widget.placeholder!,
                        style: style.copyWith(
                          color: widget.enabled ? c.textMuted : c.textDisabled,
                        ),
                      ),
                    ),
                  Editable(
                    controller: _controller,
                    focusNode: _focus,
                    style: style,
                    cursorColor: c.accent,
                    selectionColor: c.termSelection,
                    maxLines: null,
                    minLines: widget.rows,
                    readOnly: !widget.enabled,
                    onChanged: widget.onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
