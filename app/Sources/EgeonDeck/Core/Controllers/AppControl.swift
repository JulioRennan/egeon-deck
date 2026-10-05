import Foundation

/// Ganchos que a UI publica para o socket de controle. Evita o socket segurar
/// referência ao AppDelegate e permite dirigir o app de fora — o que também é
/// o que a extensão do VSCode precisa para trocar de bancada.
enum AppControl {
    static var activateWorkbench: ((String) -> Bool)?
    static var workbenchNames: (() -> [String])?
    /// Workspaces → projetos → nomes de bancada, como a barra lateral lista.
    static var workspacesSnapshot: (() -> [String: Any])?

    /// Troca dois cards de painel no mosaico da bancada ativa.
    ///
    /// O gesto de arrastar o cabeçalho não é dirigível de fora — evento de mouse
    /// sintético exige permissão de Acessibilidade, que a assinatura ad-hoc perde a
    /// cada build (ADR-003). O que precisa ser verificado é o arranjo: quem foi para
    /// qual painel, e se aquilo sobreviveu ao `workbenches.json`.
    static var swapMosaic: ((_ workbench: String, _ first: String, _ second: String)
                            -> [String: Any])?

    /// Direção de uma ligação: criar, apontar para um lado, ou ciclar.
    ///
    /// Existe pelo mesmo motivo do `swapMosaic`: desenhar aresta é arrasto e trocar
    /// direção é clique num botão de 24pt, e nenhum dos dois é dirigível de fora —
    /// evento sintético exige Acessibilidade, que a assinatura ad-hoc perde a cada
    /// build (ADR-003). Sem esta rota não há como verificar que o par nasce nos dois
    /// sentidos nem que o ciclo do botão passa onde deve.
    static var setEdgeDirection: ((_ workbench: String, _ from: String, _ to: String,
                                   _ direction: String) -> [String: Any])?

    /// PNG do card de um nó — cabeçalho, borda e corpo, como está na tela.
    ///
    /// Mudança que é só desenho não tem log nem DOM para conferir: ou se olha a
    /// imagem, ou se acredita. Devolve o caminho do arquivo, ou o erro.
    static var cardSnapshot: ((_ target: String, _ file: URL) -> String)?

    /// Remove uma bancada, opcionalmente apagando as worktrees dela.
    ///
    /// Existe pelo mesmo motivo que `makeWorktree`: o fluxo passa por `NSAlert`, que
    /// não é dirigível de fora, e "apaguei todas as worktrees" é exatamente o tipo
    /// de afirmação que precisa ser conferida em repositório de verdade. Responde
    /// pelo `completion`, no fim: apagar worktree roda na fila de fundo.
    static var removeWorkbench: ((_ name: String, _ purge: Bool,
                                  _ completion: @escaping ([String: Any]) -> Void) -> Void)?

    /// Qual bancada é dona de uma pasta.
    ///
    /// A extensão do editor sabe a pasta do workspace e mais nada — quem conhece
    /// a topologia é o app. Sem isto, a única lista que ela conseguia pedir era a
    /// global, e o editor de um projeto sugeria terminal de outro.
    static var workbenchOwning: ((String) -> String?)?
    /// Geometria dos nós do canvas ativo, já em coordenadas de tela com origem
    /// no topo — as mesmas do CGEvent. Serve para dirigir e verificar gestos de
    /// fora sem depender de estimar pixel em captura de tela.
    static var canvasGeometry: (() -> [String: Any])?

    /// Troca a visualização da bancada ativa — canvas ou mosaico.
    ///
    /// Existe pelo mesmo motivo que `/geometry`: dirigir e verificar o app de fora
    /// sem depender de gesto na tela. Nulo de volta significa modo desconhecido ou
    /// nenhuma bancada ativa.
    /// Troca o modelo ou o esforço de um terminal com IA e o reinicia.
    /// Nil/vazio = padrão.
    static var setNodeModel: ((_ target: String, _ choice: ModelChoice) -> String?)?

    /// Quem atende o terminal maestro: lê a bancada, mostra o plano e aplica
    /// (ADR-066). Montado pelo AppDelegate, que é o dono do `workbenches.json`.
    static var maestro: MaestroController?

    /// Liga ou desliga o maestro de um nó, de fora. O checkbox do formulário
    /// passa por `NSAlert`, que não é dirigível sem Acessibilidade (ADR-003).
    /// Nil de volta é sucesso; senão, o erro.
    static var setMaestro: ((_ target: String, _ on: Bool) -> String?)?
    static var setViewMode: ((String) -> String?)?

    /// Recolher a barra de bancadas ao trilho, ou abrir.
    ///
    /// Existe pelo mesmo motivo que `/mosaic?swap=`: recolher é tecla de menu e
    /// clique, e nenhum dos dois é dirigível de fora sem permissão de
    /// Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003). Sem
    /// esta rota não há como conferir de fora o que a barra faz por cima de um
    /// card. Devolve se ficou recolhida.
    static var collapseSidebar: ((Bool) -> Bool)?

    /// O mesmo que o ⌘/ e o botão da barra fazem. Devolve se ficou recolhida.
    static var toggleSidebar: (() -> Bool)?

