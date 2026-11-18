import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../../../node/card/presentation/widgets/card_accent.dart';
import '../../../node/card/presentation/widgets/card_frame.dart';
import '../../../node/card/presentation/widgets/card_status.dart';
import '../../../node/card/presentation/widgets/card_motion.dart';
import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_probe.dart';
import '../../domain/entities/canvas_tool.dart';
import '../../domain/entities/edge_link.dart';
import '../cubit/canvas_commands.dart';
import '../cubit/canvas_cubit.dart';
import 'canvas_glow.dart';
import 'canvas_grid.dart';
import 'canvas_toolbar.dart';
import 'edge_controls.dart';
import 'edge_painter.dart';
import 'surface_probe.dart';
import 'tool_overlay.dart';

/// O corpo de um card, por tipo de nó. Quem compõe a tela decide o que mostrar
/// (terminal, web, fila): o canvas só posiciona.
typedef CardBodyBuilder = Widget Function(
  BuildContext context,
  CanvasCard card,
);

/// A faixa extra do cabeçalho de um card (agente: modelo e esforço), ou nulo.
typedef CardAccessoryBuilder = Widget? Function(
  BuildContext context,
  CanvasCard card,
);

/// A tela do canvas: grid, cards numa transformação de zoom e pan, arestas
/// atrás deles e as barras flutuantes por cima.
///
/// O pan e o zoom não são de uma `ScrollView`: o documento é infinito para os
/// quatro lados, e a vista é o que o cubit diz. Cada gesto vira uma chamada
/// ao cubit, em pixels da janela.
class CanvasSurface extends StatefulWidget {
  const CanvasSurface({
    required this.bodyBuilder,
    this.accessoryBuilder,
    this.glow,
    this.componentNames = const [],
    this.onConfigureTerminal,
    this.onEditLimit,
    this.onRequestClose,
    this.probes,
    this.nativeCapture,
    this.commands,
    this.sidebarInset = 0,
    super.key,
  });

  final CardBodyBuilder bodyBuilder;
  final CardAccessoryBuilder? accessoryBuilder;

  /// A cor da bancada, esmaecida por dentro da borda (ADR-086).
  final Color? glow;
  final List<String> componentNames;
  final VoidCallback? onConfigureTerminal;
  final ValueChanged<EdgeLink>? onEditLimit;

  /// Clique no X de um nó. Confirmar é de quem escuta; sem ouvinte, remove.
  final ValueChanged<CanvasCard>? onRequestClose;

  /// Os comandos que o menu da casca chama (ferramentas e zoom).
  final CanvasCommands? commands;

  /// O quanto da esquerda a barra lateral flutuante cobre. Enquadrar usa só o
  /// que sobra: a largura é lida na hora, recolhida ou aberta.
  final double sidebarInset;

  /// Onde este canvas se registra para `/geometry` e `/shot` o acharem.
  final CanvasProbeRegistry? probes;

  /// A captura da página nativa de um card (web), que o `toImage` não pega.
  final Future<Uint8List?> Function(String cardId)? nativeCapture;

  @override
  State<CanvasSurface> createState() => _CanvasSurfaceState();
}

class _CanvasSurfaceState extends State<CanvasSurface> {
  int? _panPointer;
  double _pinchFrom = 1;

  /// Uma chave por card, para fotografar o card inteiro (`/shot`).
  final _cardKeys = <String, GlobalKey>{};
  SurfaceProbe? _probe;

  /// O cubit a que os comandos do menu foram ligados: guardado, porque no
  /// `dispose` o contexto já não serve para lê-lo.
  CanvasCubit? _attached;

  @override
  void initState() {
    super.initState();
    final cubit = _attached = context.read<CanvasCubit>();
    cubit.setSidebarInset(widget.sidebarInset);
    widget.commands?.attach(cubit);
    final registry = widget.probes;
    if (registry == null) return;
    _probe = SurfaceProbe(
      workbenchId: cubit.workbenchId,
      state: () => cubit.state,
      canvasBox: () =>
          mounted ? context.findRenderObject() as RenderBox? : null,
      cardKeys: _cardKeys,
      pixelRatio: () => View.of(context).devicePixelRatio,
      nativeCapture: widget.nativeCapture,
    );
    registry.register(_probe!);
  }

