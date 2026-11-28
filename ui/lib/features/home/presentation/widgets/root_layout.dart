import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import 'bench_drawer.dart';
import 'top_bar.dart';
import 'workbench_shell.dart';

/// A raiz: a faixa de cima, o trilho de bancadas à esquerda e a moldura com o
/// conteúdo. A gaveta de bancadas abre do trilho: por cima da moldura no canvas
/// e ao LADO do conteúdo no chat (ali sobreposição é mensagem coberta). Não há
/// fixar: a gaveta só abre e fecha.
class RootLayout extends StatelessWidget {
  const RootLayout({
    required this.shell,
    required this.rail,
    required this.drawer,
    required this.collapsed,
    required this.beside,
    super.key,
  });

  /// Monta a bancada, já sabendo onde a moldura começa.
  final Widget Function(double frameLeft) shell;
  final Widget rail;

  /// A gaveta; cuida sozinha de aparecer ou não.
  final Widget drawer;

  /// A gaveta está fechada.
  final bool collapsed;

  /// O conteúdo na tela fica ao lado da gaveta, e não por baixo dela (o chat).
  final bool beside;

  /// O vão entre a gaveta e a moldura que ela empurra.
  static const gap = EgeonSpace.s3;

  /// O menor tamanho de janela que o app aceita (o `contentMinSize` do runner
  /// macOS repete estes números): com a gaveta aberta ao lado no chat ainda cabem a coluna de
  /// participantes e uma conversa legível. Mudou aqui, mude em
  /// `macos/Runner/MainFlutterWindow.swift`.
  static const minWindow = Size(1000, 600);
  static const top = TopBar.height + WorkbenchShell.gapTop;

  /// Onde a moldura começa agora: depois do trilho, e da gaveta se ela empurra.
  static double frameLeft({required bool collapsed, required bool beside}) {
    final pushes = !collapsed && beside;
    return WorkbenchShell.frameLeft + (pushes ? BenchDrawer.width + gap : 0);
  }

  /// Quanto da borda esquerda da moldura a gaveta cobre agora: só quando ela
  /// abre por cima (no canvas). O enquadramento de nós desconta isto,
  /// lido na hora porque abrir e fechar muda o número.
  static double floatingInset({
    required bool collapsed,
    required bool beside,
  }) => !collapsed && !beside ? BenchDrawer.width + gap : 0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.eg.obsidian,
      child: Stack(
        children: [
          Positioned.fill(
            child: shell(frameLeft(collapsed: collapsed, beside: beside)),
          ),
          // O trilho recua sozinho: a faixa toda até a moldura é dele (hover).
          Positioned(
            left: 0,
            top: top,
            bottom: WorkbenchShell.gapBottom,
            width: WorkbenchShell.frameLeft,
            child: rail,
          ),
          Positioned(
            left: WorkbenchShell.frameLeft,
            top: top,
            bottom: WorkbenchShell.gapBottom,
            width: BenchDrawer.width,
            child: drawer,
          ),
        ],
      ),
    );
  }
}
