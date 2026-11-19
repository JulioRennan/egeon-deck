import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/file_drop_target.dart';
import '../../../../../commons/widgets/pasted_image.dart';
import '../../../../../core/adapters/injector.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/errors/queue_error.dart';
import '../cubit/queue_cubit.dart';
import '../cubit/queue_notice_cubit.dart';
import 'queue_bar.dart';
import 'queue_row.dart';
import 'queue_text_field.dart';

/// O corpo de um card de fila, preso ao nó: um cubit por fila. A fila como
/// lista de tarefas: cada uma é um texto corrido, e o clique deixa editar ali
/// mesmo, com os prints e a conversa embaixo.
class QueueBody extends StatelessWidget {
  const QueueBody({
    required this.workbenchId,
    required this.nodeId,
    this.onClose,
    this.focusNewTask = false,
    super.key,
  });

  /// A bancada da fila: os comandos dela vão por esta bancada.
  final String workbenchId;
  final String nodeId;

  /// No painel ao lado da conversa, o ✕ da barra; no card não há.
  final VoidCallback? onClose;

  /// Aberta no painel do chat, o teclado vai para "Nova tarefa".
  final bool focusNewTask;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      key: ValueKey((workbenchId, nodeId)),
      providers: [
        BlocProvider(
          create: (_) =>
              inject<QueueCubit>((workbenchId: workbenchId, nodeId: nodeId)),
        ),
        BlocProvider(
          create: (context) =>
              inject<QueueNoticeCubit>(context.read<QueueCubit>().notices),
        ),
      ],
      child: _QueueView(onClose: onClose, focusNewTask: focusNewTask),
    );
  }
}

class _QueueView extends StatelessWidget {
  const _QueueView({required this.focusNewTask, this.onClose});

