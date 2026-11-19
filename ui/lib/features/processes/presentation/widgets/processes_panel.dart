import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/glass_panel.dart';
import '../../../../commons/widgets/hand_cursor.dart';
import '../../../../commons/widgets/standard_dialogs.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/processes_view.dart';
import '../cubit/processes_cubit.dart';

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
  static const minSize = Size(560, 260);

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
                child: GlassPanel(
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Processos do $appName',
                        style: _style(14, 1, semi: true),
                      ),
                      const Spacer(),
                      HandCursor(
                        child: GestureDetector(
                          key: const ValueKey('processes-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onClose,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(
                              child: Text('✕', style: _style(12, 0.6)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _Segments(filter: state.filter, onChanged: cubit.setFilter),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        summary,
                        key: const ValueKey('processes-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(12, 0.55, medium: true),
                      ),
                    ),
                    DialogButton(
                      'Encerrar selecionados',
                      small: true,
                      enabled: selected.isNotEmpty,
                      onTap: () => _killSelected(context),
                    ),
                    const SizedBox(width: 8),
                    DialogButton(
                      'Encerrar órfãos',
                      small: true,
                      enabled: orphans > 0,
                      onTap: () => _killOrphans(context),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: AppColors.white(0.08)),
              _Header(),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(switch (state) {
                          ProcessesScanning() => 'Varrendo…',
                          ProcessesLoaded() => 'Nenhum processo.',
                        }, style: _style(12, 0.4)),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) => _Row(
                          row: rows[index],
                          selected: selected.contains(rows[index].pid),
                          alternate: index.isOdd,
                          onTap: (additive, range) => cubit.select(
                            rows[index].pid,
                            additive: additive,
                            range: range,
                          ),
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

TextStyle _style(
  double size,
  double alpha, {
  bool semi = false,
  bool medium = false,
  bool mono = false,
}) => TextStyle(
  color: AppColors.white(alpha),
  fontSize: size,
  fontWeight: semi
      ? FontWeight.w600
      : medium
      ? FontWeight.w500
      : FontWeight.w400,
  fontFamily: mono ? 'Menlo' : null,
  fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
  decoration: TextDecoration.none,
);

/// Todos / Órfãos.
class _Segments extends StatelessWidget {
  const _Segments({required this.filter, required this.onChanged});

  final ProcessFilter filter;
  final ValueChanged<ProcessFilter> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.white(0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in [
          (ProcessFilter.all, 'Todos'),
          (ProcessFilter.orphans, 'Órfãos'),
        ])
          HandCursor(
            child: GestureDetector(
              key: ValueKey('filter-${value.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: filter == value ? AppColors.white(0.18) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label, style: _style(12, 0.9)),
              ),
            ),
          ),
      ],
    ),
  );
}

const _widths = {'node': 220.0, 'state': 70.0, 'pid': 64.0, 'age': 80.0};

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: AppColors.white(0.04),
    child: Row(
      children: [
        SizedBox(
          width: _widths['node'],
          child: Text('Nó', style: _style(11, 0.5, semi: true)),
        ),
        SizedBox(
          width: _widths['state'],
          child: Text('Estado', style: _style(11, 0.5, semi: true)),
        ),
        SizedBox(
          width: _widths['pid'],
          child: Text('PID', style: _style(11, 0.5, semi: true)),
        ),
        SizedBox(
          width: _widths['age'],
          child: Text('Idade', style: _style(11, 0.5, semi: true)),
        ),
        Expanded(child: Text('Comando', style: _style(11, 0.5, semi: true))),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.selected,
    required this.alternate,
    required this.onTap,
  });

  final ProcessRow row;
  final bool selected;
  final bool alternate;
  final void Function(bool additive, bool range) onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: ValueKey('process-${row.pid}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final keyboard = HardwareKeyboard.instance;
        onTap(
          keyboard.isMetaPressed || keyboard.isControlPressed,
          keyboard.isShiftPressed,
        );
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: selected
            ? AppColors.accent.withValues(alpha: 0.35)
            : alternate
            ? AppColors.white(0.03)
            : null,
        child: Row(
          children: [
            SizedBox(
              width: _widths['node'],
              child: Text(
                row.node ?? 'app',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(12, 0.9),
              ),
            ),
            SizedBox(
              width: _widths['state'],
              child: Text(
                row.orphan ? 'órfão' : 'no app',
                style: row.orphan
                    ? _style(12, 1).copyWith(color: AppColors.attention)
                    : _style(12, 0.55),
              ),
            ),
            SizedBox(
              width: _widths['pid'],
              child: Text('${row.pid}', style: _style(12, 0.9, mono: true)),
            ),
            SizedBox(
              width: _widths['age'],
              child: Text(row.age, style: _style(12, 0.9, mono: true)),
            ),
            Expanded(
              child: Text(
                row.command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(12, 0.9),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
