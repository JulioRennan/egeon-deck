import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../node/queue/presentation/widgets/queue_side_panel.dart';
import '../../../node/terminal/presentation/widgets/terminal_body.dart';
import '../../../../core/adapters/injector.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/errors/chat_error.dart';
import '../../../../theme/egeon_colors.dart';
import '../../di/chat_injection.dart';
import '../cubit/chat_composer_cubit.dart';
import '../cubit/chat_conversation_cubit.dart';
import '../cubit/chat_queue_panel_cubit.dart';
import '../cubit/queue_panel_width.dart';
import '../widgets/chat_block_view.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_thread_view.dart';
import '../widgets/participants_column.dart';
import '../widgets/permission_trays.dart';
import '../widgets/size_reporter.dart';
import '../../../../commons/widgets/shell_layers.dart';

/// O chat de uma bancada: a thread e o composer. Só compõe; o cubit nasce aqui,
/// preso à bancada, e fecha a assinatura quando a bancada troca.
class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.workbenchId,
    this.offerQueues = false,
    this.traitsFor,
    super.key,
  });

  final String workbenchId;

  /// O "modelo · esforço" do agente que recebe, ao lado do enviar: quem junta o
  /// chat ao estado do agente é a home.
  final Widget Function(String nodeId)? traitsFor;

  /// Se a coluna oferece as filas da bancada, abertas num painel ao lado.
  final bool offerQueues;

  ChatFeed _feed(BuildContext context) => (
    workbenchId: workbenchId,
    threads: context.read<ChatConversationCubit>().threads,
  );

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    key: ValueKey(workbenchId),
    providers: [
      BlocProvider(create: (_) => inject<ChatConversationCubit>(workbenchId)),
      BlocProvider(
        create: (context) => inject<ChatComposerCubit>(_feed(context)),
      ),
      BlocProvider(
        create: (context) => inject<ChatQueuePanelCubit>(_feed(context)),
      ),
    ],
    child: _Chat(
      workbenchId: workbenchId,
      traitsFor: traitsFor,
      queueWidth: offerQueues ? inject<QueuePanelWidth>() : null,
    ),
  );
}

class _Chat extends StatefulWidget {
  const _Chat({required this.workbenchId, this.traitsFor, this.queueWidth});

  final String workbenchId;
  final Widget Function(String nodeId)? traitsFor;

  /// A largura do painel das filas, uma só para todas as bancadas. Sem ela, a
  /// coluna não oferece filas.
  final QueuePanelWidth? queueWidth;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _thread = GlobalKey<ChatThreadViewState>();

  /// A conversa muda de pai quando o painel da fila abre ou fecha; com a
  /// chave ela é a mesma, e o texto do composer não se perde.
  final _conversation = GlobalKey(debugLabel: 'conversation');
  final _selection = FocusNode(skipTraversal: true);

  /// A altura do composer que flutua: a conversa guarda esse espaço embaixo.
  final _composerHeight = ValueNotifier<double>(0);
  final _composer = FocusNode(debugLabel: 'composer');
  StreamSubscription<void>? _sent;
  StreamSubscription<ChatError>? _refusals;

  /// A recusa ao criar uma fila, numa linha que some sozinha.
  ChatError? _refusal;
  Timer? _refusalTimer;

