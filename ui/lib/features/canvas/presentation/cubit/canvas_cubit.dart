import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_viewport.dart';
import '../../domain/entities/edge_layout.dart';
import '../../domain/entities/edge_link.dart';
import '../../domain/errors/canvas_error.dart';
import '../../domain/repository/canvas_repository.dart';
import '../../domain/usecase/edit_links.dart';
import '../../domain/usecase/remove_node.dart';
import '../../domain/usecase/save_frames.dart';
import '../../domain/usecase/set_ui_focus.dart';
import '../../domain/usecase/watch_canvas.dart';
import 'canvas_memory.dart';

part 'canvas_state.dart';

/// Um cubit por canvas (uma bancada). É dono da assinatura do core: abre ao
/// nascer e cancela no `close()`. Todos os pontos que entram aqui estão em
/// pixels da janela do canvas; a conversão para o documento é da vista.
class CanvasCubit extends Cubit<CanvasState> {
  CanvasCubit({
    required this.workbenchId,
    required WatchCanvas watch,
    required this._saveFrames,
    required this._links,
    required this._removeNode,
    required this._setFocus,
    this.visibleInsets = const EdgeInsets.fromLTRB(0, defaultTopInset, 0, 0),
    CanvasMemory? memory,
  }) : _memory = memory,
       super(
         CanvasIdle(
           viewport: memory?.view(workbenchId) ?? const CanvasViewport(),
         ),
       ) {
    // Já esteve na tela: volta onde estava, sem reenquadrar.
    _needsFit = memory?.view(workbenchId) == null;
    _subscription = watch(workbenchId).listen(_onSnapshot);
  }

  final CanvasMemory? _memory;

  /// O que cobre o canvas por cima: as barras de ação e de informação. Enquadrar
  /// usa só o que sobra.
  static const defaultTopInset = 108.0;

  final String workbenchId;
  final SaveFrames _saveFrames;
  final EditLinks _links;
  final RemoveNode _removeNode;
  final SetUiFocus _setFocus;
  String? _focusedNode;

  /// Área coberta por barras e barra lateral flutuantes; enquadrar usa só o que
  /// sobra.
  EdgeInsets visibleInsets;

  /// A barra lateral flutuante cobre [width] à esquerda. As barras do alto
  /// ficam como estão.
  void setSidebarInset(double width) {
    visibleInsets = EdgeInsets.fromLTRB(
      width,
      visibleInsets.top,
      visibleInsets.right,
      visibleInsets.bottom,
    );
  }

  StreamSubscription<CanvasSnapshot>? _subscription;
  Timer? _settleTimer;
  final _motion = StreamController<bool>.broadcast();

  /// `true` quando a vista ou um card se mexe; `false` quando assenta.
  Stream<bool> get motion => _motion.stream;
  Timer? _windowTimer;

  /// Quanto esperar parado antes de avisar o core do tamanho novo da janela.
  static const windowDelay = Duration(milliseconds: 300);

  /// Quanto o canvas espera parado antes de dizer que parou.
  static const settleDelay = Duration(milliseconds: 250);

  /// A bancada abre enquadrada: em (0,0) você caía num canto vazio e tinha de
  /// procurar os cards.
  late bool _needsFit;
  var _framesDirty = false;

  ({Offset mouse, Offset origin})? _panAnchor;
  ({String id, Offset offset})? _dragging;

  /// A mesma fase de agora, com os cards, as ligações ou a vista novos.
  CanvasState _with({
    List<CanvasCard>? cards,
    List<EdgeLink>? links,
    CanvasViewport? viewport,
  }) {
    final c = cards ?? state.cards;
    final l = links ?? state.links;
    final v = viewport ?? state.viewport;
    return switch (state) {
      CanvasIdle() => CanvasIdle(cards: c, links: l, viewport: v),
      CanvasPanning() => CanvasPanning(cards: c, links: l, viewport: v),
      CanvasDraggingCard(:final cardId) => CanvasDraggingCard(
        cardId: cardId,
        cards: c,
        links: l,
        viewport: v,
      ),
      CanvasLinking(:final pending) => CanvasLinking(
        pending: pending,
        cards: c,
        links: l,
        viewport: v,
      ),
      CanvasLinkHovered(:final link) => CanvasLinkHovered(
        link: link,
        cards: c,
        links: l,
        viewport: v,
      ),
    };
  }

  /// Nada mais na mão.
  CanvasIdle get _idle => CanvasIdle(
    cards: state.cards,
    links: state.links,
    viewport: state.viewport,
  );

  // ---- estado vindo do core ------------------------------------------------