  @override
  void didUpdateWidget(CanvasSurface old) {
    super.didUpdateWidget(old);
    if (old.sidebarInset != widget.sidebarInset) {
      _attached?.setSidebarInset(widget.sidebarInset);
    }
  }

  @override
  void dispose() {
    final attached = _attached;
    if (attached != null) widget.commands?.detach(attached);
    final probe = _probe;
    if (probe != null) widget.probes?.unregister(probe);
    super.dispose();
  }

  CanvasCubit get _cubit => context.read<CanvasCubit>();

  Offset _local(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  void _beginPan(PointerDownEvent event) {
    if (_panPointer != null) return;
    _panPointer = event.pointer;
    _cubit.beginPan(event.localPosition);
  }

  void _endPan(PointerEvent event) {
    if (event.pointer != _panPointer) return;
    _panPointer = null;
    _cubit.endPan();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cubit.resize(size);
      });
      return BlocBuilder<CanvasCubit, CanvasState>(
        builder: (context, state) => _surface(context, state),
      );
    },
  );

  Widget _surface(BuildContext context, CanvasState state) {
    final view = state.viewport;
    final frames = state.frames;
    return MouseRegion(
      cursor: state.panning ? SystemMouseCursors.grabbing : MouseCursor.defer,
      onHover: (e) => _cubit.hoverAt(e.localPosition),
      onExit: (_) => _cubit.clearHover(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // ⌥ pana de qualquer lugar, inclusive por cima de um nó, e o botão do
        // meio é o gesto de pan que não colide com nada. Modificador é lido do
        // próprio evento e não tem como grudar.
        onPointerDown: (e) {
          final middle = e.buttons == kMiddleMouseButton;
          final alt =
              e.buttons == kPrimaryButton &&
              HardwareKeyboard.instance.isAltPressed;
          if (middle || alt) _beginPan(e);
        },
        onPointerMove: (e) {
          if (e.pointer == _panPointer) _cubit.updatePan(e.localPosition);
        },
        onPointerUp: _endPan,
        onPointerCancel: _endPan,
        onPointerSignal: (event) {
          // ⌘+scroll: zoom ancorado no cursor, como no Figma.
          if (event is PointerScrollEvent &&
              HardwareKeyboard.instance.isMetaPressed) {
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              _cubit.wheelZoom(
                event.scrollDelta.dy,
                event.localPosition,
                // Roda entrega passos grandes e discretos; trackpad, valores
                // contínuos.
                precise: event.kind == PointerDeviceKind.trackpad,
              );
            });
          }
        },
        onPointerPanZoomStart: (_) => _pinchFrom = state.viewport.zoom,
        onPointerPanZoomUpdate: (e) {
          if (e.scale != 1) {
            _cubit.pinchZoom(_pinchFrom, e.scale, e.localPosition);
          }
        },
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: CanvasGrid(viewport: view)),
              Positioned.fill(child: _background(state)),
              Positioned.fill(child: _world(context, state)),
              Positioned.fill(child: CanvasGlow(color: widget.glow)),
              if (state.hovered != null && state.tool == CanvasTool.cursor)
                Positioned.fill(
                  child: EdgeControlsLayer(
                    link: state.hovered!,
                    frames: frames,
                    viewport: view,
                    onCycle: () => _cubit.cycleDirection(state.hovered!),
                    onLimit: () => widget.onEditLimit?.call(state.hovered!),
                    onRemove: () => _cubit.removeLink(state.hovered!),
                  ),
                ),
              // Com ferramenta armada o overlay tapa o canvas para capturar o
              // clique de criação (senão o terminal engoliria); a barra vem por
              // cima dele para continuar clicável.
              if (state.tool != CanvasTool.cursor)
                Positioned.fill(
                  child: ToolOverlay(onPlace: _cubit.placeByGesture),
                ),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: CanvasToolbar(
                    tool: state.tool,
                    zoom: view.zoom,
                    componentNames: widget.componentNames,
                    onSelect: _cubit.selectTool,
                    onZoom: _cubit.stepZoom,
                    onResetZoom: _cubit.resetZoom,
                    onFitAll: _cubit.fitAll,
                    onPickComponent: _cubit.pickComponent,
                    onConfigureTerminal: widget.onConfigureTerminal,
                  ),
                ),
              ),
              if (state.banner != null)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(child: _Banner(state.banner!)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// O fundo recebe o arrasto de pan; os nós ficam por cima e consomem o que é
  /// deles. Rolar a roda aqui também anda a vista.
  Widget _background(CanvasState state) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      if (e.buttons == kPrimaryButton &&
          !HardwareKeyboard.instance.isAltPressed) {
        _beginPan(e);
      }
    },
    onPointerSignal: (event) {
      if (event is PointerScrollEvent &&
          !HardwareKeyboard.instance.isMetaPressed) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          _cubit.scroll(event.scrollDelta);
        });
      }
    },
    onPointerPanZoomUpdate: (e) {
      if (e.scale == 1) _cubit.trackpadPan(e.panDelta);
    },
    child: const SizedBox.expand(),
  );

  Widget _world(BuildContext context, CanvasState state) {
    final view = state.viewport;
    final matrix = Matrix4.diagonal3Values(view.zoom, view.zoom, 1)
      ..translateByDouble(-view.origin.dx, -view.origin.dy, 0, 1);
    // O hit test de cada caixa confere o ponto contra o tamanho DELA: o
    // documento, e não a janela, tem de ser o tamanho da caixa que carrega os
    // cards, senão um card além da janela (em coordenadas de documento) nunca
    // recebe clique. Por isso o `OverflowBox` fica FORA da transformação.
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      minHeight: 0,
      maxWidth: view.document.width,
      maxHeight: view.document.height,
      child: Transform(
        transform: matrix,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: view.document.width,
          height: view.document.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Atrás dos nós: a curva passa por baixo dos cards e some sob
              // eles em vez de riscar o terminal.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: EdgePainter(
                      links: state.links,
                      frames: state.frames,
                      zoom: view.zoom,
                      hovered: state.hovered,
                      pending: state.pending,
                    ),
                  ),
                ),
              ),
              for (final card in state.cards)
                _card(
                  card,
                  live: (view.zoom - 1).abs() < 0.001 && !state.moving,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(CanvasCard card, {required bool live}) => Positioned.fromRect(
    key: ValueKey('card-${card.id}'),
    rect: card.frame,
    // O foco de teclado entrando no card (no terminal, no campo) ou o clique
    // nele avisam o core de quem tem o foco.
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) _cubit.focusNode(card.id);
      },
      child: Listener(
        onPointerDown: (_) => _cubit.focusNode(card.id),
        child: RepaintBoundary(
          key: _cardKeys.putIfAbsent(card.id, GlobalKey.new),
          child: CardFrame(
            id: card.id,
            kind: card.kind,
            title: card.title,
            subtitle: card.subtitle,
            height: card.frame.height,
            linkable: card.port,
            needsAttention: card.activity.needsAttention,
            maestro: card.maestro,
            accent: card.maestro ? CardAccent.maestro : null,
            titleColor: ActivityColors.of(card.activity.tone),
            status: CardStatus(activity: card.activity),
            onDragStart: (p) => _cubit.beginCardDrag(card.id, _local(p)),
            onDrag: (p) => _cubit.dragCard(_local(p)),
            onDragEnd: _cubit.endCardGesture,
            onResize: (delta) => _cubit.resizeCard(card.id, delta),
            onResizeEnd: _cubit.endCardGesture,
            onClose: () => widget.onRequestClose != null
                ? widget.onRequestClose!(card)
                : _cubit.removeCard(card.id),
            onPortDrag: (p) => _cubit.portDrag(card.id, _local(p)),
            onPortRelease: (p) => _cubit.portRelease(card.id, _local(p)),
            onPortCancel: _cubit.portCancel,
            accessory: widget.accessoryBuilder?.call(context, card),
            child: CardMotion(
              live: live,
              child: widget.bodyBuilder(context, card),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE61E1E20),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.white(0.12)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: AppTheme.textStyle.copyWith(fontSize: 12)),
    ),
  );
}
