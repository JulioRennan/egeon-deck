import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Onde a página está agora: o endereço e o que a navegação permite.
class WebPageState {
  const WebPageState({
    required this.url,
    this.canGoBack = false,
    this.canGoForward = false,
    this.loading = false,
  });

  final String url;
  final bool canGoBack;
  final bool canGoForward;
  final bool loading;
}

/// Uma página web de verdade, por trás de uma interface: quem usa (o nó web)
/// não conhece a biblioteca nativa. A implementação por plataforma entra pela
/// fábrica quando existir; os testes usam um falso.
abstract interface class WebSurfaceController {
  /// A cada navegação e a cada commit.
  Stream<WebPageState> get states;

  Future<void> load(String url);

  Future<void> goBack();

  Future<void> goForward();

  Future<void> reload();

  /// A página como PNG, para o modo congelado; `null` se não há o que capturar.
  Future<Uint8List?> capture();

  /// A vista nativa, para o modo ao vivo.
  Widget buildView(BuildContext context);

  void dispose();
}

/// Mostra a página. Ao vivo ([live]) é a vista nativa na posição do widget;
/// senão, a última captura — que acompanha a transformação do canvas, coisa
/// que uma vista nativa não faz.
class WebSurface extends StatefulWidget {
  const WebSurface({required this.controller, required this.live, super.key});

  final WebSurfaceController controller;
  final bool live;

  @override
  State<WebSurface> createState() => _WebSurfaceState();
}

class _WebSurfaceState extends State<WebSurface> {
  Uint8List? _frozen;

  @override
  void initState() {
    super.initState();
    if (!widget.live) unawaited(_freeze());
  }

  @override
  void didUpdateWidget(WebSurface old) {
    super.didUpdateWidget(old);
    // Ao sair do ao vivo, tira a foto antes que a vista nativa suma; a foto
    // anterior fica na tela até a nova chegar.
    if (old.live && !widget.live) unawaited(_freeze());
  }

  Future<void> _freeze() async {
    final image = await widget.controller.capture();
    if (!mounted || image == null) return;
    setState(() => _frozen = image);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.live) return widget.controller.buildView(context);
    final frozen = _frozen;
    if (frozen == null) return const SizedBox.expand();
    return Image.memory(frozen, fit: BoxFit.fill, gaplessPlayback: true);
  }
}
