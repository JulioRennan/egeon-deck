import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../node/queue/presentation/widgets/queue_side_panel.dart';
import '../../../node/queue/domain/repository/queue_repository.dart';
import '../../domain/repository/chat_repository.dart';
import '../../domain/usecase/chat_actions.dart';
import '../../domain/usecase/watch_chat.dart';
import '../../../../theme/app_colors.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../cubit/queue_panel_width.dart';
import '../widgets/chat_block_view.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_thread_view.dart';
import '../widgets/participants_column.dart';
import '../widgets/permission_tray.dart';

/// O que o chat precisa para oferecer as filas da bancada: o repositório delas
/// (o da MESMA bancada) e a largura escolhida para o painel.
class ChatQueues {
  const ChatQueues({required this.repository, required this.width});

  final QueueRepository repository;
  final QueuePanelWidth width;
}

/// O chat de uma bancada: a thread e o composer. Só compõe; o cubit nasce aqui,
/// preso à bancada, e fecha a assinatura quando a bancada troca.
class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.workbenchId,
    this.onLink,
    this.queues,
    super.key,
  });

  final String workbenchId;

  /// Clicar num link da resposta; quem compõe decide como abrir.
  final ValueChanged<String>? onLink;

  /// As filas da bancada: o repositório delas e a largura do painel. Sem isto,
  /// a coluna não oferece filas.
  final ChatQueues? queues;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ChatRepository>();
    final page = BlocProvider(
      key: ValueKey(workbenchId),
      create: (_) => ChatCubit(
        workbenchId: workbenchId,
        watch: WatchChat(repository),
        actions: ChatActions(repository),
      ),
      child: _Chat(onLink: onLink, queues: queues),
    );
    final chatQueues = queues;
    return chatQueues == null
        ? page
        : RepositoryProvider<QueueRepository>.value(
            key: ValueKey(workbenchId),
            value: chatQueues.repository,
            child: page,
          );
  }
}

class _Chat extends StatefulWidget {
  const _Chat({this.onLink, this.queues});

  final ValueChanged<String>? onLink;
  final ChatQueues? queues;

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
            if (state.notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text(
                  state.notice!,
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
        final queues = widget.queues;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: open != null && queues != null
                  ? ValueListenableBuilder<double?>(
                      valueListenable: queues.width.notifier,
                      builder: (context, width, _) => QueueSidePanel(
                        key: ValueKey('queue-side-${open.id}'),
                        thread: conversation,
                        queueNodeId: open.id,
                        preferredWidth: width,
                        onWidth: (value) => queues.width.notifier.value = value,
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
                onPickQueue: queues == null ? null : cubit.toggleQueue,
                onNewQueue: queues == null
                    ? null
                    : () => unawaited(cubit.newQueue()),
              ),
          ],
        );
      },
    );
  }
}
