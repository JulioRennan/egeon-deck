import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/icon_button.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/segmented_control.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/processes_view.dart';
import '../cubit/processes_cubit.dart';
import 'process_table.dart';

/// Abre a janela "Processos" flutuando sobre a tela, sem barreira: o app
/// segue usável por baixo, como a janela própria do Swift. Já aberta, a mesma
/// vem para a frente com o foco (`ProcessesWindow.present()`); o futuro
/// completa quando ela fecha. O título leva o nome do app ([appName]), como o
/// "Processos do Egeon Deck Dev" do Swift: com os dois flavors abertos, diz de
/// qual é a lista.
Future<void> showProcessesPanel(
  BuildContext context, {
  String appName = 'Egeon Deck',
}) {
  final overlay = Overlay.of(context);
  final open = _open[overlay];
  if (open != null) {
    open.present(overlay);
    return open.closed.future;
  }
  final window = _OpenWindow();
  _open[overlay] = window;
  window.entry = OverlayEntry(
    builder: (_) => ProcessesWindow(
      key: window.key,
      initial: _frames[overlay],
      onFrame: (frame) => _frames[overlay] = frame,
      onClose: () {
        _open[overlay] = null;
        window.close();
      },
      child: (close, move) => BlocProvider(
        create: (_) => inject<ProcessesCubit>(),
        child: ProcessesPanel(onClose: close, onMove: move, appName: appName),
      ),
    ),
  );
  overlay.insert(window.entry);
  return window.closed.future;
}

/// Uma janela por `Overlay` (por janela do app), como o `shared` do Swift.
final _open = Expando<_OpenWindow>();

/// Onde ela estava ao fechar: reabre no mesmo lugar, como o
/// `setFrameAutosaveName` (só nesta sessão).
final _frames = Expando<Rect>();

class _OpenWindow {
  final key = GlobalKey<ProcessesWindowState>();
  late final OverlayEntry entry;
  final closed = Completer<void>();

  void present(OverlayState overlay) {
    // Tirar e pôr de volta no mesmo quadro: a `GlobalKey` da entrada leva o
    // estado junto (lista, seleção, posição) e ela sobe acima de tudo.
    entry.remove();
    overlay.insert(entry);
    key.currentState?.focus();
  }

  void close() {
    if (closed.isCompleted) return;
    entry.remove();
    closed.complete();
  }
}

/// A moldura flutuante: arrasta pelo título, redimensiona pelo canto e tem o
/// próprio escopo de foco — aberta por cima de um terminal focado, o Esc e as
/// teclas vêm para ela, e não para o terminal de trás.
class ProcessesWindow extends StatefulWidget {
  const ProcessesWindow({
    required this.child,
    required this.onClose,
    this.initial,
    this.onFrame,
    super.key,
  });

  /// O conteúdo, com o fechar e o mover que o título usa.
  final Widget Function(VoidCallback close, ValueChanged<Offset> move) child;
  final VoidCallback onClose;
  final Rect? initial;
  final ValueChanged<Rect>? onFrame;

  static const size = Size(900, ProcessesPanel.height);
  static const minSize = Size(680, 260);

  @override
  State<ProcessesWindow> createState() => ProcessesWindowState();
}

class ProcessesWindowState extends State<ProcessesWindow> {
  final _scope = FocusScopeNode(debugLabel: 'Processos');
  Rect? _frame;

  @override
  void initState() {
    super.initState();
    _frame = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => focus());
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  void focus() {
    if (mounted) _scope.requestFocus();
  }

  /// Dentro da área: nem some pela borda nem fica menor que o mínimo.
  Rect _fit(Rect frame, Size area) {
    final width = frame.width.clamp(
      ProcessesWindow.minSize.width,
      area.width < ProcessesWindow.minSize.width
          ? ProcessesWindow.minSize.width
          : area.width,
    );
    final height = frame.height.clamp(
      ProcessesWindow.minSize.height,
      area.height < ProcessesWindow.minSize.height
          ? ProcessesWindow.minSize.height
          : area.height,
    );
    final left = frame.left.clamp(0.0, (area.width - width).clamp(0.0, 1e9));
    final top = frame.top.clamp(0.0, (area.height - height).clamp(0.0, 1e9));
    return Rect.fromLTWH(left, top, width, height);
  }

