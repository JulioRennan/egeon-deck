import 'package:flutter/widgets.dart';

import '../cubit/chat_conversation_cubit.dart';
import 'permission_tray.dart';

/// Uma faixa por pedido de permissão em aberto, na ordem do core (dois agentes
/// pedindo ao mesmo tempo): é o que o composer, do chat e do canvas, leva acima
/// do campo.
List<Widget> permissionTrays(
  ChatConversationState state,
  ChatConversationCubit cubit,
) => [
  for (final permission in state.permissions)
    PermissionTray(
      key: ValueKey('permission-${permission.id}'),
      request: permission,
      // Quem pediu, pelo endereço que o core manda; sem participante com ele,
      // o próprio endereço.
      agentName:
          state.participants
              .where(
                (p) =>
                    p.address == permission.address || p.id == permission.agent,
              )
              .firstOrNull
              ?.id ??
          permission.address ??
          permission.agent ??
          'agente',
      onAnswer: cubit.answer,
      onChoose: cubit.choose,
      onAnswerAll: cubit.answerAll,
    ),
];
