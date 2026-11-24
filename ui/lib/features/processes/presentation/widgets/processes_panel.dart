import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/eg/segmented_control.dart';
import '../../../../core/adapters/app_windows.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/processes_view.dart';
import '../cubit/processes_cubit.dart';
import 'process_table.dart';

/// Abre a janela "Processos" como janela própria do sistema (decisão 51),
/// como o Swift: o app segue usável ao lado, e ela pode ir para outra tela.
/// Já aberta, a mesma vem para a frente. O título leva o nome do app
/// ([appName]), como o "Processos do Egeon Deck Dev" do Swift: com os dois
/// flavors abertos, diz de qual é a lista.
Future<void> showProcessesWindow({String appName = 'Egeon Deck'}) =>
    inject<AppWindows>().open(
      WindowArguments(
        kind: WindowKind.processes,
        title: ProcessesPanel.titleFor(appName),
      ),
    );

/// A janela inteira, no motor dela: o Esc fecha, como no Swift.
class ProcessesWindowPage extends StatelessWidget {
  const ProcessesWindowPage({required this.onClose, super.key});

  final VoidCallback onClose;

  /// O tamanho com que abre e o menor a que encolhe.
  static const size = Size(900, ProcessesPanel.height);
  static const minSize = Size(680, 260);

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => inject<ProcessesCubit>(),
    child: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: context.eg.carbon,
        child: const ProcessesPanel(),
      ),
    ),
  );
}

/// O conteúdo da janela: o filtro, o resumo, os dois botões de encerrar e a
/// tabela de processos.
class ProcessesPanel extends StatelessWidget {
  const ProcessesPanel({super.key});

  /// O título da janela, com o nome do app.
  static String titleFor(String appName) => 'Processos do $appName';

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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
