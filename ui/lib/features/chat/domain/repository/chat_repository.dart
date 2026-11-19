import '../entities/chat_completion.dart';
import '../entities/chat_thread.dart';
import '../entities/chat_update.dart';

/// O chat de uma bancada. As linhas, o que está aberto e o histórico carregado
/// são do core Rust; aqui se escuta o diff e se manda o gesto.
abstract interface class ChatRepository {
  /// O que mudou a cada evento; a primeira entrega traz tudo num `reset`.
  Stream<ChatUpdate> watch(String workbenchId);

  /// A thread inteira, para quem perdeu uma revisão.
  Future<ChatThread> snapshot(String workbenchId);

  /// Abre ou fecha um passo (o clique no título dele).
  Future<void> toggleStep(String workbenchId, String blockId);

  /// Avança o nível da capa de uma sequência de passos.
  Future<void> cycleGroup(String workbenchId, String blockId);

  /// Carrega mais histórico (a janela cresce).
  Future<void> loadMore(String workbenchId);

  /// As sugestões do menu do composer (@menção e /slash) para o [text] e o
  /// [caret] (em UTF-16). Sem gatilho antes do cursor, a lista vem vazia.
  Future<ChatCompletion> complete(
    String workbenchId,
    String text,
    int caret, {
    String? to,
    String? search,
  });

  /// Arquiva a conversa (não é o limpar dos agentes).
  Future<void> clear(String workbenchId);

  /// Abre o link da resposta no navegador do sistema; quem abre é o core.
  Future<void> openLink(String url);

  /// Responde ao pedido de permissão: [answer] é `allow`, `always` ou `deny`;
  /// [choice] a opção escolhida de uma pergunta; [answers] as escolhas de
  /// várias perguntas (`{pergunta: [opções]}`).
  Future<void> answerPermission(
    String workbenchId,
    String request, {
    String? answer,
    String? choice,
    Map<String, List<String>>? answers,
  });

  /// Cria uma fila na bancada, ligada ao agente [agent] — o que está em foco no
  /// chat, que só a tela sabe; sem ele o core liga ao primeiro. Devolve o id do
  /// nó novo.
  Future<String> newQueue(String workbenchId, {String? agent});

  /// Manda a mensagem do composer para [to] (ids dos participantes), citando a
  /// linha de [quoteKey] se houver.
  Future<void> send(
    String workbenchId, {
    required List<String> to,
    required String text,
    String? quoteKey,
  });
}
