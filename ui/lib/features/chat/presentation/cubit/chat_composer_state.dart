part of 'chat_composer_cubit.dart';

/// Para quem o composer manda e o que ele cita.
sealed class ChatComposerState {
  const ChatComposerState({this.target, this.quote, this.queueAgent});

  /// O destino: quem está em foco, se vive; senão o primeiro agente vivo.
  final ChatParticipantInfo? target;

  /// A linha que o composer está citando, se houver.
  final ChatBlock? quote;

  /// O agente a que uma fila nova se liga: o em foco, senão o primeiro.
  final String? queueAgent;
}

/// Ninguém vivo na conversa: não há para quem mandar.
final class ComposerNobody extends ChatComposerState {
  const ComposerNobody({super.queueAgent});
}

/// Para um agente: a thread fica na tela.
final class ComposerToAgent extends ChatComposerState {
  const ComposerToAgent(
    ChatParticipantInfo agent, {
    super.quote,
    super.queueAgent,
  }) : super(target: agent);
}

/// Para um shell: clicar nele é querer VER o terminal, que entra no lugar da
/// thread (se já tem tela). Enter manda comando para ele; se o shell morre, o
/// foco cai num agente e a thread volta.
final class ComposerToShell extends ChatComposerState {
  const ComposerToShell(
    ChatParticipantInfo shell, {
    super.quote,
    super.queueAgent,
  }) : super(target: shell);
}
