import Foundation

/// Ganchos que a UI publica para o socket de controle. Evita o socket segurar
/// referência ao AppDelegate e permite dirigir o app de fora — o que também é
/// o que a extensão do VSCode precisa para trocar de bancada.
enum AppControl {
    static var activateWorkbench: ((String) -> Bool)?
    static var workbenchNames: (() -> [String])?

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
    /// de afirmação que precisa ser conferida em repositório de verdade.
    static var removeWorkbench: ((_ name: String, _ purge: Bool) -> [String: Any])?

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

    /// O CLI avisou qual conversa está aberta neste terminal. Chamado a cada
    /// prompt, então quem implementa só grava quando o valor muda de fato.
    static var recordConversation: ((_ target: String, _ id: String, _ transcript: String?) -> Void)?

    /// O thread do modo Chat de uma bancada, como dados.
    ///
    /// Existe pelo mesmo motivo do `/peek`: o thread é montado de vários arquivos,
    /// e "a mensagem do dev-backend apareceu depois da sua, com o diff certo" é
    /// exatamente o tipo de afirmação que não se confere olhando print. Aqui dá
    /// para ver a ordem, o autor e os blocos de cada mensagem sem abrir o app.
    static var chatThread: ((String) -> [String: Any]?)?

    /// Escreve na caixa do modo Chat, sem enviar, e devolve a geometria.
    ///
    /// Existe pelo mesmo motivo do `swapMosaic` e do `setEdgeDirection`: crescer a
    /// caixa é digitar, e tecla sintética exige Acessibilidade, que a assinatura
    /// ad-hoc perde a cada build (ADR-003). Sem esta rota, "a caixa cresce para cima e
    /// o histórico cede a área" é afirmação sem evidência.
    static var chatCompose: ((_ workbench: String, _ text: String, _ send: Bool)
                             -> [String: Any]?)?
}
