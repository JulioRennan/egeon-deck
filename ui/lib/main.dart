import 'package:flutter/widgets.dart';

void main() {
  runApp(const EgeonDeckApp());
}

/// Raiz do app. Por enquanto só abre a janela: as features entram a partir
/// de `features/home`.
class EgeonDeckApp extends StatelessWidget {
  const EgeonDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'Egeon Deck',
      color: const Color(0xFF171717),
      builder: (context, child) => const ColoredBox(color: Color(0xFF171717)),
    );
  }
}
