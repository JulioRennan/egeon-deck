import 'package:flutter/widgets.dart';

/// Onde se clica, o ponteiro diz: a mão em cima de [child]. Desligado
/// ([enabled] falso), deixa o cursor de quem está por baixo valer.
class HandCursor extends StatelessWidget {
  const HandCursor({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
    child: child,
  );
}
