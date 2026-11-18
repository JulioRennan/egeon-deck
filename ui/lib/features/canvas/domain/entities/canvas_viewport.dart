import 'dart:math' as math;
import 'dart:ui';

/// O que a vista mostra do documento do canvas: zoom, origem (canto
/// superior esquerdo da vista, em coordenadas do documento) e tamanho do
/// documento. É estado passageiro de tela — o core só guarda os frames dos
/// cards.
///
/// Imutável: cada gesto devolve a vista seguinte. As operações que deslocam o
/// mundo (`makeSpace`) devolvem também o quanto abriram, para quem guarda os
/// cards deslocá-los pelo mesmo tanto.
class CanvasViewport {
  const CanvasViewport({
    this.zoom = 1,
    this.rawZoom = 1,
    this.origin = Offset.zero,
    this.document = minDocumentSize,
    this.size = Size.zero,
  });

  /// Passos do zoom: botões e atalhos andam por eles, e a detente gruda neles.
  static const zoomSteps = <double>[
    0.25, 0.4, 0.5, 0.67, 0.8, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, //
  ];
  static const minDocumentSize = Size(6000, 4000);
  static const documentMargin = 1200.0;

  /// Teto para o documento não crescer sem fim em pans longos.
  static const maxDocumentSize = 120000.0;

  /// Folga de enquadrar: nunca cola nas barras flutuantes.
  static const fitMargin = 60.0;

  /// Em blocos: crescer a cada pixel redesenharia as arestas a cada evento.
  static const wheelChunk = 512.0;

  static const _epsilon = 0.0001;

  final double zoom;

  /// Zoom pedido antes da detente. O gesto continua a partir daqui: partindo do
  /// valor já grudado, cada evento cairia de novo dentro da janela de captura e
  /// a roda ficaria presa no passo.
  final double rawZoom;
  final Offset origin;
  final Size document;

  /// Tamanho da janela do canvas, em pixels de tela.
  final Size size;

  static double get minZoom => zoomSteps.first;
  static double get maxZoom => zoomSteps.last;

  /// Quanto do documento a vista cobre, em unidades de documento.
  Size get visible => Size(size.width / zoom, size.height / zoom);

  CanvasViewport copyWith({
    double? zoom,
    double? rawZoom,
    Offset? origin,
    Size? document,
    Size? size,
  }) => CanvasViewport(
    zoom: zoom ?? this.zoom,
    rawZoom: rawZoom ?? this.rawZoom,
    origin: origin ?? this.origin,
    document: document ?? this.document,
    size: size ?? this.size,
  );

  /// Zoom que faz um retângulo caber num viewport com margem. Nunca passa de
  /// 100%: dois cards pequenos não devem virar terminais gigantes — enquadrar é
  /// achar, não ampliar.
  static double fitZoom(
    Rect content,
    Size viewport, {
    double margin = fitMargin,
  }) {
    final usableWidth = viewport.width - 2 * margin;
    final usableHeight = viewport.height - 2 * margin;
    if (content.width <= 0 ||
        content.height <= 0 ||
        usableWidth <= 0 ||
        usableHeight <= 0) {
      return 1;
    }
    final scale = math.min(
      math.min(usableWidth / content.width, usableHeight / content.height),
      1.0,
    );
    return scale.clamp(minZoom, maxZoom);
  }

  /// Gruda no passo mais próximo dentro de 3%.
  ///
  /// O zoom da roda é exponencial e nunca cai em 1.0 exato — 112%, 78%, 141%.
  /// Fora dos passos redondos o canvas some do lugar onde os números são
  /// legíveis, e 100% é o único ponto em que ninguém reamostra nada.
  static double detente(double value) {
    var nearest = zoomSteps.first;
    for (final step in zoomSteps) {
      if ((step - value).abs() < (nearest - value).abs()) nearest = step;
    }
    return (nearest - value).abs() <= nearest * 0.03 ? nearest : value;
  }

  /// Origem presa dentro do documento: a vista nunca escapa dele.
  Offset clampedOrigin(Offset origin) {
    final view = visible;
    return Offset(
      origin.dx.clamp(0, math.max(0, document.width - view.width)).toDouble(),
      origin.dy.clamp(0, math.max(0, document.height - view.height)).toDouble(),
    );
  }

