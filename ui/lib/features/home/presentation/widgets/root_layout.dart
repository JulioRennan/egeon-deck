import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/glass_panel.dart';
import '../../../sidebar/presentation/widgets/sidebar_panel.dart';
import 'view_toolbar.dart';

/// A raiz: a bancada ocupa a janela inteira e a barra lateral flutua por cima
/// dela — no canvas por cima do grid, e no chat ao LADO do conteúdo, porque ali
/// sobreposição é mensagem coberta.
class RootLayout extends StatelessWidget {
  const RootLayout({
    required this.shell,
    required this.sidebar,
    required this.collapsed,
    required this.beside,
    super.key,
  });

  /// Monta a bancada, já sabendo quanto ceder à barra: `contentInset` (só no
  /// chat) e `tabsInset` (sempre, a faixa nunca fica sob o vidro).
  final Widget Function(double contentInset, double tabsInset) shell;
  final Widget sidebar;
  final bool collapsed;

  /// O conteúdo na tela fica ao lado da barra, e não por baixo dela.
  final bool beside;

  static const margin = 10.0;
  static const gap = 8.0;
  static const top = ViewToolbar.height + 8;

  static double sidebarWidth({required bool collapsed}) =>
      collapsed ? SidebarPanel.railWidth : SidebarPanel.expandedWidth;

  /// Quanto da borda esquerda a barra cobre agora. No canvas o enquadramento de
  /// nós desconta isto — e é lido na hora, porque recolher muda o número.
  static double floatingInset({
    required bool collapsed,
    required bool beside,
  }) => beside ? 0 : margin + sidebarWidth(collapsed: collapsed) + gap;

  @override
  Widget build(BuildContext context) {
    final cover = margin + sidebarWidth(collapsed: collapsed) + gap;
    return ColoredBox(
      color: const Color(0xFF171717),
      child: Stack(
        children: [
          Positioned.fill(child: shell(beside ? cover : 0, cover)),
          Positioned(
            left: margin,
            top: top,
            bottom: margin,
            width: sidebarWidth(collapsed: collapsed),
            child: GlassPanel(radius: 16, child: sidebar),
          ),
        ],
      ),
    );
  }
}
