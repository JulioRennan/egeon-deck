import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_tokens.dart';
import 'bench_frame.dart';

/// A bancada na janela: a faixa de cima de borda a borda e, embaixo, a moldura
/// com a cor da bancada em volta do conteúdo, as camadas fixas e as cortinas.
class WorkbenchShell extends StatelessWidget {
  const WorkbenchShell({
    required this.topBar,
    required this.content,
    this.colorName,
    this.lit = true,
    this.layers,
    this.curtains = const [],
    this.leftInset = frameLeft,
    super.key,
  });

  final Widget topBar;
  final Widget content;

  /// As camadas fixas por cima do conteúdo (barra de ações, consumo, composer).
  final Widget? layers;
  final List<Widget> curtains;

  /// A cor da bancada na tela, como o core a grava.
  final String? colorName;

  /// Sem bancada, a moldura fica sem o brilho.
  final bool lit;

  /// Onde a moldura começa: depois do trilho de bancadas e, com a gaveta fixa,
  /// depois dela.
  final double leftInset;

  /// O respiro da moldura na v3: 12 abaixo da faixa, 24 à direita e embaixo, e
  /// à esquerda 84 (24 de margem, 44 do trilho e 16 de vão).
  static const gapTop = EgeonSpace.s3;
  static const gapRight = EgeonSpace.s6;
  static const gapBottom = EgeonSpace.s6;
  static const frameLeft = 84.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      topBar,
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftInset, gapTop, gapRight, gapBottom),
          child: BenchFrame(
            colorName: colorName,
            lit: lit,
            child: Stack(
              children: [
                Positioned.fill(
                  child: KeyedSubtree(
                    key: const ValueKey('shell-content'),
                    child: content,
                  ),
                ),
                ?layers == null ? null : Positioned.fill(child: layers!),
                for (final curtain in curtains) Positioned.fill(child: curtain),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
