import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ponte com o método de entrada do sistema (IME): é por aqui que chegam as
/// teclas mortas (´ ~ ^ ` ¨), o ç e qualquer texto composto. O texto só sai
/// quando a composição termina; enquanto ela dura, [composing] guarda o
/// trecho provisório para a tela mostrar no cursor.
class TerminalTextInput with TextInputClient {
  TerminalTextInput({required this.onText, this.onClosed});

  final ValueChanged<String> onText;

  /// O sistema fechou a conexão de texto (outro campo tomou a entrada, reset
  /// da plataforma). Quem tem o foco usa isto para reabri-la.
  final VoidCallback? onClosed;

  /// O trecho em composição (por exemplo `´` depois de uma tecla morta).
  final composing = ValueNotifier<String>('');

  static const _empty = TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );

  TextInputConnection? _connection;
  TextEditingValue _value = _empty;

  bool get isComposing => composing.value.isNotEmpty;
  bool get attached => _connection?.attached ?? false;

  void attach() {
    if (attached) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputAction: TextInputAction.none,
        autocorrect: false,
        enableSuggestions: false,
        enableDeltaModel: false,
      ),
    )..show();
    _value = _empty;
    _connection!.setEditingState(_value);
  }

  void detach() {
    _connection?.close();
    _connection = null;
    _value = _empty;
    composing.value = '';
  }

  void dispose() {
    detach();
    composing.dispose();
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    final range = value.composing;
    if (range.isValid && !range.isCollapsed) {
      composing.value = range.textInside(value.text);
      return;
    }
    composing.value = '';
    if (value.text.isEmpty) return;
    onText(value.text);
    _value = _empty;
    _connection?.setEditingState(_value);
  }

  @override
  void connectionClosed() {
    _connection = null;
    composing.value = '';
    onClosed?.call();
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void performAction(TextInputAction action) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
}
