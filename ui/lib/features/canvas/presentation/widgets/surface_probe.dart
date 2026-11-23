import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/adapters/png_file.dart';
import '../../../../core/domain/entities/workbench_node.dart';
import '../../../node/card/presentation/widgets/card_frame.dart';
import '../../domain/entities/canvas_probe.dart';
import '../cubit/canvas_cubit.dart';

/// O canvas respondendo `/geometry` e `/shot`: a geometria sai da vista e dos
/// frames; a imagem de um card, do `RepaintBoundary` dele.
class SurfaceProbe implements CanvasProbe {
  SurfaceProbe({
    required this.workbenchId,
    required this.state,
    required this.canvasBox,
    required this.cardKeys,
    required this.pixelRatio,
    this.nativeCapture,
  });

  @override
  final String workbenchId;
  final CanvasState Function() state;

  /// A caixa do canvas, para saber onde ele cai na área de conteúdo da janela.
  final RenderBox? Function() canvasBox;
  final Map<String, GlobalKey> cardKeys;
  final double Function() pixelRatio;

  /// A página nativa (web) não sai no `toImage`: quem a conhece devolve a
  /// captura dela, e ela entra no corpo do card.
  final Future<Uint8List?> Function(String cardId)? nativeCapture;

  @override
  Map<String, Object?> geometry(WindowFrame window, {String mode = 'canvas'}) {
    final box = canvasBox();
    final current = state();
    return canvasGeometry(
      workbenchId: workbenchId,
      viewport: current.viewport,
      cards: current.cards,
      origin: box == null ? Offset.zero : box.localToGlobal(Offset.zero),
      size: box?.size ?? current.viewport.size,
      window: window,
      headerHeight: CardFrame.headerHeightOf,
      mode: mode,
    );
  }

  @override
  Future<String> snapshot(String cardId, String file) async {
    try {
      final boundary = cardKeys[cardId]?.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        return 'erro: nó "$cardId" não encontrado';
      }
      final ratio = pixelRatio();
      var image = await boundary.toImage(pixelRatio: ratio);
      final native = await nativeCapture?.call(cardId);
      if (native != null) {
        final kind = state().cards.firstWhere((c) => c.id == cardId).kind;
        image = await _withNative(image, native, kind);
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return 'erro: não consegui gerar a imagem';
      await writePng(file, bytes.buffer.asUint8List());
      return file;
    } on Object catch (error) {
      return 'erro: $error';
    }
  }

  /// A página nativa por cima do corpo do card, que no `toImage` sai vazio.
  Future<ui.Image> _withNative(
    ui.Image card,
    Uint8List png,
    NodeKind kind,
  ) async {
    final codec = await ui.instantiateImageCodec(png);
    final page = (await codec.getNextFrame()).image;
    final ratio = pixelRatio();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(card, Offset.zero, Paint());
    // O corpo começa abaixo do cabeçalho (e da faixa, quando há): o que sobra.
    final body = Rect.fromLTWH(
      1 * ratio,
      CardFrame.headerHeightOf(kind) * ratio,
      card.width - 2 * ratio,
      card.height - (CardFrame.headerHeightOf(kind) + 1) * ratio,
    );
    canvas.drawImageRect(
      page,
      Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
      body,
      Paint()..filterQuality = FilterQuality.medium,
    );
    return recorder.endRecording().toImage(card.width, card.height);
  }
}