  /// Cresce o documento até [atLeast]; nunca encolhe. No teto o canvas volta a
  /// ter borda dura — diferente de [makeSpace], que precisa recusar inteiro para
  /// não deslocar os nós pela metade.
  CanvasViewport growDocument(Size atLeast) {
    final width = math.min(
      math.max(atLeast.width.ceilToDouble(), document.width),
      maxDocumentSize,
    );
    final height = math.min(
      math.max(atLeast.height.ceilToDouble(), document.height),
      maxDocumentSize,
    );
    if (width <= document.width && height <= document.height) return this;
    return copyWith(document: Size(width, height));
  }

  /// Abre espaço à direita e embaixo: o documento cresce até uma vista com
  /// origem em [origin] caber inteira. É o par de [makeSpace], e mais barato —
  /// o canto (0,0) fica onde está, então nó nenhum se desloca.
  CanvasViewport extendDocument(Offset toShow) {
    final view = visible;
    return growDocument(Size(toShow.dx + view.width, toShow.dy + view.height));
  }

  /// O documento era fixo, e isso trava o pan de dois jeitos: um nó arrastado
  /// para perto da borda não tem para onde continuar, e em zoom out a vista
  /// passa a mostrar mais unidades do que o documento tem — aí o scroll
  /// simplesmente não anda. Recebe o zoom de destino quando o chamador está no
  /// meio de uma troca de escala.
  CanvasViewport growForNodes(Iterable<Rect> frames, {double? zoom}) {
    var width = minDocumentSize.width;
    var height = minDocumentSize.height;
    for (final frame in frames) {
      width = math.max(width, frame.right + documentMargin);
      height = math.max(height, frame.bottom + documentMargin);
    }
    final scale = zoom ?? this.zoom;
    if (scale <= 0) return this;
    width = math.max(width, size.width / scale * 1.5);
    height = math.max(height, size.height / scale * 1.5);
    return growDocument(Size(width, height));
  }

  /// Abre espaço à esquerda e no topo deslocando o mundo inteiro.
  ///
  /// O documento tem canto em (0,0) e a origem não vai a negativo, então
  /// "infinito à esquerda" não vem de permitir coordenada negativa — vem de
  /// mover todos os nós e a vista pelo mesmo tanto. Na tela nada se move, e
  /// quem estava na borda ganha para onde ir. [shift] é o que de fato abriu:
  /// zero quando o teto recusa.
  ({CanvasViewport viewport, Offset shift}) makeSpace(Size request) {
    final dx = math.max(0, request.width.roundToDouble());
    final dy = math.max(0, request.height.roundToDouble());
    if ((dx == 0 && dy == 0) ||
        document.width + dx > maxDocumentSize ||
        document.height + dy > maxDocumentSize) {
      return (viewport: this, shift: Offset.zero);
    }
    final shift = Offset(dx.toDouble(), dy.toDouble());
    return (
      viewport: copyWith(
        document: Size(document.width + dx, document.height + dy),
        origin: origin + shift,
      ),
      shift: shift,
    );
  }

  /// Leva a origem para [target]. Navegar além da borda esquerda/topo abre
  /// espaço (se [openSpace]) e além da direita/embaixo faz o documento crescer,
  /// senão o canvas seria infinito para mover nó e finito para olhar. O
  /// [shift] devolvido é o deslocamento que os cards sofreram.
  ///
  /// [lookAhead] é folga de crescimento só para a direita/embaixo: a roda cresce
  /// em blocos, antes de a vista chegar na borda.
  ({CanvasViewport viewport, Offset shift}) panTo(
    Offset target, {
    bool openSpace = true,
    Offset lookAhead = Offset.zero,
  }) {
    var view = this;
    var shift = Offset.zero;
    var goal = target;
    if (openSpace && (goal.dx < 0 || goal.dy < 0)) {
      final opened = view.makeSpace(
        Size(math.max(0, -goal.dx), math.max(0, -goal.dy)),
      );
      view = opened.viewport;
      shift = opened.shift;
      // O teto pode ter recusado: só compensa pelo que de fato abriu, senão a
      // vista descola do cursor.
      goal += shift;
    }
    view = view.extendDocument(goal + lookAhead);
    return (
      viewport: view.copyWith(origin: view.clampedOrigin(goal)),
      shift: shift,
    );
  }

