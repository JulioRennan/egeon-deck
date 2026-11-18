import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';
import '../../domain/entities/terminal_cursor.dart';
import '../../domain/entities/terminal_effect.dart';
import '../../domain/entities/terminal_frame.dart';
import '../../domain/entities/terminal_key.dart';
import '../../domain/entities/terminal_line.dart';
import '../../domain/entities/terminal_pointer.dart';
import '../../domain/entities/terminal_scrollbar.dart';
import 'terminal_buffer.dart';
import 'terminal_key_mapper.dart';
import 'terminal_line_painter.dart';
import 'terminal_metrics.dart';
import 'terminal_text_input.dart';

/// Pinta a grade do terminal a partir de um stream de quadros, captura o
/// teclado e informa colunas × linhas quando o espaço muda. Não sabe de
/// socket nem de cubit: quem o usa liga os callbacks.
class TerminalView extends StatefulWidget {
  const TerminalView({
    super.key,
    required this.frames,
    required this.onKey,
    required this.onText,
    required this.onPaste,
    required this.onResize,
    this.initialFrame,
    this.autofocus = true,
    this.effects = const Stream.empty(),
    this.onPointer,
    this.onScroll,
    this.onSelectAll,
    this.onCopy,
    this.onClipboardResponse,
    this.onLinkHover,
    this.focusNode,
  });

  final Stream<TerminalFrame> frames;
  final TerminalFrame? initialFrame;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<String> onText;
  final ValueChanged<String> onPaste;
  final void Function(int columns, int rows) onResize;
  final bool autofocus;

  /// Beep e área de transferência pedidos pelo programa.
  final Stream<TerminalEffect> effects;

  /// O gesto do mouse, cru. Quem o interpreta é o core.
  final ValueChanged<TerminalPointer>? onPointer;
  final ValueChanged<TerminalScroll>? onScroll;
  final VoidCallback? onSelectAll;

  /// ⌘C: o texto da seleção, ou nulo.
  final Future<String?> Function()? onCopy;

  /// Resposta ao pedido de leitura da área de transferência.
  final ValueChanged<String>? onClipboardResponse;

  /// Há link na célula? Só com ⌘ sobre ela; a UI mostra a mão se houver.
  final Future<bool> Function(double x, double y)? onLinkHover;

  /// Quem precisa devolver o foco ao terminal (depois de soltar um arquivo)
  /// o cria e o solta; sem ele, a vista cuida do seu.
  final FocusNode? focusNode;

  /// Enquanto o botão segura fora da vista, o último arrasto se repete assim,
  /// e cada repetição rola a seleção.
  static const dragRepeat = Duration(milliseconds: 50);

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

const _scrollbarWidth = 8.0;

class _TerminalViewState extends State<TerminalView> {
  final _buffer = TerminalBuffer();
  late final _focus = widget.focusNode ?? FocusNode(debugLabel: 'terminal');
  late final TerminalTextInput _input = TerminalTextInput(
    onText: widget.onText,
    onClosed: () {
      if (_focus.hasFocus) _input.attach();
    },
  );
  final _metrics = TerminalMetrics.measure();
  StreamSubscription<TerminalFrame>? _subscription;
  StreamSubscription<TerminalEffect>? _effects;
  (int, int)? _reported;
  PointerButton? _pressed;
  TerminalPointer? _lastDrag;
  Timer? _dragTimer;
  var _wheelPixels = 0.0;
  var _linkCursor = false;
  Offset? _hoverAt;
  (int, int)? _linkCell;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFrame;
    if (initial != null) _buffer.apply(initial);
    _subscription = widget.frames.listen(_buffer.apply);
    _effects = widget.effects.listen(_onEffect);
  }

