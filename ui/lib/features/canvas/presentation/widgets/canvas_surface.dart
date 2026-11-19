import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../theme/app_colors.dart';
import '../../../../core/domain/entities/workbench_node.dart';
import '../../../../theme/app_theme.dart';
import '../../../node/card/presentation/widgets/card_accent.dart';
import '../../../node/card/presentation/widgets/card_frame.dart';
import '../../../node/card/presentation/widgets/card_status.dart';
import '../../../node/card/presentation/widgets/card_motion.dart';
import '../../domain/entities/canvas_card.dart';
import '../../domain/entities/canvas_probe.dart';
import '../../domain/entities/edge_link.dart';
import '../cubit/canvas_commands.dart';
import '../cubit/canvas_cubit.dart';
import '../cubit/canvas_motion_cubit.dart';
import '../cubit/canvas_tool_cubit.dart';
import 'canvas_glow.dart';
import 'canvas_grid.dart';
import 'canvas_bench_actions.dart';
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
/// A página web fica ao vivo em qualquer zoom, como no Swift, em vez de virar
/// foto fora de 100%. Desligada até alguém conferir com o app aberto que a vista
/// nativa escala e recebe clique dentro do canvas ampliado. Liga na compilação:
/// `DART_DEFINES=--dart-define=EGEON_WEB_LIVE_ZOOM=true ui/scripts/dev.sh`.
const webLiveAtAnyZoom = bool.fromEnvironment('EGEON_WEB_LIVE_ZOOM');

class CanvasSurface extends StatefulWidget {
  const CanvasSurface({
    required this.bodyBuilder,
    this.accessoryBuilder,
    this.glow,
    this.componentNames,
    this.onConfigureTerminal,
    this.onConfigureTerminalAt,
    this.benchActions,
    this.infoBar,
    this.onRequestConfigure,
    this.onEditLimit,
    this.onRequestClose,
    this.onRetry,
    this.onOpenFolder,
    this.onRequestWorktree,
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

  /// Os componentes salvos, pedidos na hora em que o menu do Terminal abre.
  final Future<List<String>> Function()? componentNames;

  /// "Configurar novo terminal…" do menu do Terminal.
  /// "Configurar novo terminal…": recebe o que está à vista, no espaço do
  /// canvas, para o nó nascer ali.
  final ValueChanged<Rect>? onConfigureTerminal;

  /// Terminal solto sem componente: abre o formulário para aquele lugar.
  final ValueChanged<Rect>? onConfigureTerminalAt;

  /// Os botões de template e worktree da barra.
  final CanvasBenchActions? benchActions;

  /// A faixa informativa sob a barra de ações (ADR-085).
  final Widget? infoBar;

  /// O lápis do card de terminal: configurar o nó.
  final ValueChanged<CanvasCard>? onRequestConfigure;
  final ValueChanged<EdgeLink>? onEditLimit;

  /// Clique no X de um nó. Confirmar é de quem escuta; sem ouvinte, remove.
  final ValueChanged<CanvasCard>? onRequestClose;

  /// "Tentar agora" / "Cancelar tentativa" no status de um agente.
  final void Function(CanvasCard card, {required bool now})? onRetry;

  /// O ⌘-clique no subtítulo de um terminal: a pasta dele no Finder.
  final ValueChanged<CanvasCard>? onOpenFolder;

  /// "Nova worktree para este terminal…" de um shell ou agente.
  final ValueChanged<CanvasCard>? onRequestWorktree;

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
  StreamSubscription<Rect>? _configure;

  @override
  void initState() {
    super.initState();
    final cubit = _attached = context.read<CanvasCubit>();
    final tools = context.read<CanvasToolCubit>();
    _configure = tools.configureTerminal.listen(
      (frame) => widget.onConfigureTerminalAt?.call(frame),
    );
    cubit.setSidebarInset(widget.sidebarInset);
    widget.commands?.attach(cubit, tools);
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
    unawaited(_configure?.cancel());
    final attached = _attached;
    if (attached != null) widget.commands?.detach(attached);
    final probe = _probe;
    if (probe != null) widget.probes?.unregister(probe);
    super.dispose();
  }

  CanvasCubit get _cubit => context.read<CanvasCubit>();

  CanvasToolCubit get _tools => context.read<CanvasToolCubit>();

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
      // Armar uma ferramenta tira o realce: com ela o clique é de criação.
      return BlocListener<CanvasToolCubit, CanvasToolState>(
        listener: (context, tool) {
          if (tool is! CanvasPointer) _cubit.clearHover();
        },
        child: Builder(
          builder: (context) {
            final state = context.watch<CanvasCubit>().state;
            final tool = context.watch<CanvasToolCubit>().state;
            final moving = switch (context.watch<CanvasMotionCubit>().state) {
              CanvasStill() => false,
              CanvasMoving() => true,
            };
            return _surface(context, state, tool, moving: moving);
          },
        ),
      );
    },
  );