  void _change(Rect Function(Rect frame) next, Size area) {
    final frame = _frame;
    if (frame == null) return;
    setState(() => _frame = _fit(next(frame), area));
    widget.onFrame?.call(_frame!);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final area = box.biggest;
      final frame = _fit(
        _frame ??
            Rect.fromCenter(
              center: area.center(Offset.zero),
              width: ProcessesWindow.size.width,
              height: ProcessesWindow.size.height,
            ),
        area,
      );
      _frame = frame;
      return Stack(
        children: [
          Positioned.fromRect(
            rect: frame,
            child: FocusScope(
              node: _scope,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              // Clicar nela devolve o foco a ela, como clicar numa janela.
              child: Listener(
                onPointerDown: (_) => focus(),
                child: GlassSurface(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: widget.child(
                          widget.onClose,
                          (delta) => _change((f) => f.shift(delta), area),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeDownRight,
                          child: GestureDetector(
                            key: const ValueKey('processes-resize'),
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) => _change(
                              (f) => Rect.fromLTWH(
                                f.left,
                                f.top,
                                f.width + d.delta.dx,
                                f.height + d.delta.dy,
                              ),
                              area,
                            ),
                            child: const SizedBox(width: 14, height: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// O conteúdo da janela: o filtro, o resumo, os dois botões de encerrar e a
/// tabela de processos.
class ProcessesPanel extends StatelessWidget {
  const ProcessesPanel({
    required this.onClose,
    this.onMove,
    this.appName = 'Egeon Deck',
    super.key,
  });

  final String appName;

  final VoidCallback onClose;

  /// Arrastar pelo título move a janela.
  final ValueChanged<Offset>? onMove;

  static const height = 480.0;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProcessesCubit>();
    final c = context.eg;
    return BlocBuilder<ProcessesCubit, ProcessesState>(
      builder: (context, state) {
        final (rows, selected, summary, orphans) = switch (state) {
          ProcessesScanning() => (const <ProcessRow>[], const <int>{}, '', 0),
          ProcessesLoaded(:final rows, :final selected, :final view) => (
            rows,
            selected,
            view.summary,
            view.orphans,
          ),
        };
        return SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                key: const ValueKey('processes-title'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: onMove == null
                    ? null
                    : (details) => onMove!(details.delta),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Processos do $appName',
                        style: EgeonType.heading.copyWith(
                          color: c.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('processes-close'),
                        icon: EgIcons.x,
                        tooltip: 'Fechar',
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    SegmentedControl<ProcessFilter>(
                      value: state.filter,
                      onChanged: cubit.setFilter,
                      options: const [
                        SegmentOption(ProcessFilter.all, 'Todos'),
                        SegmentOption(ProcessFilter.orphans, 'Órfãos'),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        summary,
                        key: const ValueKey('processes-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.caption.copyWith(
                          color: c.textSecondary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    FormDialogButton(
                      'Encerrar selecionados',
                      small: true,
                      enabled: selected.isNotEmpty,
                      onTap: () => _killSelected(context),
                    ),
                    const SizedBox(width: 8),
                    FormDialogButton(
                      'Encerrar órfãos',
                      small: true,
                      enabled: orphans > 0,
                      onTap: () => _killOrphans(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          switch (state) {
                            ProcessesScanning() => 'Varrendo…',
                            ProcessesLoaded() => 'Nenhum processo.',
                          },
                          style: EgeonType.caption.copyWith(
                            color: c.textMuted,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    : ProcessTable(
                        rows: rows,
                        selected: selected,
                        onTap: (row, {required additive, required range}) =>
                            cubit.select(
                              row.pid,
                              additive: additive,
                              range: range,
                            ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _killOrphans(BuildContext context) async {
    final cubit = context.read<ProcessesCubit>();
    final confirm = await cubit.confirmReap();
    if (confirm == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: confirm.title,
      message: confirm.detail,
      confirmLabel: 'Encerrar',
      destructive: true,
    );
    if (ok) await cubit.reapOrphans();
  }

  Future<void> _killSelected(BuildContext context) async {
    final cubit = context.read<ProcessesCubit>();
    final confirm = await cubit.confirmKill();
    if (confirm == null || !context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: confirm.title,
      message: confirm.detail,
      confirmLabel: 'Encerrar',
      destructive: true,
    );
    if (ok) await cubit.killSelected();
  }
}
