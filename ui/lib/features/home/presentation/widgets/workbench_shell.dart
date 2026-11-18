import 'package:flutter/widgets.dart';

/// A bancada na janela: a barra de cima de borda a borda, a faixa de abas e o
/// conteúdo embaixo. Quem cede à barra lateral é só o conteúdo — a barra de
/// cima corre inteira em todo modo, e as cortinas cobrem só o conteúdo.
class WorkbenchShell extends StatelessWidget {
  const WorkbenchShell({
    required this.toolbar,
    required this.tabs,
    required this.content,
    this.curtains = const [],
    this.contentInset = 0,
    super.key,
  });

  final Widget toolbar;

  /// A faixa de abas; quando some, o conteúdo sobe.
  final Widget tabs;
  final Widget content;
  final List<Widget> curtains;

  /// Quanto o conteúdo cede à barra lateral: nada no canvas, onde o grid corre
  /// por baixo do vidro, e a largura dela no chat.
  final double contentInset;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      toolbar,
      tabs,
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              left: contentInset,
              child: KeyedSubtree(
                key: const ValueKey('shell-content'),
                child: content,
              ),
            ),
            for (final curtain in curtains)
              Positioned.fill(left: contentInset, child: curtain),
          ],
        ),
      ),
    ],
  );
}
