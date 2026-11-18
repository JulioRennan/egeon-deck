import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/hand_cursor.dart';
import '../../../../commons/widgets/standard_dialogs.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/processes_view.dart';
import '../../domain/repository/processes_repository.dart';
import '../../domain/usecase/manage_processes.dart';
import '../cubit/processes_cubit.dart';
import '../cubit/processes_state.dart';

/// Abre a janela "Processos" por cima da tela. Não é janela do sistema: o app
/// tem uma só, e a lista cabe num painel modal que se fecha com Esc.
Future<void> showProcessesPanel(BuildContext context) {
  final repository = context.read<ProcessesRepository>();
  return showAppDialog<void>(
    context,
    width: 900,
    builder: (_, close) => BlocProvider(
      create: (_) => ProcessesCubit(manage: ManageProcesses(repository)),
      child: ProcessesPanel(onClose: close),
    ),
  );
}

/// O conteúdo da janela: o filtro, o resumo, os dois botões de encerrar e a
/// tabela de processos.
class ProcessesPanel extends StatelessWidget {
  const ProcessesPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  static const height = 480.0;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProcessesCubit>();
    return BlocBuilder<ProcessesCubit, ProcessesState>(
      builder: (context, state) {
        final orphans = state.view.orphans;
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Row(
                  children: [
                    Text(
                      'Processos do Egeon Deck',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _Segments(filter: state.filter, onChanged: cubit.setFilter),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.view.summary,
                        key: const ValueKey('processes-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(12, 0.55, medium: true),
                      ),
                    ),
                    DialogButton(
                      'Encerrar selecionados',
                      small: true,
                      enabled: state.selected.isNotEmpty,
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
                child: state.rows.isEmpty
                    ? Center(
                        child: Text(
                          state.loaded ? 'Nenhum processo.' : 'Varrendo…',
                          style: _style(12, 0.4),
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.rows.length,
                        itemBuilder: (context, index) => _Row(
                          row: state.rows[index],
                          selected: state.selected.contains(
                            state.rows[index].pid,
                          ),
                          alternate: index.isOdd,
                          onTap: (additive, range) => cubit.select(
                            state.rows[index].pid,
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