  @override
  void didUpdateWidget(TerminalView old) {
    super.didUpdateWidget(old);
    if (old.frames != widget.frames) {
      unawaited(_subscription?.cancel());
      _subscription = widget.frames.listen(_buffer.apply);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_effects?.cancel());
    _dragTimer?.cancel();
    _input.dispose();
    _buffer.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused) {
      _input.attach();
    } else {
      _input.detach();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight) {
      // ⌘ apertado ou solto: a mão aparece (ou some) sem mexer o mouse.
      _linkCell = null;
      _refreshLink();
    }
    // Composição em andamento (depois de uma tecla morta): a próxima tecla é
    // do método de entrada, que a junta com o acento. Enter incluído: o macOS
    // o consome para fechar a composição (precisa de um segundo Enter), o
    // mesmo que o SwiftTerm faz no legado, onde Return só chega por
    // doCommand(insertNewline:) quando não há texto marcado.
    if (_input.isComposing) return KeyEventResult.ignored;
    // O sistema pode ter fechado a conexão de texto com o foco ainda aqui;
    // sem ela as letras (que a UI deixa para o método de entrada) sumiriam.
    if (!_input.attached) _input.attach();
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed && event is! KeyUpEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyV) {
        unawaited(_paste());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA && widget.onSelectAll != null) {
        widget.onSelectAll!();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC && widget.onCopy != null) {
        unawaited(_copy());
        return KeyEventResult.handled;
      }
    }
    final key = mapTerminalKey(event, keyboard);
    if (key == null) return KeyEventResult.ignored;
    widget.onKey(key);
    return KeyEventResult.handled;
  }

  Future<void> _copy() async {
    final text = await widget.onCopy!();
    if (text != null && text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> _onEffect(TerminalEffect effect) async {
    switch (effect) {
      case Bell():
        await SystemSound.play(SystemSoundType.alert);
      case ClipboardWrite(:final text):
        await Clipboard.setData(ClipboardData(text: text));
      case ClipboardRequest():
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        widget.onClipboardResponse?.call(data?.text ?? '');
    }
  }

  // ---- mouse ---------------------------------------------------------------

  TerminalPointer _pointer(
    PointerEvent event,
    PointerKind kind, {
    PointerButton? button,
    int? lines,
  }) {
    final keyboard = HardwareKeyboard.instance;
    return TerminalPointer(
      kind: kind,
      button: button,
      x: event.localPosition.dx / _metrics.cellWidth,
      y: event.localPosition.dy / _metrics.cellHeight,
      timeMs: event.timeStamp.inMilliseconds,
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
      lines: lines,
    );
  }

  static PointerButton? _buttonOf(int buttons) => switch (buttons) {
    kPrimaryButton => PointerButton.left,
    kMiddleMouseButton => PointerButton.middle,
    kSecondaryButton => PointerButton.right,
    _ => null,
  };

  /// ⌘ sobre um link mostra a mão; sem link, o I-beam. Vale também sobre um
  /// terminal sem foco. Só pergunta ao core quando a célula muda.
  void _onHover(PointerHoverEvent event) {
    _hoverAt = event.localPosition;
    _refreshLink();
  }

  void _refreshLink() {
    final at = _hoverAt;
    final ask = widget.onLinkHover;
    if (at == null || ask == null || !HardwareKeyboard.instance.isMetaPressed) {
      _linkCell = null;
      _setLinkCursor(false);
      return;
    }
    final x = at.dx / _metrics.cellWidth;
    final y = at.dy / _metrics.cellHeight;
    final cell = (x.floor(), y.floor());
    if (cell == _linkCell) return;
    _linkCell = cell;
    unawaited(
      ask(x, y).then((link) {
        // A célula pode ter mudado enquanto o core respondia.
        if (mounted && _linkCell == cell) _setLinkCursor(link);
      }),
    );
  }

  void _setLinkCursor(bool value) {
    if (_linkCursor == value || !mounted) return;
    setState(() => _linkCursor = value);
  }

  void _onPointerDown(PointerDownEvent event) {
    // ⌥ pana o canvas por cima do nó: o gesto não é do terminal.
    if (HardwareKeyboard.instance.isAltPressed) return;
    final button = _buttonOf(event.buttons);
    if (button == null || widget.onPointer == null) return;
    _focus.requestFocus();
    _pressed = button;
    widget.onPointer!(_pointer(event, PointerKind.press, button: button));
  }

  void _onPointerMove(PointerMoveEvent event) {
    final button = _pressed;
    if (button == null) return;
    final drag = _pointer(event, PointerKind.drag, button: button);
    widget.onPointer!(drag);
    // Segurando FORA da vista, o arrasto se repete sozinho e rola a seleção.
    final outside = drag.y < 0 || drag.y >= _buffer.rows;
    if (outside) {
      _lastDrag = drag;
      _dragTimer ??= Timer.periodic(TerminalView.dragRepeat, (_) {
        final last = _lastDrag;
        if (last != null) {
          widget.onPointer!(last.at(DateTime.now().millisecondsSinceEpoch));
        }
      });
    } else {
      _stopRepeat();
    }
  }

  void _onPointerUp(PointerEvent event) {
    final button = _pressed;
    if (button == null) return;
    _pressed = null;
    _stopRepeat();
    widget.onPointer!(_pointer(event, PointerKind.release, button: button));
  }

  void _stopRepeat() {
    _dragTimer?.cancel();
    _dragTimer = null;
    _lastDrag = null;
  }

  /// Acumula a rolagem em pixels e solta linhas inteiras — como o SwiftTerm:
  /// pixels sobre a altura da célula. Positivo sobe.
  void _wheel(double pixels, PointerEvent event) {
    _wheelPixels += pixels;
    final lines = (_wheelPixels / _metrics.cellHeight).truncate();
    if (lines == 0) return;
    _wheelPixels -= lines * _metrics.cellHeight;
    widget.onPointer?.call(_pointer(event, PointerKind.wheel, lines: lines));
  }

  void _onSignal(PointerSignalEvent event) {
    // ⌘+scroll é zoom do canvas.
    if (event is! PointerScrollEvent ||
        HardwareKeyboard.instance.isMetaPressed ||
        widget.onPointer == null) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _wheel(-event.scrollDelta.dy, event),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) widget.onPaste(text);
  }

  void _reportSize(Size size) {
    final columns = (size.width / _metrics.cellWidth).floor();
    final rows = (size.height / _metrics.cellHeight).floor();
    if (columns < 1 || rows < 1 || _reported == (columns, rows)) return;
    _reported = (columns, rows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onResize(columns, rows);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: MouseRegion(
        cursor: _linkCursor
            ? SystemMouseCursors.click
            : SystemMouseCursors.text,
        onHover: _onHover,
        onExit: (_) {
          _hoverAt = null;
          _refreshLink();
        },
        // A barra fica ao lado do Listener, e não dentro: o Listener de um
        // ancestral veria também o arrasto da pegada e o mandaria ao
        // programa como seleção.
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                onPointerSignal: _onSignal,
                onPointerPanZoomUpdate: (e) {
                  if (e.scale == 1 && widget.onPointer != null) {
                    _wheel(e.panDelta.dy, e);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focus.requestFocus,
                  child: ColoredBox(
                    color: AppColors.terminalBackground,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _reportSize(constraints.biggest);
                        return ClipRect(
                          child: ListenableBuilder(
                            listenable: _buffer,
                            builder: (context, _) => _grid(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              bottom: 2,
              width: _scrollbarWidth,
              child: ValueListenableBuilder<TerminalScrollbar?>(
                valueListenable: _buffer.scrollbar,
                builder: (context, bar, _) => bar == null || !bar.scrollable
                    ? const SizedBox.shrink()
                    : _TerminalScrollbar(
                        bar: bar,
                        onScroll: (rows) =>
                            widget.onScroll?.call(ScrollRows(rows)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final lines = _buffer.lines;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              RepaintBoundary(
                child: ValueListenableBuilder<TerminalLine>(
                  valueListenable: line,
                  builder: (context, value, _) => CustomPaint(
                    size: Size(
                      _buffer.columns * _metrics.cellWidth,
                      _metrics.cellHeight,
                    ),
                    painter: TerminalLinePainter(
                      line: value,
                      metrics: _metrics,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ValueListenableBuilder<TerminalCursor>(
          valueListenable: _buffer.cursor,
          builder: (context, cursor, _) => _cursor(cursor),
        ),
      ],
    );
  }

  Widget _cursor(TerminalCursor cursor) {
    if (!cursor.visible) return const SizedBox.shrink();
    return Positioned(
      left: cursor.column * _metrics.cellWidth,
      top: cursor.row * _metrics.cellHeight,
      width: _metrics.cellWidth,
      height: _metrics.cellHeight,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: Listenable.merge([_focus, _input.composing]),
          builder: (context, _) => _input.isComposing
              ? _composingMark(_input.composing.value)
              : _cursorShape(cursor.shape),
        ),
      ),
    );
  }

  /// O trecho em composição (o acento antes da letra), sublinhado no cursor.
  Widget _composingMark(String text) {
    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: double.infinity,
      child: ColoredBox(
        color: AppColors.terminalForeground.withValues(alpha: 0.25),
        child: Text(
          text,
          style: TerminalMetrics.baseStyle.copyWith(
            color: AppColors.terminalForeground,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.terminalForeground,
          ),
        ),
      ),
    );
  }

  Widget _cursorShape(TerminalCursorShape shape) {
    const color = AppColors.terminalCursor;
    if (!_focus.hasFocus) {
      return DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: color)),
      );
    }
    return switch (shape) {
      TerminalCursorShape.block => const ColoredBox(color: color),
      TerminalCursorShape.bar => const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 2, child: ColoredBox(color: color)),
      ),
      TerminalCursorShape.underline => const Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(height: 2, child: ColoredBox(color: color)),
      ),
    };
  }
}

/// A barra de rolagem do histórico: só aparece com histórico acima do que se
/// vê. Arrastar a pegada rola a vista; quem rola é o core, e o quadro novo
/// move a pegada.
class _TerminalScrollbar extends StatefulWidget {
  const _TerminalScrollbar({required this.bar, required this.onScroll});

  final TerminalScrollbar bar;
  final ValueChanged<int> onScroll;

  @override
  State<_TerminalScrollbar> createState() => _TerminalScrollbarState();
}

class _TerminalScrollbarState extends State<_TerminalScrollbar> {
  var _dragging = false;
  var _remainder = 0.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final track = constraints.maxHeight;
      final bar = widget.bar;
      final thumb = (track * bar.len / bar.total).clamp(18.0, track);
      final top =
          (track - thumb) *
          (bar.offset / (bar.total - bar.len)).clamp(0.0, 1.0);
      return Stack(
        children: [
          Positioned(
            key: const ValueKey('scrollbar-thumb'),
            top: top,
            left: 0,
            right: 0,
            height: thumb,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => setState(() => _dragging = true),
              onPointerMove: (e) {
                // Pixels da pegada viram linhas do histórico inteiro.
                _remainder +=
                    e.delta.dy / (track - thumb) * (bar.total - bar.len);
                final rows = _remainder.truncate();
                if (rows == 0) return;
                _remainder -= rows;
                widget.onScroll(rows);
              },
              onPointerUp: (_) => setState(() => _dragging = false),
              onPointerCancel: (_) => setState(() => _dragging = false),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.white(_dragging ? 0.5 : 0.28),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
