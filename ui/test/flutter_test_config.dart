import 'dart:async';

import 'package:egeon_deck/commons/utils/app_shortcut.dart';

/// Os testes descrevem os atalhos do macOS (⌘); os que cobrem Windows e Linux
/// trocam `debugUsesCommandKey` e devolvem no fim.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugUsesCommandKey = true;
  await testMain();
}