  void _onSnapshot(CanvasSnapshot snapshot) {
    // Gesto em curso (arrasto de card, pan que deslocou o mundo, frames ainda
    // não gravados): os frames locais valem mais que os do core, senão os
    // cards pulam para onde o arquivo ainda os tem.
    final local = {for (final c in state.cards) c.id: c};
    final gesture = _dragging != null || _panAnchor != null || _framesDirty;
    final cards = [
      for (final card in snapshot.cards)
        if (gesture && local.containsKey(card.id))
          card.copyWith(frame: local[card.id]!.frame)
        else
          card,
    ];
    var viewport = state.viewport.growForNodes(cards.map((c) => c.frame));
    viewport = viewport.copyWith(
      origin: viewport.clampedOrigin(viewport.origin),
    );
    final current = state;
    if (current is CanvasLinkHovered) {
      // O realce guarda a ligação do arquivo anterior com os flags velhos:
      // resolve de novo contra a lista nova, ou some se o par saiu.
      final link = snapshot.links.where((l) => l == current.link).firstOrNull;
      emit(
        link == null
            ? CanvasIdle(
                cards: cards,
                links: snapshot.links,
                viewport: viewport,
              )
            : CanvasLinkHovered(
                link: link,
                cards: cards,
                links: snapshot.links,
                viewport: viewport,
              ),
      );
    } else {
      emit(_with(cards: cards, links: snapshot.links, viewport: viewport));
    }
    if (_needsFit && cards.isNotEmpty) _fitIfSized();
  }

  // ---- janela e vista ------------------------------------------------------

  void resize(Size size) {
    if (size == state.viewport.size) return;
    emit(
      _with(
        viewport: state.viewport.resized(size, state.cards.map((c) => c.frame)),
      ),
    );
    if (_needsFit && state.cards.isNotEmpty) _fitIfSized();
    _resendWindowLater();
  }

  /// O core usa o tamanho do canvas para dar o frame padrão a quem nasce sem:
  /// quando a janela muda com um nó em foco, repete o foco com o tamanho novo
  /// (depois que o arrasto da borda para).
  void _resendWindowLater() {
    if (_focusedNode == null) return;
    _windowTimer?.cancel();
    _windowTimer = Timer(windowDelay, () {
      final id = _focusedNode;
      if (isClosed || id == null) return;
      _sendFocus(id);
    });
  }

  void _sendFocus(String id) {
    final size = state.viewport.size;
    _fire(
      _setFocus(
        appActive: true,
        workbenchId: workbenchId,
        nodeId: id,
        window: size.isEmpty ? null : size,
      ),
    );
  }

  void _fitIfSized() {
    if (state.viewport.size.isEmpty) return;
    _needsFit = false;
    fitAll();
  }

  /// O que está à vista, no espaço do canvas (sem a faixa da barra de ações
  /// nem a barra lateral por cima): onde nasce um nó sem desenho.
  Rect get visibleDocument {
    final area = _visibleArea;
    return Rect.fromPoints(
      state.viewport.toDocument(area.topLeft),
      state.viewport.toDocument(area.bottomRight),
    );
  }

  Rect get _visibleArea {
    final size = state.viewport.size;
    return Rect.fromLTRB(
      visibleInsets.left,
      visibleInsets.top,
      math.max(visibleInsets.left, size.width - visibleInsets.right),
      math.max(visibleInsets.top, size.height - visibleInsets.bottom),
    );
  }

  /// Enquadra todos os nós na área visível: zoom para caberem, centrados. É o
  /// botão da barra quando você se perde no canvas.
  void fitAll() {
    final union = state.union;
    if (union == null) return;
    _view(
      state.viewport.fit(union, _visibleArea, state.cards.map((c) => c.frame)),
    );
  }

  Iterable<Rect> get _frames => state.cards.map((c) => c.frame);

  void _view(CanvasViewport viewport) {
    emit(_with(viewport: viewport));
    _settleLater();
  }

