import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Os testes de consumo medem com as fontes do app: com a Ahem (a de todo
/// teste) cada letra ocupa um quadrado e o segmentado estoura só aqui.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> load(String family, String asset) async {
    final loader = FontLoader(family)..addFont(rootBundle.load(asset));
    await loader.load();
  }

  await load('Noto Sans', 'assets/fonts/NotoSans-Variable.ttf');
  await load('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  await testMain();
}