  /// A vista com [size] novo. Em janela maior o documento precisa cobrir o
  /// que ela passa a mostrar.
  CanvasViewport resized(Size size, Iterable<Rect> frames) =>
      copyWith(size: size)
          .growForNodes(frames)
          .copyWith(origin: copyWith(size: size).clampedOrigin(origin));

  /// Zoom que deixa um ponto da tela ([anchor], em pixels da janela do canvas)
  /// parado no lugar. Medir o ponto antes e depois da troca de escala e
  /// corrigir a origem pela diferença é o que de fato ancora.
  CanvasViewport zoomAt(double value, Offset anchor, Iterable<Rect> frames) {
    final clamped = value.clamp(minZoom, maxZoom).toDouble();
    // Antes da guarda: preso na detente, o zoom não muda e sair dela depende
    // justamente de o valor cru continuar andando.
    final remembered = copyWith(rawZoom: clamped);
    final target = detente(clamped);
    if ((target - zoom).abs() <= _epsilon) return remembered;

    // Crescer antes: em zoom out a vista passa a cobrir mais unidades do que o
    // documento tem, e a origem seria presa — o que sozinho já desloca a vista.
    final grown = remembered.growForNodes(frames, zoom: target);
    final docPoint = origin + anchor / zoom;
    final scaled = grown.copyWith(zoom: target);
    final moved = docPoint - anchor / target;
    return scaled.copyWith(origin: scaled.clampedOrigin(moved));
  }

  /// Zoom da roda com ⌘: parte do valor cru enquanto o zoom for dele — é assim
  /// que a roda atravessa a detente. Se o zoom mudou por fora (pinça, ⌘0,
  /// botão), o cru está velho e quem manda é o zoom.
  ///
  /// [delta] é o sentido já normalizado (positivo = vista se afasta do mundo,
  /// como deslizar para baixo); a roda entrega passos grandes e discretos, o
  /// trackpad valores contínuos, por isso [precise].
  CanvasViewport wheelZoom(
    double delta,
    Offset anchor,
    Iterable<Rect> frames, {
    bool precise = true,
  }) {
    final scaled = precise ? delta : delta * 6;
    if (scaled == 0) return this;
    final base = (detente(rawZoom) - zoom).abs() < _epsilon ? rawZoom : zoom;
    // Exponencial: o passo é proporcional ao zoom atual, então a sensação é a
    // mesma em 0.3x e em 2x.
    return zoomAt(base * math.pow(1.0025, -scaled), anchor, frames);
  }

  /// Passo dos botões `+` e `−`: próximo passo da lista, ancorado no centro.
  CanvasViewport stepZoom(int direction, Iterable<Rect> frames) {
    double? next;
    if (direction > 0) {
      for (final step in zoomSteps) {
        if (step > zoom + 0.001) {
          next = step;
          break;
        }
      }
    } else {
      for (final step in zoomSteps.reversed) {
        if (step < zoom - 0.001) {
          next = step;
          break;
        }
      }
    }
    return zoomTo(next ?? zoom, frames);
  }

  /// Zoom ancorado no centro da vista: o que está no meio da tela continua no
  /// meio.
  CanvasViewport zoomTo(double value, Iterable<Rect> frames) =>
      zoomAt(value, Offset(size.width / 2, size.height / 2), frames);

  /// Enquadra [content] na [area] visível (em pixels da janela, sem as barras
  /// flutuantes): zoom para caber, centrado. É onde a bancada abre — em (0,0)
  /// você caía num canto vazio e tinha de procurar os cards.
  CanvasViewport fit(Rect content, Rect area, Iterable<Rect> frames) {
    if (size.isEmpty || area.width <= 0 || area.height <= 0) return this;
    final target = fitZoom(content, area.size);
    final grown = growForNodes(
      frames,
      zoom: target,
    ).copyWith(zoom: target, rawZoom: target);
    final origin = Offset(
      content.center.dx - area.center.dx / target,
      content.center.dy - area.center.dy / target,
    );
    return grown.copyWith(origin: grown.clampedOrigin(origin));
  }

  /// Ponto da janela → ponto do documento.
  Offset toDocument(Offset screen) => origin + screen / zoom;

  /// Ponto do documento → ponto da janela.
  Offset toScreen(Offset doc) => (doc - origin) * zoom;
}