  /// A vista ou um card se mexeu: some o "ao vivo" e agenda a volta.
  void _settleLater() {
    if (!_motion.isClosed) _motion.add(true);
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, () {
      if (!isClosed && state is! CanvasPanning && _dragging == null) {
        _motion.add(false);
      }
    });
  }

  // ---- zoom ----------------------------------------------------------------

  void wheelZoom(double delta, Offset anchor, {bool precise = true}) =>
      _view(state.viewport.wheelZoom(delta, anchor, _frames, precise: precise));

  /// Pinça do trackpad: [ratio] é a escala acumulada do gesto sobre o zoom de
  /// quando ele começou ([from]).
  void pinchZoom(double from, double ratio, Offset anchor) =>
      _view(state.viewport.zoomAt(from * ratio, anchor, _frames));

  void stepZoom(int direction) =>
      _view(state.viewport.stepZoom(direction, _frames));

  void resetZoom() => _view(state.viewport.zoomTo(1, _frames));

  // ---- pan -----------------------------------------------------------------

  void beginPan(Offset point) {
    _panAnchor = (mouse: point, origin: state.viewport.origin);
    emit(
      CanvasPanning(
        cards: state.cards,
        links: state.links,
        viewport: state.viewport,
      ),
    );
  }

  void updatePan(Offset point) {
    final anchor = _panAnchor;
    if (anchor == null) return;
    final target = anchor.origin - (point - anchor.mouse) / state.viewport.zoom;
    final moved = state.viewport.panTo(target);
    if (moved.shift != Offset.zero) {
      // O mundo andou junto com a vista: a âncora também, senão a vista
      // descola do cursor.
      _panAnchor = (mouse: anchor.mouse, origin: anchor.origin + moved.shift);
      _shiftCards(moved.shift);
    }
    _view(moved.viewport);
  }

  void endPan() {
    if (_panAnchor == null) return;
    _panAnchor = null;
    emit(_idle);
    _flushFrames();
  }

  /// A roda do trackpad: [delta] em pixels de tela, positivo = vista andando
  /// para a direita/embaixo. Não abre espaço à esquerda: lá a vista só para.
  void scroll(Offset delta) {
    final view = state.viewport;
    final target = view.origin + delta / view.zoom;
    _view(
      view
          .panTo(
            target,
            openSpace: false,
            lookAhead: Offset(
              delta.dx > 0 ? CanvasViewport.wheelChunk : 0,
              delta.dy > 0 ? CanvasViewport.wheelChunk : 0,
            ),
          )
          .viewport,
    );
  }

  /// Dois dedos no trackpad: o conteúdo acompanha os dedos.
  void trackpadPan(Offset delta) => scroll(-delta);

  // ---- cards ---------------------------------------------------------------

  void _shiftCards(Offset shift) {
    emit(
      _with(
        cards: [
          for (final card in state.cards)
            card.copyWith(frame: card.frame.shift(shift)),
        ],
      ),
    );
    _framesDirty = true;
  }

  void _setFrame(String id, Rect frame) {
    emit(
      CanvasDraggingCard(
        cardId: id,
        cards: [
          for (final card in state.cards)
            if (card.id == id) card.copyWith(frame: frame) else card,
        ],
        links: state.links,
        viewport: state.viewport,
      ),
    );
    _framesDirty = true;
    _settleLater();
  }

  CanvasCard? _card(String id) =>
      state.cards.where((c) => c.id == id).firstOrNull;

  void beginCardDrag(String id, Offset point) {
    final card = _card(id);
    if (card == null) return;
    final doc = state.viewport.toDocument(point);
    _dragging = (id: id, offset: doc - card.frame.topLeft);
  }

  /// Arrastar pelo cabeçalho move o nó no espaço do canvas. Em vez de barrar o
  /// nó na borda esquerda/topo, o canvas desloca o mundo e abre espaço.
  void dragCard(Offset point) {
    final drag = _dragging;
    final card = drag == null ? null : _card(drag.id);
    if (drag == null || card == null) return;
    final doc = state.viewport.toDocument(point);
    var desired = Offset(
      (doc.dx - drag.offset.dx).roundToDouble(),
      (doc.dy - drag.offset.dy).roundToDouble(),
    );
    if (desired.dx < 0 || desired.dy < 0) {
      final opened = state.viewport.makeSpace(
        Size(math.max(0, -desired.dx), math.max(0, -desired.dy)),
      );
      if (opened.shift != Offset.zero) {
        _shiftCards(opened.shift);
        _view(opened.viewport);
      }
      // O deslocamento entra igualmente no nó e na conversão do cursor, então
      // o `offset` do arrasto não precisa de correção.
      final shifted = state.viewport.toDocument(point);
      desired = Offset(
        math.max(0, (shifted.dx - drag.offset.dx).roundToDouble()),
        math.max(0, (shifted.dy - drag.offset.dy).roundToDouble()),
      );
    }
    final moved = _card(drag.id)!;
    _setFrame(drag.id, desired & moved.frame.size);
  }

  /// Alça de resize no canto inferior direito. [delta] em pixels de tela: o nó
  /// vive num documento magnificado, e 10px de mouse viram 20 unidades a 0.5x.
  void resizeCard(String id, Offset delta) {
    final card = _card(id);
    if (card == null) return;
    final zoom = state.viewport.zoom;
    final size = Size(
      math.max(
        CanvasCard.minSize.width,
        (card.frame.width + delta.dx / zoom).roundToDouble(),
      ),
      math.max(
        CanvasCard.minSize.height,
        (card.frame.height + delta.dy / zoom).roundToDouble(),
      ),
    );
    _setFrame(id, card.frame.topLeft & size);
  }

  /// Fim do arrasto ou do resize: só aqui o core grava, para não reescrever o
  /// arquivo a cada pixel. O documento cresce para o que ficou perto da borda.
  void endCardGesture() {
    _dragging = null;
    if (state is CanvasDraggingCard) emit(_idle);
    _view(state.viewport.growForNodes(_frames));
    _flushFrames();
  }

  void _flushFrames() {
    if (!_framesDirty) return;
    _framesDirty = false;
    unawaited(_fire(_saveFrames(workbenchId, state.frames)));
  }

  Future<void> removeCard(String id) => _fire(_removeNode(workbenchId, id));

  // ---- ligações ------------------------------------------------------------

  /// Realce da ligação sob o cursor. Quem chama só chama no cursor: com a
  /// ferramenta armada o clique é de criação. Com a mão ocupada (pan, arrasto,
  /// ligação nova), não há realce.
  void hoverAt(Offset point) {
    final current = state;
    final hovered = current is CanvasLinkHovered ? current.link : null;
    if (current is! CanvasIdle && current is! CanvasLinkHovered) return;
    final link = EdgeLayout.linkNear(
      screenPoint: point,
      links: state.links,
      frames: state.frames,
      viewport: state.viewport,
      hovered: hovered,
    );
    if (link == hovered) return;
    emit(
      link == null
          ? _idle
          : CanvasLinkHovered(
              link: link,
              cards: state.cards,
              links: state.links,
              viewport: state.viewport,
            ),
    );
  }

  void clearHover() {
    if (state is CanvasLinkHovered) emit(_idle);
  }

  Future<void> cycleDirection(EdgeLink link) =>
      _fire(_links.cycleDirection(workbenchId, link));

  Future<void> removeLink(EdgeLink link) =>
      _fire(_links.remove(workbenchId, link));

  Future<void> setLimit(EdgeLink link, int? maxSends) =>
      _fire(_links.setLimit(workbenchId, link, maxSends));

  /// Arrasto saindo do `+` de um nó: a ponta segue o mouse.
  void portDrag(String from, Offset point) => emit(
    CanvasLinking(
      pending: PendingLink(from: from, to: state.viewport.toDocument(point)),
      cards: state.cards,
      links: state.links,
      viewport: state.viewport,
    ),
  );

  /// O gesto foi cancelado pelo sistema: a linha tracejada some.
  void portCancel() {
    if (state is CanvasLinking) emit(_idle);
  }

  /// Soltou: se caiu sobre um nó a que o de origem pode se ligar (a lista é do
  /// core, `linkable`), pede a ligação. Ligado, laço ou sem porta, quem recusa
  /// é o core.
  Future<void> portRelease(String from, Offset point) async {
    if (state is CanvasLinking) emit(_idle);
    final doc = state.viewport.toDocument(point);
    final source = state.cards.where((c) => c.id == from).firstOrNull;
    final target = state.cards
        .where((c) => c.id != from && c.frame.contains(doc))
        .firstOrNull;
    if (source == null || target == null) return;
    if (!source.linkable.contains(target.id)) return;
    await _fire(_links.create(workbenchId, from, target.id));
  }

  // ---- foco ----------------------------------------------------------------

  /// O foco de teclado entrou neste card (clique nele ou no terminal). O core
  /// usa para decidir notificação e o que é tecla do usuário; só avisa quando o
  /// nó muda.
  void focusNode(String id) {
    if (_focusedNode == id) return;
    _focusedNode = id;
    _sendFocus(id);
  }

  // ---- utilidades ----------------------------------------------------------

  /// Comando é "mande e siga": se o core recusar, o próximo estado que ele
  /// mandar já corrige a tela.
  Future<void> _fire(Future<void> future) =>
      future.catchError((_) {}, test: (error) => error is CanvasError);

  @override
  Future<void> close() async {
    _memory?.keepView(workbenchId, state.viewport);
    _settleTimer?.cancel();
    _windowTimer?.cancel();
    await _subscription?.cancel();
    await _motion.close();
    return super.close();
  }
}
