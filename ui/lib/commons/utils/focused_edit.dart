import 'package:flutter/widgets.dart';

import '../../core/adapters/native_edit.dart';

/// Entrega a ação do menu Editar ao widget focado da Flutter: o terminal e as
/// caixas de texto a atendem como intent. Devolve `false` quando ninguém na
/// Flutter a quer (a página web, que vive na cadeia de responders do AppKit).
///
/// O ⌘V também passa por aqui: com o método de entrada ligado, o macOS pode dar
/// o atalho ao item do menu antes da tecla chegar ao Dart.
bool invokeFocusedEdit(EditAction action, {BuildContext? context}) {
  final at = context ?? primaryFocus?.context;
  if (at == null) return false;
  final Intent intent = switch (action) {
    EditAction.undo => const UndoTextIntent(SelectionChangedCause.keyboard),
    EditAction.redo => const RedoTextIntent(SelectionChangedCause.keyboard),
    EditAction.cut => const CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    EditAction.copy => CopySelectionTextIntent.copy,
    EditAction.paste => const PasteTextIntent(SelectionChangedCause.keyboard),
    EditAction.selectAll => const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };
  final handler = Actions.maybeFind<Intent>(at, intent: intent);
  if (handler == null || !handler.isEnabled(intent)) return false;
  Actions.invoke(at, intent);
  return true;
}