    /// Cria worktree e reaponta: `bancada` duplica a bancada inteira levando os
    /// terminais de repo vizinho junto, `bancada/nó` leva só aquele terminal.
    ///
    /// Existe pelo mesmo motivo que `/geometry` e `/layout`: o fluxo passa por
    /// `NSAlert`, que não é dirigível de fora, e sem isto não haveria como
    /// verificar que cada terminal foi para a pasta certa — que é justamente o
    /// defeito que este código conserta. Devolve o que aconteceu, ou o erro.
    static var makeWorktree: ((_ target: String, _ branch: String,
                              _ nodeBranches: [String: String]) -> [String: Any])?

    /// Ligações e teto de revisitas de uma bancada, por nome.
    ///
    /// O Dispatcher precisa dos dois para validar mensagem entre agentes, e não
    /// conhece o `workbenches.json` — quem conhece é o AppDelegate. Mesmo arranjo
    /// dos ganchos acima, e pelo mesmo motivo: evita o Dispatcher segurar
    /// referência à UI.
    static var workbenchEdges: ((String) -> [EdgeConfig])?
    static var workbenchVisitLimit: ((String) -> Int)?
    /// Papel do nó, para a lista de vizinhos dizer o que cada um faz — sem isso
    /// o agente lê endereços e não tem como escolher entre dois irmãos.
    static var nodeRole: ((String) -> String?)?
    /// O nó pode montar a bancada (ADR-066) — vai no `egeon status`, que é
    /// por onde o agente descobre se tem esse poder.
    static var nodeIsMaestro: ((String) -> Bool)?

    /// Com o que o nó está rodando, para a trilha da bancada carimbar cada
    /// registro: nome do CLI, modelo literal em uso e id da conversa. O agente
    /// escreve o texto; isto ele não escolhe (ADR-036).
    static var nodeIdentity: ((String) -> (cli: String?, model: String?, conversation: String?,
                                           workbenchID: String)?)?

    /// Um turno acabou neste terminal (gancho `Stop`), e o transcript já foi
    /// conferido. É o instante em que o turno está inteiro e ainda se sabe
    /// qual é: `notBefore` é quando o prompt dele chegou (ADR-037).
    static var turnEnded: ((_ address: String, _ transcript: URL?, _ notBefore: Date?) -> Void)?

    /// "Limpar a conversa" do chat da bancada: arquiva o `chat.jsonl` e começa
    /// outro. Devolve o payload da rota.
    static var clearChat: ((_ workbench: String) -> [String: Any])?

    /// "Limpar a bancada": o `clear` do perfil em todo agente que tem um e,
    /// DEPOIS de eles assentarem, a conversa e a trilha arquivadas — por isso o
    /// payload vem por closure e não de volta (ADR-059). Sem confirmação — a
    /// rota é você.
    static var clearWorkbench: ((_ workbench: String,
                                 _ done: @escaping ([String: Any]) -> Void) -> Void)?

    /// O CLI avisou qual conversa está aberta neste terminal. Chamado a cada
    /// prompt, então quem implementa só grava quando o valor muda de fato.
    static var recordConversation: ((_ target: String, _ id: String, _ transcript: String?) -> Void)?

    /// A faixa de bancadas abertas como dados: uma linha por aba, a ativa
    /// marcada e os badges por extenso. Existe pelo mesmo motivo do `/peek`:
    /// conferir o que está na tela sem comparar pixels.
    static var tabsSnapshot: (() -> [String: Any])?

    /// Reordena a faixa: leva a aba desta bancada para a posição dada. Arrasto
    /// não é dirigível de fora sem Acessibilidade (ADR-003).
    static var moveTab: ((_ workbench: String, _ position: Int) -> [String: Any])?

    /// Fecha a aba de uma bancada — sem encerrar nada. O x da pastilha não é
    /// dirigível de fora sem Acessibilidade (ADR-003), e esta é a mesma operação.
    static var closeTab: ((_ workbench: String) -> [String: Any])?

    /// O modo chat de uma bancada como dados: participantes, foco, popup, caixa.
    /// Existe pelo mesmo motivo do `/peek`: conferir a tela sem comparar pixels.
    static var chatState: ((String) -> [String: Any]?)?

    /// Rola a thread do chat por fora: "top" ou "bottom".
    static var chatScroll: ((_ workbench: String, _ edge: String) -> Void)?
    /// Escolhe o participante em foco por fora, como o clique na coluna.
    static var chatFocus: ((_ workbench: String, _ id: String) -> Void)?
    /// Reposiciona um item da árvore: workspace, projeto ou bancada (ADR-051).
    /// `parent` é o workspace do projeto ou o projeto da bancada.
    static var moveInTree: ((_ kind: String, _ id: String, _ parent: String,
                            _ position: Int) -> [String: Any])?

    /// Abre ou recolhe um passo por fora, como o clique no título dele: clique
    /// sintético exige Acessibilidade, que a assinatura ad-hoc perde a cada
    /// build (ADR-003).
    static var chatExpandStep: ((_ workbench: String, _ blockId: String) -> Void)?

    /// Escreve na caixa do chat, sem enviar ou enviando, e devolve o estado.
    /// Tecla sintética exige Acessibilidade, que a assinatura ad-hoc perde a
    /// cada build (ADR-003) — sem esta rota o composer não se verifica de fora.
    static var chatCompose: ((_ workbench: String, _ text: String, _ send: Bool)
                             -> [String: Any]?)?
}