  final VoidCallback? onClose;
  final bool focusNewTask;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QueueCubit>();
    // Print solto na fila: entra na tarefa aberta; sem nenhuma aberta (ou já
    // enviada), vira tarefa nova já aberta, para você escrever.
    return FileDropTarget(
      onFiles: (paths) => unawaited(cubit.attachFiles(paths)),
      onImage: (png) => unawaited(cubit.attachPng(png)),
      child: ColoredBox(
        color: const Color(0xFF181818),
        child: BlocBuilder<QueueCubit, QueueState>(
          builder: (context, state) {
            final queue = state.queue;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QueueBar(
                  queue: queue,
                  onTarget: cubit.setTarget,
                  onAuto: (on) => cubit.setAuto(on: on),
                  onSendNext: () => cubit.send(),
                  onClearDone: cubit.clearDone,
                  onClose: onClose,
                ),
                const _Notice(),
                Expanded(
                  child: _List(
                    state: state,
                    cubit: cubit,
                    focusNewTask: focusNewTask,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// O erro recente do envio, senão por que a fila não anda.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<QueueNoticeCubit, QueueNoticeState>(
        builder: (context, state) {
          final notice = switch (state) {
            QueueQuiet() => null,
            QueueBlocked(:final text) => text,
            QueueSendFailed(
              failure: QueueSendFailure(error: QueueRefused(:final message)),
            ) =>
              message,
            QueueSendFailed(
              failure: QueueSendFailure(error: QueueOffline(), reply: true),
            ) =>
              'Falha ao responder',
            QueueSendFailed(failure: QueueSendFailure(error: QueueOffline())) =>
              'Falha ao enviar',
          };
          if (notice == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              notice,
              key: const ValueKey('queue-notice'),
              style: const TextStyle(
                color: AppColors.attention,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          );
        },
      );
}

class _List extends StatelessWidget {
  const _List({
    required this.state,
    required this.cubit,
    required this.focusNewTask,
  });

  final QueueState state;
  final QueueCubit cubit;
  final bool focusNewTask;

  @override
  Widget build(BuildContext context) {
    final items = state.queue.items;
    final open = switch (state) {
      QueueEditing(:final open) => open,
      QueueWaiting() || QueueBrowsing() => null,
    };
    final labels = {for (final t in state.queue.targets) t.id: t.label};
    return GestureDetector(
      // Clicar no vazio fecha a tarefa aberta.
      behavior: HitTestBehavior.translucent,
      onTap: cubit.collapse,
      child: ReorderableList(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        itemCount: items.length + 1,
        // `onReorderItem` já entrega a posição entre as linhas que ficaram, que
        // é a conta que a fila quer. A linha nova de baixo não conta.
        onReorderItem: (from, to) =>
            cubit.move(items[from].id, to: to.clamp(0, items.length - 1)),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return _NewRow(
              key: const ValueKey('new-row'),
              drafts: cubit.drafts,
              onCreate: (text) => cubit.create(text: text),
              onPaste: cubit.pasteNew,
              autofocus: focusNewTask,
            );
          }
          final item = items[index];
          return _Reorderable(
            key: ValueKey(item.id),
            index: index,
            child: QueueRow(
              item: item,
              expanded: open == item.id,
              destinationLabel: labels[item.sentTo],
              onExpand: () => cubit.expand(item.id),
              onToggleDone: () => cubit.toggleDone(item.id),
              onSend: () => cubit.send(id: item.id),
              onReopen: () => cubit.reopen(item.id),
              onRemove: () => cubit.remove(item.id),
              onMove: (offset) => cubit.moveBy(item.id, offset),
              onEdit: (text) => cubit.update(item.id, text),
              onDetach: (image) => cubit.detach(item.id, image),
              onOpenImage: (image) => cubit.openImage(item.id, image),
              imagesDir: state.queue.imagesDir,
              onReply: (text) => cubit.reply(item.id, text),
              // Enter em tarefa em branco é parar de anotar, não abrir outra
              // em branco.
              onCommit: () =>
                  item.empty ? cubit.collapse() : cubit.create(after: item.id),
              onCollapse: cubit.collapse,
              onPaste: (pasted) => cubit.pasteInto(item.id, pasted),
            ),
          );
        },
      ),
    );
  }
}

/// A linha arrastável: o gesto de arrastar começa no corpo da linha depois de
/// um instante parado (como no Things), e não rouba o clique nem o texto.
class _Reorderable extends StatelessWidget {
  const _Reorderable({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ReorderableDelayedDragStartListener(index: index, child: child);
}

/// A linha de baixo: Enter põe a tarefa na lista e deixa a linha pronta para a
/// próxima — anotar dez seguidas é digitar e dar Enter dez vezes.
class _NewRow extends StatefulWidget {
  const _NewRow({
    required this.onCreate,
    required this.onPaste,
    required this.drafts,
    this.autofocus = false,
    super.key,
  });

  final ValueChanged<String> onCreate;

  /// Pede o teclado ao nascer, mesmo com ele em outro campo (o composer do
  /// chat): o `autofocus` só vale num escopo sem foco nenhum.
  final bool autofocus;

  /// ⌘V com imagem: o que já estava escrito vai junto, numa tarefa nova.
  final bool Function(String text, PastedClipboard pasted) onPaste;

  /// Rascunhos que chegam de fora (o `egeon` do terminal).
  final Stream<String> drafts;

  @override
  State<_NewRow> createState() => _NewRowState();
}

class _NewRowState extends State<_NewRow> {
  var _text = '';
  var _generation = 0;
  StreamSubscription<String>? _drafts;
  final _focus = FocusNode(debugLabel: 'queue-new-task');

  @override
  void initState() {
    super.initState();
    _drafts = widget.drafts.listen(_onDraft);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_NewRow old) {
    super.didUpdateWidget(old);
    if (old.drafts != widget.drafts) {
      unawaited(_drafts?.cancel());
      _drafts = widget.drafts.listen(_onDraft);
    }
  }

  /// Escreve na linha de baixo sem pôr na lista: você confere e dá Enter.
  void _onDraft(String draft) => setState(() {
    _text = draft.trim();
    _generation++;
  });

  @override
  void dispose() {
    unawaited(_drafts?.cancel());
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _text.trim();
    if (text.isEmpty) return;
    widget.onCreate(text);
    setState(() {
      _text = '';
      _generation++;
    });
  }

  /// Print colado aqui nasce como tarefa aberta, e a linha se esvazia.
  bool _paste(PastedClipboard pasted) {
    if (!widget.onPaste(_text, pasted)) return false;
    setState(() {
      _text = '';
      _generation++;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 1, right: 12),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white(0.2), width: 1.6),
          ),
        ),
        Expanded(
          child: QueueTextField(
            key: ValueKey('new-field-$_generation'),
            text: _text,
            hint: 'Nova tarefa',
            focusNode: _focus,
            onChanged: (text) => _text = text,
            onSubmit: _commit,
            onPasteImage: _paste,
          ),
        ),
      ],
    ),
  );
}
