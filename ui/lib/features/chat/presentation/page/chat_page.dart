import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../node/queue/presentation/widgets/queue_side_panel.dart';
import '../../../../core/adapters/injector.dart';
import '../../domain/errors/chat_error.dart';
import '../../../../theme/app_colors.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/queue_panel_width.dart';
import '../widgets/chat_block_view.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_thread_view.dart';
import '../widgets/participants_column.dart';
import '../widgets/permission_tray.dart';

/// O chat de uma bancada: a thread e o composer. Só compõe; o cubit nasce aqui,
/// preso à bancada, e fecha a assinatura quando a bancada troca.
class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.workbenchId,
    this.onLink,
    this.offerQueues = false,
    super.key,
  });

  final String workbenchId;

  /// Clicar num link da resposta; quem compõe decide como abrir.
  final ValueChanged<String>? onLink;

  /// Se a coluna oferece as filas da bancada, abertas num painel ao lado.
  final bool offerQueues;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(workbenchId),
    create: (_) => inject<ChatCubit>(workbenchId),
    child: _Chat(
      workbenchId: workbenchId,
      onLink: onLink,
      queueWidth: offerQueues ? inject<QueuePanelWidth>() : null,
    ),
  );
}

class _Chat extends StatefulWidget {
  const _Chat({required this.workbenchId, this.onLink, this.queueWidth});

  final String workbenchId;
  final ValueChanged<String>? onLink;

  /// A largura do painel das filas, uma só para todas as bancadas. Sem ela, a
  /// coluna não oferece filas.
  final QueuePanelWidth? queueWidth;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _thread = GlobalKey<ChatThreadViewState>();
  final _selection = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final permission = state.permission;
        final asking = permission == null
            ? null
            : state.participants
                  .where((p) => p.id == permission.agent)
                  .firstOrNull;
        final conversation = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // A seleção é da thread inteira, não de cada texto.
              child: SelectableRegion(
                selectionControls: emptyTextSelectionControls,
                focusNode: _selection,
                child: ChatThreadView(
                  key: _thread,
                  blocks: state.blocks,
                  sends: state.sends,
                  onTop: cubit.loadMore,
                  actions: ChatRowActions(
                    onToggleStep: cubit.toggleStep,
                    onCycleGroup: cubit.cycleGroup,
                    onQuote: (key) => _thread.currentState?.revealMessage(key),
                    onLink: widget.onLink,
                  ),
                ),
              ),
            ),
            if (permission != null)
              PermissionTray(
                request: permission,
                agentName: asking?.id ?? permission.agent ?? 'agente',
                onAnswer: cubit.answer,
                onChoose: cubit.choose,
                onAnswerAll: cubit.answerAll,
              ),
            if (state.queueFailure case final failure?)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text(
                  switch (failure) {
                    ChatRefused(:final message) => message,
                    ChatOffline() => 'Não foi possível criar a fila.',
                  },
                  key: const ValueKey('chat-notice'),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.attention,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ChatComposer(
              target: state.target,
              quote: state.quote,
              onClearQuote: cubit.clearQuote,
              onNextTarget: cubit.focusNext,
              onComplete: cubit.complete,
              onSend: cubit.send,
            ),
          ],
        );
        final open = state.openQueue;
        final queueWidth = widget.queueWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: open != null && queueWidth != null
                  ? ValueListenableBuilder<double?>(
                      valueListenable: queueWidth.notifier,
                      builder: (context, width, _) => QueueSidePanel(
                        key: ValueKey('queue-side-${open.id}'),
                        thread: conversation,
                        workbenchId: widget.workbenchId,
                        queueNodeId: open.id,
                        preferredWidth: width,
                        onWidth: (value) => queueWidth.notifier.value = value,
                        onClose: cubit.closeQueue,
                      ),
                    )
                  : conversation,
            ),
            if (state.participants.isNotEmpty)
              ParticipantsColumn(
                participants: state.participants,
                focused: state.target?.id,
                onPick: cubit.focusOn,
                queues: state.queues,
                shownQueue: state.openQueue?.id,
                onPickQueue: queueWidth == null ? null : cubit.toggleQueue,
                onNewQueue: queueWidth == null
                    ? null
                    : () => unawaited(cubit.newQueue()),
              ),
          ],
        );
      },
    );
  }
}
