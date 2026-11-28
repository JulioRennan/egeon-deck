import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/adapters/injector.dart';
import '../cubit/chat_composer_cubit.dart';
import '../cubit/chat_conversation_cubit.dart';
import 'chat_composer.dart';
import 'permission_trays.dart';

/// O composer embaixo do canvas (v3 "composer com rascunho"): o mesmo do chat,
/// com os mesmos cubits e as faixas de permissão acima do campo, sem a
/// conversa. Manda ao destinatário escolhido pela rota que o chat já usa.
class ChatDock extends StatelessWidget {
  const ChatDock({required this.workbenchId, this.traitsFor, super.key});

  final String workbenchId;

  /// O "modelo · esforço" do agente que recebe; a home o monta.
  final Widget Function(String nodeId)? traitsFor;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    key: ValueKey(workbenchId),
    providers: [
      BlocProvider(create: (_) => inject<ChatConversationCubit>(workbenchId)),
      BlocProvider(
        create: (context) => inject<ChatComposerCubit>((
          workbenchId: workbenchId,
          threads: context.read<ChatConversationCubit>().threads,
        )),
      ),
    ],
    child: _Dock(traitsFor: traitsFor),
  );
}

class _Dock extends StatelessWidget {
  const _Dock({this.traitsFor});

  final Widget Function(String nodeId)? traitsFor;

  @override
  Widget build(BuildContext context) {
    final conversation = context.read<ChatConversationCubit>();
    final composer = context.watch<ChatComposerCubit>();
    return BlocBuilder<ChatConversationCubit, ChatConversationState>(
      builder: (context, state) => ChatComposer(
        autofocus: false,
        margin: EdgeInsets.zero,
        target: composer.state.target,
        quote: composer.state.quote,
        participants: state.participants,
        onPickTarget: composer.focusOn,
        onClearQuote: composer.clearQuote,
        onNextTarget: composer.focusNext,
        onComplete: composer.complete,
        onSend: composer.send,
        traits: composer.state.target?.isAgent == true
            ? traitsFor?.call(composer.state.target!.id)
            : null,
        above: permissionTrays(state, conversation),
      ),
    );
  }
}
