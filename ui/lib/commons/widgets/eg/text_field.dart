import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'editable.dart';
import 'eg_icon.dart';
import 'field.dart';
import 'spinner.dart';

/// Campo de texto de uma linha: rótulo, placeholder, dica, erro, ícone à
/// esquerda, sufixo e spinner à direita. Com [mono] o texto é JetBrains Mono
/// (caminhos, endereços, comandos).
class TextField extends StatefulWidget {
  const TextField({
    this.controller,
    this.initialValue,
    this.label,
    this.placeholder,
    this.hint,
    this.error,
    this.icon,
    this.suffix,
    this.mono = false,
    this.loading = false,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.focusNode,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.width,
    super.key,
  });

  /// Sem controller, o campo guarda o próprio, a partir de [initialValue].
  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? placeholder;
  final String? hint;
  final String? error;
  final EgIconData? icon;
  final String? suffix;
  final bool mono;
  final bool loading;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField> {
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
    // Depois do primeiro quadro: quem hospeda (a gaveta, o diálogo) já tomou o
    // foco, e o campo o pede de volta para quem digita.
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
    // 14/20 (mono 13/20), como o `.eg-input` do DS.
    final style = (widget.mono ? EgeonType.code : EgeonType.body).copyWith(
      color: widget.enabled ? c.textPrimary : c.textDisabled,
      decoration: TextDecoration.none,
      height: 20 / (widget.mono ? 13 : 14),
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
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    EgIcon(
                      widget.icon!,
                      color: widget.enabled ? c.textMuted : c.textDisabled,
                    ),
                    const SizedBox(width: EgeonSpace.s2),
                  ],
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        if (_controller.text.isEmpty &&
                            widget.placeholder != null)
                          IgnorePointer(
                            child: Text(
                              widget.placeholder!,
                              style: style.copyWith(
                                color: widget.enabled
                                    ? c.textMuted
                                    : c.textDisabled,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        Editable(
                          controller: _controller,
                          focusNode: _focus,
                          style: style,
                          cursorColor: c.accent,
                          selectionColor: c.termSelection,
                          obscureText: widget.obscureText,
                          readOnly: !widget.enabled,
                          inputFormatters: widget.inputFormatters,
                          onChanged: widget.onChanged,
                          onSubmitted: widget.onSubmitted,
                        ),
                      ],
                    ),
                  ),
                  if (widget.loading) ...[
                    const SizedBox(width: EgeonSpace.s2),
                    const Spinner(),
                  ],
                  if (widget.suffix != null) ...[
                    const SizedBox(width: EgeonSpace.s2),
                    Text(
                      widget.suffix!,
                      style: EgeonType.monoMeta.copyWith(
                        fontWeight: FontWeight.w400,
                        color: c.textMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
