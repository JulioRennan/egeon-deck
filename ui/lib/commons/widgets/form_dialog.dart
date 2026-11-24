import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'eg/button.dart';
import 'eg/checkbox.dart';
import 'eg/dialog.dart' as eg;
import 'eg/eg_icon.dart';
import 'eg/text_area.dart';
import 'eg/text_field.dart';
import '../../theme/egeon_colors.dart';
import '../../theme/egeon_type.dart';

/// A largura que o [showFormDialog] deu à janela, para o [FormDialogBody].
class _DialogWidth extends InheritedWidget {
  const _DialogWidth(this.width, {required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DialogWidth>()?.width ?? 360;

  @override
  bool updateShouldNotify(_DialogWidth old) => old.width != width;
}

/// Abre uma janela modal (o `Dialog` do DS) e devolve o que ela fechar com.
/// Precisa de um `Overlay` acima de [context]. Esc e o clique fora cancelam
/// (`null`). O ⌘ que ninguém dentro dela atendeu para aqui, como o `runModal`
/// do Swift: não sobe ao menu para trocar de aba nem fechar a de baixo.
Future<T?> showFormDialog<T>(
  BuildContext context, {
  required Widget Function(
    BuildContext context,
    void Function([T? result]) close,
  )
  builder,
  double width = 440,
}) => eg.showEgDialog<T>(
  context,
  builder: (context, close) => _DialogWidth(
    width,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) =>
          HardwareKeyboard.instance.isMetaPressed &&
              event.logicalKey != LogicalKeyboardKey.metaLeft &&
              event.logicalKey != LogicalKeyboardKey.metaRight
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      // Os atalhos de texto (⌘V, ⌘C, ⌘A, ⌘Z) moram na raiz do `WidgetsApp`,
      // acima deste bloqueio: sem uma cópia aqui dentro o ⌘V morreria antes de
      // chegar ao campo.
      child: DefaultTextEditingShortcuts(
        child: Builder(builder: (context) => builder(context, close)),
      ),
    ),
  ),
);

/// O miolo de uma janela de formulário: título, texto de apoio, o conteúdo e a
/// fileira de botões (`Dialog` do DS).
class FormDialogBody extends StatelessWidget {
  const FormDialogBody({
    required this.title,
    required this.actions,
    this.message,
    this.child,
    this.destructive = false,
    super.key,
  });

  /// A janela que apaga: o ícone da lixeira em cima do título.
  final bool destructive;

  final String title;
  final String? message;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return eg.Dialog(
      title: title,
      width: _DialogWidth.of(context),
      actions: actions,
      icon: destructive ? EgIcons.trash : null,
      // O formulário alto rola dentro da janela, que não passa da tela (a
      // altura é a da janela de verdade: o Column do diálogo não limita).
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (_windowHeight(context) - 300).clamp(120.0, 4000.0),
        ),
        child: SingleChildScrollView(
          // Texto de formulário solto herda linhas mais baixas que o corpo
          // do diálogo.
          child: DefaultTextStyle.merge(
            style: const TextStyle(height: 1.3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null)
                  Text(
                    message!,
                    style: EgeonType.small.copyWith(
                      color: c.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                if (message != null && child != null)
                  const SizedBox(height: 14),
                ?child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _windowHeight(BuildContext context) {
  final view = View.of(context);
  return view.physicalSize.height / view.devicePixelRatio;
}

/// Botão de janela (`Button` do DS). [primary] é o que o Enter confirma;
/// [destructive] com [primary] é a ação que apaga.
class FormDialogButton extends StatelessWidget {
  const FormDialogButton(
    this.label, {
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.enabled = true,
    this.small = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  final bool enabled;

  /// Botão miúdo, para os que moram dentro de um formulário.
  final bool small;

  @override
  Widget build(BuildContext context) => Button(
    label: label,
    size: small ? ButtonSize.sm : ButtonSize.lg,
    kind: primary
        ? (destructive ? ButtonKind.dangerSolid : ButtonKind.primary)
        : (small ? ButtonKind.secondary : ButtonKind.ghost),
    onPressed: enabled ? onTap : null,
  );
}

/// Pergunta e espera: confirmar ou cancelar. [destructive] pinta o botão de
/// perigo (apaga).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  double width = 440,
}) async {
  final result = await showFormDialog<bool>(
    context,
    width: width,
    builder: (_, close) => FormDialogBody(
      title: title,
      message: message,
      destructive: destructive,
      actions: [
        FormDialogButton('Cancelar', onTap: () => close(false)),
        FormDialogButton(
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
}) => showFormDialog<void>(
  context,
  builder: (_, close) => FormDialogBody(
    title: title,
    message: message,
    actions: [FormDialogButton('OK', primary: true, onTap: close)],
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
}) => showFormDialog<String>(
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
}) => showFormDialog<String>(
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
  Widget build(BuildContext context) => FormDialogBody(
    title: widget.title,
    message: widget.message,
    actions: [
      FormDialogButton('Cancelar', onTap: widget.close),
      FormDialogButton(widget.confirmLabel, primary: true, onTap: _submit),
    ],
    child: widget.multiline
        ? TextArea(
            controller: _controller,
            placeholder: widget.placeholder,
            autofocus: true,
            rows: 7,
          )
        : TextField(
            controller: _controller,
            placeholder: widget.placeholder,
            autofocus: true,
            onSubmitted: (_) => _submit(),
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
  final result = await showFormDialog<({bool confirmed, bool option})>(
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
  Widget build(BuildContext context) {
    final c = context.eg;
    final hint = widget.optionHint;
    return FormDialogBody(
      title: widget.title,
      message: widget.message,
      destructive: widget.destructive,
      actions: [
        FormDialogButton('Cancelar', onTap: widget.close),
        FormDialogButton(
          widget.confirmLabel,
          primary: true,
          destructive: widget.destructive,
          onTap: () => widget.close((confirmed: true, option: _option)),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: const ValueKey('option-box'),
            checked: _option,
            onChanged: (v) => setState(() => _option = v),
            label: Text(widget.optionLabel),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(
                hint,
                key: const ValueKey('option-hint'),
                style: EgeonType.caption.copyWith(
                  color: c.textMuted,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