  /// Quanto a recusa ao criar uma fila fica na tela.
  static const refusalTime = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    // Cada mensagem sua leva a thread ao fim, de onde quer que esteja.
    _sent = context.read<ChatComposerCubit>().sent.listen(
      (_) => _thread.currentState?.jumpToEnd(),
    );
    _refusals = context.read<ChatQueuePanelCubit>().refusals.listen((error) {
      _refusalTimer?.cancel();
      setState(() => _refusal = error);
      _refusalTimer = Timer(refusalTime, () {
        if (mounted) setState(() => _refusal = null);
      });
    });
  }

  /// Escolher alguém na coluna é para falar com ele: o teclado vai ao
  /// composer, mesmo quando o escolhido é um shell e o terminal aparece.
  void _pick(ChatComposerCubit composer, String id) {
    composer.focusOn(id);
    _composer.requestFocus();
  }

  /// Fechar o painel devolve o teclado ao composer, como o Swift; abrir o
  /// leva para "Nova tarefa" da fila.
  void _toggleQueue(ChatQueuePanelCubit panel, String id) {
    panel.toggle(id);
    if (panel.state is QueuePanelClosed) _composer.requestFocus();
  }

  void _closeQueue(ChatQueuePanelCubit panel) {
    panel.closePanel();
    _composer.requestFocus();
  }

  @override
  void dispose() {
    unawaited(_sent?.cancel());
    unawaited(_refusals?.cancel());
    _refusalTimer?.cancel();
    _composer.dispose();
    _selection.dispose();
    _composerHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatConversationCubit>();
    final composer = context.watch<ChatComposerCubit>();
    final panel = context.watch<ChatQueuePanelCubit>();
    final target = composer.state.target;
    return BlocBuilder<ChatConversationCubit, ChatConversationState>(
      builder: (context, state) {
        final conversation = KeyedSubtree(
          key: _conversation,
          child: ValueListenableBuilder<double>(
            valueListenable: _composerHeight,
            builder: (context, composerHeight, _) {
              // O composer flutua (como o do canvas); o respiro embaixo é a
              // altura dele, a margem da camada e um pouco de ar.
              final inset = composerHeight == 0
                  ? 0.0
                  : composerHeight + ShellLayers.bottomMargin + ShellLayers.gap;
              return Stack(
                children: [
                  Positioned.fill(
                    child: switch (composer.state) {
                      // O shell em foco no lugar da thread: o mesmo terminal do
                      // canvas, sem tomar o teclado do composer.
                      ComposerToShell(
                        target: ChatParticipantInfo(:final screen?),
                      ) =>
                        Padding(
                          padding: EdgeInsets.only(bottom: inset),
                          child: TerminalBody(
                            key: ValueKey('chat-terminal-$screen'),
                            nodeId: screen,
                          ),
                        ),
                      // A seleção é da thread inteira, não de cada texto.
                      _ => SelectableRegion(
                        selectionControls: emptyTextSelectionControls,
                        focusNode: _selection,
                        child: ChatThreadView(
                          key: _thread,
                          blocks: state.blocks,
                          bottomInset: inset,
                          mentions: {
                            for (final p in state.participants)
                              if (p.isAgent) p.id,
                          },
                          onTop: cubit.loadMore,
                          actions: ChatRowActions(
                            onToggleStep: cubit.toggleStep,
                            onCycleGroup: cubit.cycleGroup,
                            onQuote: (key) =>
                                _thread.currentState?.revealMessage(key),
                            onLink: cubit.openLink,
                          ),
                        ),
                      ),
                    },
                  ),
                  Positioned.fill(
                    child: ShellLayers(
                      permissions: _refusal == null
                          ? null
                          : Text(
                              switch (_refusal!) {
                                ChatRefused(:final message) => message,
                                ChatOffline() =>
                                  'Não foi possível criar a fila.',
                              },
                              key: const ValueKey('chat-notice'),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.eg.attention,
                                decoration: TextDecoration.none,
                              ),
                            ),
                      composer: SizeReporter(
                        onHeight: (h) => _composerHeight.value = h,
                        child: ChatComposer(
                          focusNode: _composer,
                          margin: EdgeInsets.zero,
                          participants: state.participants,
                          onPickTarget: (id) => _pick(composer, id),
                          // Dois agentes pedindo ao mesmo tempo: uma faixa por
                          // pedido, na ordem do core, dentro do composer.
                          above: permissionTrays(state, cubit),
                          target: target,
                          quote: composer.state.quote,
                          onClearQuote: composer.clearQuote,
                          onNextTarget: composer.focusNext,
                          onComplete: composer.complete,
                          onSend: composer.send,
                          traits: target?.isAgent == true
                              ? widget.traitsFor?.call(target!.id)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
        final open = switch (panel.state) {
          QueuePanelOpen(:final queue) => queue,
          QueuePanelClosed() => null,
        };
        final queueWidth = widget.queueWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.participants.isNotEmpty)
              ParticipantsColumn(
                participants: state.participants,
                focused: target?.id,
                onPick: (id) => _pick(composer, id),
                queues: panel.state.queues,
                shownQueue: open?.id,
                onPickQueue: queueWidth == null
                    ? null
                    : (id) => _toggleQueue(panel, id),
                onNewQueue: queueWidth == null
                    ? null
                    : () => unawaited(
                        panel.newQueue(agent: composer.state.queueAgent),
                      ),
              ),
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
                        onClose: () => _closeQueue(panel),
                      ),
                    )
                  : conversation,
            ),
          ],
        );
      },
    );
  }
}
