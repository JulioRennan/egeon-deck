import 'package:flutter/widgets.dart';

import 'eg_host.dart';

/// Uma janela com `Overlay` e o tema do design system, para o que abre
/// camadas e para os widgets que leem as cores do tema.
Widget overlayHost(Widget child, {Size size = const Size(1000, 800)}) =>
    egHost(child, size: size, fill: true);