  Widget _surface(
    BuildContext context,
    CanvasState state,
    CanvasToolState tool, {
    required bool moving,
  }) {
    final view = state.viewport;
    final frames = state.frames;
    final pointer = tool is CanvasPointer;
    final armed = _tools.tool;
    final hovered = switch (state) {
      CanvasLinkHovered(:final link) => link,
      CanvasIdle() ||
      CanvasPanning() ||
      CanvasDraggingCard() ||
      CanvasLinking() => null,
    };
    final banner = switch (tool) {
      CanvasAnnouncing(:final component) =>
        'Próximo terminal: ${component ?? 'shell'}',
      CanvasPointer() || CanvasArmed() || CanvasComponentArmed() => null,
    };
    return MouseRegion(
      cursor: state is CanvasPanning
          ? SystemMouseCursors.grabbing
          : MouseCursor.defer,
      onHover: (e) {
        if (pointer) _cubit.hoverAt(e.localPosition);
      },
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
          } else if (HardwareKeyboard.instance.isMetaPressed) {
            // ⌘ + dois dedos: o mesmo zoom no cursor da ⌘+roda, de qualquer
            // ponto do canvas, inclusive sobre um terminal. O trackpad manda
            // o deslocamento dos dedos, o contrário do da roda.
            _cubit.wheelZoom(-e.panDelta.dy, e.localPosition);
          }
        },
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: CanvasGrid(viewport: view)),
              Positioned.fill(child: _background(state)),
              Positioned.fill(
                child: _world(context, state, hovered, moving: moving),
              ),
              Positioned.fill(child: CanvasGlow(color: widget.glow)),
              if (hovered != null && pointer)
                Positioned.fill(
                  child: EdgeControlsLayer(
                    link: hovered,
                    frames: frames,
                    viewport: view,
                    onCycle: () => _cubit.cycleDirection(hovered),
                    onLimit: () => widget.onEditLimit?.call(hovered),
                    onRemove: () => _cubit.removeLink(hovered),
                  ),
                ),
              // Com ferramenta armada o overlay tapa o canvas para capturar o
              // clique de criação (senão o terminal engoliria); a barra vem por
              // cima dele para continuar clicável.
              if (!pointer)
                Positioned.fill(
                  child: ToolOverlay(
                    onPlace: (start, end) => _tools.placeByGesture(
                      start,
                      end,
                      _cubit.state.viewport,
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: CanvasToolbar(
                    tool: armed,
                    zoom: view.zoom,
                    componentNames: widget.componentNames,
                    onSelect: _tools.selectTool,
                    onZoom: _cubit.stepZoom,
                    onResetZoom: _cubit.resetZoom,
                    onFitAll: _cubit.fitAll,
                    onPickComponent: _tools.pickComponent,
                    onConfigureTerminal: switch (widget.onConfigureTerminal) {
                      final configure? => () => configure(
                        _cubit.visibleDocument,
                      ),
                      null => null,
                    },
                    benchActions: widget.benchActions,
                  ),
                ),
              ),
              if (widget.infoBar case final info?)
                Positioned(
                  top: 12 + CanvasToolbar.height + 6,
                  left: 0,
                  right: 0,
                  child: Center(child: info),
                ),
              if (banner != null)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Center(child: _Banner(banner)),
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
      if (e.scale == 1 && !HardwareKeyboard.instance.isMetaPressed) {
        _cubit.trackpadPan(e.panDelta);
      }
    },
    child: const SizedBox.expand(),
  );

  Widget _world(
    BuildContext context,
    CanvasState state,
    EdgeLink? hovered, {
    required bool moving,
  }) {
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
                      hovered: hovered,
                      pending: switch (state) {
                        CanvasLinking(:final pending) => pending,
                        CanvasIdle() ||
                        CanvasPanning() ||
                        CanvasDraggingCard() ||
                        CanvasLinkHovered() => null,
                      },
                    ),
                  ),
                ),
              ),
              for (final card in state.cards)
                _card(
                  card,
                  live:
                      !moving &&
                      (webLiveAtAnyZoom || (view.zoom - 1).abs() < 0.001),
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
            titleTooltip: card.titleTooltip,
            onWorktree: switch (widget.onRequestWorktree) {
              final worktree?
                  when card.kind == NodeKind.shell ||
                      card.kind == NodeKind.agent =>
                () => worktree(card),
              _ => null,
            },
            onOpenFolder: switch (widget.onOpenFolder) {
              final open?
                  when card.kind == NodeKind.shell ||
                      card.kind == NodeKind.agent =>
                () => open(card),
              _ => null,
            },
            subtitle: card.subtitle,
            height: card.frame.height,
            linkable: card.port,
            needsAttention: card.activity.needsAttention,
            maestro: card.maestro,
            accent: card.maestro ? CardAccent.maestro : null,
            titleColor: ActivityColors.of(card.activity.tone),
            status: CardStatus(
              activity: card.activity,
              onRetry: switch (widget.onRetry) {
                final retry? when card.kind == NodeKind.agent => ({
                  required now,
                }) => retry(card, now: now),
                _ => null,
              },
            ),
            onDragStart: (p) => _cubit.beginCardDrag(card.id, _local(p)),
            onDrag: (p) => _cubit.dragCard(_local(p)),
            onDragEnd: _cubit.endCardGesture,
            onResize: (delta) => _cubit.resizeCard(card.id, delta),
            onResizeEnd: _cubit.endCardGesture,
            onClose: () => widget.onRequestClose != null
                ? widget.onRequestClose!(card)
                : _cubit.removeCard(card.id),
            // Só terminal se configura: web e fila têm o formulário deles.
            onConfigure:
                widget.onRequestConfigure != null &&
                    (card.kind == NodeKind.shell || card.kind == NodeKind.agent)
                ? () => widget.onRequestConfigure!(card)
                : null,
            onPortDrag: (p) => _cubit.portDrag(card.id, _local(p)),
            onPortRelease: (p) => _cubit.portRelease(card.id, _local(p)),
            onPortCancel: _cubit.portCancel,
            focusColor: widget.glow,
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
