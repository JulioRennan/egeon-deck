import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import 'app_dialog.dart';
import 'app_text_field.dart';

/// Pergunta sim ou não. Devolve `true` ao confirmar; Esc, clique fora e o
/// botão de cancelar devolvem `false`.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  double width = 360,
}) async {
  final result = await showAppDialog<bool>(
    context,
    width: width,
    builder: (_, close) => DialogBody(
      title: title,
      message: message,
      actions: [
        DialogButton('Cancelar', onTap: () => close(false)),
        DialogButton(
          confirmLabel,
          primary: true,
          destructive: destructive,
          onTap: () => close(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Só avisa: um título, um texto e o OK.
Future<void> messageDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showAppDialog<void>(
  context,
  builder: (_, close) => DialogBody(
    title: title,
    message: message,
    actions: [DialogButton('OK', primary: true, onTap: close)],
  ),
);

/// Pede uma linha de texto. `null` se cancelou; vazio conta como cancelar.
Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  String initial = '',
  String? placeholder,
  bool allowEmpty = false,
}) => showAppDialog<String>(
  context,
  builder: (_, close) => _PromptBody(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    initial: initial,
    placeholder: placeholder,
    multiline: false,
    allowEmpty: allowEmpty,
    close: close,
  ),
);

/// Como [promptDialog], mas de várias linhas — e vazio é um valor válido.
Future<String?> textAreaDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  String initial = '',
}) => showAppDialog<String>(
  context,
  width: 460,
  builder: (_, close) => _PromptBody(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    initial: initial,
    multiline: true,
    close: close,
  ),
);

class _PromptBody extends StatefulWidget {
  const _PromptBody({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.multiline,
    required this.close,
    this.allowEmpty = false,
    this.message,
    this.placeholder,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String initial;
  final String? placeholder;
  final bool multiline;
  final bool allowEmpty;
  final void Function([String? result]) close;

  @override
  State<_PromptBody> createState() => _PromptBodyState();
}

class _PromptBodyState extends State<_PromptBody> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (!widget.multiline && !widget.allowEmpty && text.isEmpty) {
      return widget.close();
    }
    widget.close(text);
  }

  @override
  Widget build(BuildContext context) => DialogBody(
    title: widget.title,
    message: widget.message,
    actions: [
      DialogButton('Cancelar', onTap: widget.close),
      DialogButton(widget.confirmLabel, primary: true, onTap: _submit),
    ],
    child: AppTextField(
      controller: _controller,
      placeholder: widget.placeholder,
      autofocus: true,
      maxLines: widget.multiline ? 7 : 1,
      onSubmitted: widget.multiline ? null : _submit,
    ),
  );
}

/// Como [confirmDialog], com uma opção marcável embaixo (desmarcada de saída).
Future<({bool confirmed, bool option})> confirmWithOptionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String optionLabel,
  bool destructive = false,
  String? optionHint,
}) async {
  final result = await showAppDialog<({bool confirmed, bool option})>(
    context,
    builder: (_, close) => _OptionBody(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      optionLabel: optionLabel,
      optionHint: optionHint,
      destructive: destructive,
      close: close,
    ),
  );
  return result ?? (confirmed: false, option: false);
}

class _OptionBody extends StatefulWidget {
  const _OptionBody({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.optionLabel,
    required this.destructive,
    required this.close,
    this.optionHint,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String optionLabel;

  /// Linhas miúdas embaixo da opção, recuadas sob o texto dela.
  final String? optionHint;
  final bool destructive;
  final void Function([({bool confirmed, bool option})? result]) close;

  @override
  State<_OptionBody> createState() => _OptionBodyState();
}

class _OptionBodyState extends State<_OptionBody> {
  bool _option = false;

  @override
  Widget build(BuildContext context) => DialogBody(
    title: widget.title,
    message: widget.message,
    actions: [
      DialogButton('Cancelar', onTap: widget.close),
      DialogButton(
        widget.confirmLabel,
        primary: true,
        destructive: widget.destructive,
        onTap: () => widget.close((confirmed: true, option: _option)),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_optionRow(), ?_hint()],
    ),
  );

  Widget? _hint() {
    final hint = widget.optionHint;
    if (hint == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 4),
      child: Text(
        hint,
        key: const ValueKey('option-hint'),
        style: TextStyle(
          fontSize: 10,
          color: AppColors.white(0.5),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _optionRow() => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _option = !_option),
      child: Row(
        children: [
          Container(
            key: const ValueKey('option-box'),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _option ? AppColors.accent : null,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: _option ? AppColors.accent : AppColors.white(0.4),
              ),
            ),
            alignment: Alignment.center,
            child: _option
                ? const Text(
                    '✓',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFFFFF),
                      decoration: TextDecoration.none,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.optionLabel,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.white(0.85),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
