import 'package:flutter/widgets.dart';

/// Hospeda um widget com `Overlay` (menus precisam de um), no canto de uma
/// janela de tamanho fixo.
Widget overlayHost(Widget child, {Size size = const Size(1000, 800)}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      // Listas reordenáveis (a fila) pedem os textos do sistema, que o
      // WidgetsApp do app já dá.
      child: Localizations(
        locale: const Locale('pt'),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
