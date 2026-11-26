# Changelog

Todas as mudanças notáveis do Egeon Deck ficam neste arquivo.

O formato segue o [Keep a Changelog 1.1.0](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adota o [Versionamento Semântico 2.0.0](https://semver.org/lang/pt-BR/).
O porquê de cada decisão está nos ADRs de [`docs/01-decisoes.md`](docs/01-decisoes.md),
citados entre parênteses.

## [Unreleased]

### Adicionado

- "Novo projeto…" no menu do workspace: dá nome, escolhe a pasta-mãe (sugere a que os projetos dele já dividem) e cria a pasta, com `git init` se quiser, sem sair do app (ADR-092).
- A gaveta de bancadas abre ao passar o mouse na faixa do trilho, à esquerda da bancada, e fecha ao tirar; clicar no botão a deixa aberta (decisão 44).
- App para Linux (x86_64 e arm64): AppImage, que se atualiza sozinho como no macOS, e .deb, que avisa da versão nova com o link; terminais, agentes, notificações e a janela de Processos (decisão 52).

### Alterado

- A janela Processos volta a ser uma janela própria do sistema, como no Egeon de hoje: dá para movê-la para fora do app ou para outra tela, e ela reabre onde estava (decisão 51).
- Ao abrir o app, os projetos que têm bancada aparecem abertos e no topo do workspace.
- A cor da bancada na moldura fica mais forte.
- Escolher uma bancada pela gaveta não a fecha mais; ela fecha pelo clique fora, pelo Esc, pelo ⌘/ ou quando o mouse sai.
- O trilho à esquerda mostra as bancadas ativas, na ordem da aba Ativas, em vez das abas abertas; ⌘1…⌘9 seguem essa lista.
- A janela perde a barra de título: a faixa de cima agora tem voltar e avançar (⌘[ ⌘]), a troca Canvas | Chat (só ícones, com o nome e o atalho na dica) e o caminho projeto / bancada, e arrasta a janela; a área da bancada ganha uma moldura com a cor dela. A faixa de abas sai da casca (decisão 45).
- A barra lateral vira a gaveta de bancadas: abre pelo trilho de bancadas à esquerda (cada bancada com as iniciais na cor dela e o estado), por cima do canvas ou ao lado no chat, fecha com Esc; ⌘K também a abre (decisão 46).
- A barra lateral ganha o visual novo: cabeçalho com Todas | Ativas (com o ponto de atenção), busca por bancada, projeto e workspace (⌘K a abre e foca) e "Novo"; as linhas mostram o estado em texto curto e, embaixo, o custo, e o ⋯ de cada nível abre um menu de vidro (salvar como template, copiar caminho do projeto…) (decisão 44).
- A barra lateral ganha o painel de filtros: mostrar só o que espera você, está em trabalho ou terminou, agrupar por workspace › projeto ou por última atividade, e ver um workspace só; o botão mostra quantos filtros estão ligados. O item arrastado ganha sombra (decisão 44).
- O canvas ganha o visual novo: fundo liso com grade de pontos, barra de ações em vidro (ferramentas, zoom, template e worktree, enquadrar), dica "Esc cancela" enquanto uma ferramenta de criar está ligada, e Esc desliga a ferramenta (decisão 44).
- No canvas, Shell e Terminal de agente são ferramentas separadas (o shell nasce na hora, sem formulário); o menu do agente mostra os componentes salvos com CLI, modelo e esforço; o menu Template ▾ salva ou atualiza o template; e a cor da bancada se troca por uma grade de 12 cores na barra. As ligações ficam cinza e a selecionada fica azul, com o rótulo do limite (decisão 44).
- Os cards do canvas ganham o visual novo: moldura com anel (agente na cor de identidade, "precisa de você" em laranja, maestro com faixa, etiqueta e anel maior), cabeçalho com o ponto de estado, caminho curto e ações; linha de controles do agente com modelo, esforço (com Automático no menu), ultracode e contexto (menus de vidro e o diálogo de limpar o contexto); o terminal passa para a fonte JetBrains Mono 14 e a paleta nova (decisão 44).
- O card web ganha a barra nova (voltar, avançar, recarregar, endereço no campo do tema e o perfil num menu), e a fila de prompts passa para as cores do tema, com o spinner na tarefa que o agente está fazendo (decisão 44).
- O chat ganha o visual novo: mensagem sua na bolha, respostas corridas com nome na cor do agente, capa de passos, diff lado a lado com número de linha e a conversa vazia com um convite. A coluna de participantes vai para a esquerda, a permissão (Permitir · Sempre · Negar) fica dentro do composer, e o composer vira um cartão de vidro com "Para <agente>" e os botões de / e @. No chat, o composer flutua sobre a conversa, no mesmo lugar do canvas. O composer também aparece embaixo do canvas, para falar com um agente sem sair dele; a hora e o custo de cada resposta ficam ao lado do nome, sempre à vista; e cada agente tem a mesma cor no canvas e no chat (decisões 44 e 45).
- O consumo da bancada vira um chip de vidro no canto, no canvas e no chat, com o cronômetro (trabalhando e esperando você) e o custo; o clique abre o painel com os tempos, o topo por agente e, em Por modelo, o total por tarifa, a tabela de preços e "Zerar cronômetro" (decisão 44).
- Os formulários (bancada, workspace, projeto, multi-projeto, worktree, terminal e agente) e os diálogos de confirmar, perguntar e avisar ganham o visual novo: janela de 440, campos, caixas, rádios e seleção do tema, Cancelar discreto e, nas ações que apagam, a lixeira em vermelho. A cor da bancada se escolhe na mesma grade de 12 cores (decisão 44).
- O trilho de bancadas ganha arrastar para reordenar e, no botão direito, "Fechar bancada" (a bancada segue rodando), além do ⌘W (decisão 45).
- A janela Processos ganha a tabela do tema: processo com o ponto de estado, a etiqueta "órfão", o nó na cor dele, PID e tempo, e o filtro Todos | Órfãos (decisão 44).
- O aviso de "você está na última versão" e os outros avisos de uma linha do app viram um aviso passageiro no pé da tela, e o de versão nova usa a caixa do tema (decisão 44).
- O aviso do shell e as cortinas "Um instante" e "Sem acesso à pasta" usam o visual novo, com vidro e os botões do tema (decisão 44).
- O card do maestro fica sempre amarelo — faixa no topo, cabeçalho tingido, nome, etiqueta "maestro", borda e brilho —, em vez da cor do agente (decisão 44).
- A fila de prompts usa os botões, o menu e a caixa "Automático" do tema (decisão 44).
- Noto Sans e JetBrains Mono vêm embutidas no app, que passa a abrir com o mesmo texto offline e em qualquer máquina (decisão 44).
- A gaveta de bancadas fica como no design: sem título nem ✕, uma linha só com as abas Todas | Ativas (sublinhado que desliza), buscar, filtrar, novo e recolher; cada bancada mostra todos os estados de uma vez ("1 terminou", "2 em trabalho") e o traço dela sobre o fio da árvore; o nome do projeto fica em destaque e o lugar dos selos de stack está reservado (decisão 44).
- A barra de ações usa o ícone de enquadrar da v3 (cantos com alvo); o menu de componentes pinta o nome na cor e mostra o esforço em português, o select de esforço do formulário de agente também, e o botão de limpar o contexto do card vira o ↻ da v3 (decisão 44).
- No trilho, o selo de pedidos no botão da gaveta fica menor, em pílula laranja, e o ponto verde de "terminou" também aparece na bancada que está na tela (decisão 45).
- A linha de controles do agente ganha fios entre os grupos e o ↻ de limpar o contexto (o Automático do esforço fica no menu dele); o card da fila mostra "Fila de prompts" (decisão 44).
- O card da fila mostra embaixo do título quantas tarefas esperam ("nada pendente", "2 pendentes"), como no Swift (decisão 44).
- O menu do workspace ganha "Recolher tudo", que fecha todos os projetos abertos dele (decisão 44).

### Corrigido

- Colar e copiar no terminal voltam a funcionar pelo ⌘V/⌘C e pelo menu Editar.
- Colar, copiar, selecionar tudo e desfazer (⌘V, ⌘C, ⌘A, ⌘Z) funcionam nos campos das janelas de formulário (nova bancada, terminal, workspace, renomear).
- Os menus da barra do macOS (o do app, Editar, Canvas…) não fecham mais sozinhos logo depois de abertos.
- Os cards de uma bancada não somem mais quando um agente fica aguardando um vizinho: o canvas ficava vazio até ele responder.
- O app de teste (dev) não liga mais ao app de uso por engano: build de depuração e o bundle "Dev" sempre usam a pasta do dev, mesmo quando o macOS perde a variável que os distinguia.
- O custo dos agentes em modelos que só o Claude Code instalado conhece (como o Fable 5.2) volta a ser calculado; o que já tinha sido contado sem preço ganha o valor, e o `pricing.json` editado vale sem reabrir o app (ADR-085).
- O modo de voz do Claude Code grava no terminal: o app pede o microfone ao macOS, como o Egeon de hoje; o navegador volta a abrir servidores locais (http://127.0.0.1).
- Ícone novo: a mão do maestro segurando os fios de vários terminais, flat e monocromático; o app de desenvolvimento ganha a mesma mão em branco sobre azul (decisão 44).
- Clicar num botão não deixa mais a borda de foco presa nele (abas Todas/Ativas, trilho, barra de ações e demais botões) (decisão 44).
- Em janela estreita a barra de ações do canvas não passa mais por baixo do chip de consumo (anda para a esquerda até o chip), o chat com a gaveta aberta não estoura, e a janela ganha um tamanho mínimo de 1000 × 600 (decisão 44).
- Os botões vermelho, amarelo e verde da janela ficam na mesma linha de voltar, avançar, Canvas | Chat e do caminho da bancada (decisão 45).
- O esforço do agente aparece em português na faixa do card e no menu (baixo, médio, alto, extra alto, máximo), como no design (decisão 44).

## [1.8.0] - 2026-11-04

### Adicionado

- A fila de prompts também no modo chat: a coluna ganhou a seção Filas, com o que está pendente e a pergunta em laranja; o clique abre a mesma lista num painel ao lado da conversa, com o composer funcionando e uma divisória para ajustar a largura, e "+ Nova fila" cria uma já ligada ao agente em foco (ADR-088).

### Alterado

- Na fila de prompts, cada tarefa agora é um texto corrido, sem título e notas separados, e o texto quebra sozinho em todo lugar, inclusive em "Nova tarefa…" e na resposta da thread: a lista mostra o texto inteiro, o clique deixa editar ali mesmo, Enter cria a próxima e ⇧Enter quebra linha; depois de enviada, a tarefa não muda mais, e a conversa segue pela thread; tarefas antigas têm título e notas juntados (ADR-088).
- No cabeçalho do agente, "auto" agora é uma pílula ao lado da barra de esforço: ligada, a barra aparece apagada no nível que o modelo usa; mexer na barra fixa o nível e desliga o auto. Não se confunde mais auto com um nível escolhido (ADR-090).
- No cabeçalho do agente, a faixa de modelo e esforço agora mostra o contexto em uso numa pizza com a porcentagem, que vai do verde ao vermelho conforme enche, e ganhou um ícone de limpeza, que limpa a conversa daquele agente depois de confirmar (ADR-091).

## [1.7.1] - 2026-10-31

### Corrigido

- Apagar a última bancada não traz mais de volta, na próxima abertura, as bancadas de um arquivo antigo (`sessions.json`), com os agentes delas subindo sozinhos.
- Sem nenhuma bancada, o aviso "Nenhuma bancada" não fica mais escrito por cima do workspace na barra lateral: aparece abaixo dele.

## [1.7.0] - 2026-10-30

### Adicionado

- O app avisa ao abrir quando há versão nova e atualiza com um clique; o menu ganhou "Procurar atualizações…" e "Atualizar automaticamente", que baixa sozinho e troca o app só quando você fechar, para nunca derrubar agentes. Cada versão vem com assinatura própria, conferida antes de instalar (ADR-089).
- O site explica, junto do botão de baixar, o passo para o macOS abrir o app, que ainda não tem assinatura da Apple.
- Fila de prompts, um tipo de nó novo na barra do canvas: uma lista de tarefas como no Things — cada tarefa é uma linha, e o clique abre ali mesmo para editar o título, escrever as notas e colar prints (⌘V, ou arrastar a imagem); "Nova tarefa…" no fim anota várias seguidas, uma por Enter; arrastar a linha muda a ordem. Ligue a fila a um agente arrastando o `+` da borda até ele e mande um a um — pelo botão de cada item ou no automático, que manda o próximo quando o agente termina o turno e espera enquanto ele pergunta algo a você. As imagens chegam ao Claude Code como anexo de verdade, não como caminho no texto. Cada tarefa é uma thread com o agente: ele marca a tarefa como feita, pergunta ou comenta por ela (`egeon task done|ask|note`), a pergunta aparece no cartão com a bolinha laranja e a fila espera você responder ali mesmo (ADR-088).

### Corrigido

- O build não roda mais `npm run dev` sem querer na pasta em que é feito.

## [1.6.0] - 2026-10-30

### Adicionado

- Consumo de tokens e custo por bancada: a barra lateral mostra quanto cada bancada já custou; no canvas, uma barra informativa sob a barra de ações mostra o custo, e o clique abre o detalhe — para onde foi o dinheiro (entrada, saída, cache escrito e cache lido), cada agente e cada modelo, e a tabela de preços; no chat, cada resposta diz quanto aquele turno custou e cada agente mostra o que já gastou. Os preços vêm do próprio Claude Code instalado e se atualizam com ele; o custo fica no preço do dia em que foi gasto — preço novo só vale dali para frente; exceções à mão em `pricing.json` (ADR-085).
- Cada bancada ganha uma cor sozinha, a menos usada entre as que existem: uma sombra esmaecida dessa cor contorna o canvas por dentro e um ponto dela acompanha o nome da bancada na barra de cima, que ficou maior, o card em que você está digitando e a bancada selecionada na barra lateral levam essa cor na borda, e a bolinha de "de pé" da barra lateral deixou de ser verde e passou a ser essa cor — dá para saber em que bancada você está antes de ler o nome (ADR-086).
- A cor da bancada se troca à mão: o clique na bolinha ao lado do nome (agora maior) ou "Cor da bancada…" no menu de contexto da barra lateral abre uma paleta de 24 cores em grade, com o nome de cada uma ao passar o mouse; a bolinha de "de pé" da barra lateral também cresceu (ADR-086).
- A última versão fica sempre no mesmo endereço, `releases/latest/download/EgeonDeck.zip`: toda release passa a trazer esse zip de nome fixo, além dos dois com a versão no nome.
- O site mostra a última versão publicada e a data dela, lidas da própria release, ao lado do botão de baixar.
- "Sobre o Egeon Deck", no topo do menu do app: mostra a versão instalada e o commit de que ela foi construída.
- O `/` no chat lista tudo o que o Claude Code oferece no terminal: os comandos embutidos (mais de 90, com os apelidos — `/cost` acha o `/usage`), as skills que vêm com ele (`/simplify`, `/loop`, `/code-review`, `/debug`…), as skills e os plugins da sua conta do claude.ai (`anthropic-skills:*`) e as skills das pastas acima do terminal até a raiz do repositório. A lista rola com a seta ou a roda do mouse, em vez de parar em oito linhas, e tem uma barra de busca no topo (clique ou ⌘F) que procura no nome e na descrição, com várias palavras em qualquer ordem — "pdf" acha também o que só cita PDF na descrição (ADR-087).

### Alterado

- O prompt de instalação do site agora pede sua autorização, antes de baixar qualquer coisa, para liberar o app da verificação do macOS, e só então remove a quarentena e confere se ela saiu: o app ainda não tem assinatura da Apple.
- A barra de ações do canvas passou para o topo, e embaixo dela uma barra informativa com o cronômetro e o custo da bancada; no chat os dois ficam embaixo da coluna de participantes. O cronômetro saiu de baixo do título, e o clique nele continua oferecendo zerar (ADR-085).
- O maestro sempre responde os pedidos de permissão dos outros terminais da bancada; a caixa "Aprova permissões do time" saiu do formulário (ADR-080).

### Corrigido

- Agente que respondeu a um pedido de outro não fica mais preso em "aguardando" quando você fala com quem pediu antes da resposta chegar (ADR-067).
- Agente que fecha o turno dizendo que terminou não fica mais na ampulheta só porque deixou um servidor ou túnel rodando em segundo plano — e quem esperava por ele é liberado (ADR-067).
- A limpeza automática de órfãos agora encerra o laço que relança um comando a cada queda (como um túnel `aws ssm` que se refaz sozinho): antes só o filho, sempre novo, entrava na conta, e o laço ficava de pé por dias (ADR-083).

## [1.5.0] - 2026-10-22

### Adicionado

- Janela **Processos…** (⌥⌘P) e `egeon ps`: tudo o que o Egeon lançou, por bancada e nó, com os processos órfãos — os que ficaram de pé depois que o terminal fechou — no topo, a idade de cada um e botões para encerrá-los; todo terminal, shell incluído, passa a marcar no ambiente de onde veio o que ele abre (ADR-083).
- App de desktop que um agente abriu — o Docker Desktop, por exemplo — fecha quando a bancada que o abriu é removida, se ninguém mais estiver usando: outra bancada ligada a ele, ou com container de pé no Docker, segura o app aberto e passa a ser quem o fecha. App que já estava aberto antes nunca é fechado (ADR-084).
- Limpeza automática de processos órfãos: a cada 10 minutos o Egeon encerra o que foi lançado por ele, ficou sem dono e tem mais de 1 hora — sem tocar no daemon do Claude Code nem em apps abertos por um agente, como o Docker Desktop. Desliga em "Limpar órfãos automaticamente", no menu do app, e se ajusta em `processes.json` (ADR-083).

### Corrigido

- Remover um terminal ou uma bancada agora encerra também o que o agente deixou rodando em segundo plano — servidor de desenvolvimento, testes, o navegador do Playwright —, que antes ficava de pé, órfão, por dias (ADR-083).
- O app aberto de dentro de um terminal do Egeon não passa mais o endereço daquele terminal para os shells que ele abre (ADR-083).

## [1.4.0] - 2026-10-22

### Adicionado

- O maestro pode aprovar as permissões do time: com "Aprova permissões do time" marcado no formulário dele, cada pedido de ferramenta dos outros agentes da bancada chega ao maestro, que permite ou nega pelo `egeon` — você continua vendo o pedido, vale quem responder primeiro, e toda resposta fica na trilha. Perguntas a você continuam só com você (ADR-080).
- A barra lateral ganhou duas abas: **Todas**, a árvore de workspaces de sempre, e **Ativas**, só as bancadas de pé, em cards soltos (nome, projeto e cronômetro, com o ícone do workspace à esquerda), da que rodou por último para a mais antiga, separadas entre as que rodaram nas últimas 24 horas e as paradas há mais que isso; quando a ordem muda, os cards deslizam até o lugar novo (ADR-082).
- No chat, digitar `/` no começo da mensagem abre a lista do que o Claude Code daquele terminal aceita — comandos embutidos, os seus, os do projeto, skills e plugins habilitados, com a descrição de cada um; digitar filtra, e Tab ou Enter completa (ADR-079).

### Alterado

- Na barra lateral, workspaces e projetos não ficam mais dentro de caixas, um dentro do outro: são separados por um fio, e só a bancada continua como card (ADR-082).
- A bancada em foco na barra lateral ganha fundo azulado e um contorno azul firme, parado; a borda de quem parou ficou mais lenta (6 s por volta) e agora anda pela borda em velocidade constante, sem disparar nas pontas do card.
- Projeto sem bancada não mostra mais a seta de abrir, e clicar nele oferece criar a primeira bancada; workspaces e projetos da barra lateral se realçam ao passar o mouse.
- O cronômetro da bancada conta as fases ao mesmo tempo: um agente esperando você não para mais o tempo de trabalho de quem segue trabalhando ao lado, e as fases em curso ficam todas acesas. Aguardar outro agente continua contando como trabalho, não como espera por você (ADR-078).
- O card no canvas que precisa de você (pergunta, permissão ou erro) ganha a mesma borda girando da bancada na barra lateral, em vez da borda laranja parada.

### Corrigido

- Terminal que publicou uma página do Claude e terminou o turno não fica mais preso em "⏳ em segundo plano" — o vigia de comentários que o Claude Code arma em cada publicação contava como trabalho de fundo, e o cronômetro seguia contando a bancada como trabalhando (ADR-081).
- Terminal que pediu permissão no meio do turno e depois terminou respondendo a outro agente não fica mais preso em "precisa de você" — antes o card seguia laranja e o cronômetro contava a bancada como esperando você, mesmo com o turno fechado em `ok` (ADR-074).

## [1.3.0] - 2026-10-20

### Adicionado

- Cronômetro da bancada na barra de cima e em cada bancada da barra lateral, no lugar do caminho da pasta (que agora aparece ao passar o mouse): quanto tempo ela passou **trabalhando** (martelo, ciano), **esperando você** (mão, laranja) e **em erro** (sinal de parada, vermelho), com a fase em curso em destaque e o tempo em minuto e segundo (`01:18`, a hora entrando quando passa de 60 min). Conta só enquanto há algo acontecendo, sobrevive a fechar o app e a renomear, recomeça ao limpar a bancada, e clicar nele oferece **Zerar cronômetro** (ADR-074).
- Agente Claude que para por erro da API não fica mais parado esperando um "oi": erro passageiro (sobrecarga, servidor) tenta de novo sozinho em 30 s, 2 min e 5 min, e limite de uso em 2, 10 e 30 min — o card mostra "⟳ tentando de novo às 16:32 (2/3)" e o clique nele oferece **Tentar agora** e **Cancelar tentativa**. Erro sem volta (login, cobrança, pedido inválido) ou tentativas esgotadas param e chamam você, com **bolinha vermelha** no chat, borda e notificação (ADR-072).
- Links no modo chat são clicáveis e abrem no navegador: URL solta (`https://…`) e link de Markdown (`[documentação](https://…)`, que mostra só o rótulo), nas respostas dos agentes e nas suas mensagens.
- Agente Claude numa worktree nova não pergunta mais se você confia na pasta nem pede os imports externos do CLAUDE.md, quando o repositório de origem já foi aceito: a worktree herda as respostas — inclusive a pasta do multi-projeto, que junta vários repositórios e só herda se todos foram aceitos (ADR-071).
- Bancada cuja pasta o macOS não deixa ler (Documentos, Mesa, Transferências) pede o acesso de novo sozinha ao abrir; se continuar sem, fica travada com o aviso e os botões **Abrir Ajustes** e **Pedir de novo**, e destrava sozinha — subindo os agentes — assim que você libera. Antes o agente caía com "low max file descriptors" (ADR-070).
- Um agente pode mandar comando do CLI para outro (`/clear`, `/compact`, `/model sonnet`) pelo `egeon send`: o vizinho recebe antes um aviso dizendo quem vai mandar o quê, e o comando roda no terminal dele (ADR-069).
- Notificação do macOS, com som, quando um agente precisa de você ou termina, com o Egeon Deck fora da frente — "A bancada X precisa de você" ou "A bancada X já terminou o serviço", com o terminal e o que está esperando embaixo; clicar abre a bancada; nasce no estilo alerta, que fica na tela até você fechar (troca-se em Ajustes › Notificações). Segundo plano e "aguardando vizinho" não notificam.
- A bancada que terminou ganha a mesma borda girando, em verde, na barra lateral, na pastilha do trilho e na aba; o laranja de "precisa de você" tem prioridade sobre ela.
- Perguntas do agente com opções (a ferramenta de pergunta do Claude Code) aparecem no chat com as opções como botões, e a resposta vai direto para ele; o Claude passa a ser orientado a perguntar assim (ADR-068).
- Pedidos de permissão aparecem no chat, acima da caixa de mensagem, com o comando que o agente quer rodar e os botões **Permitir**, **Sempre** e **Negar**; responder no terminal continua valendo, e o pedido some do chat (ADR-068).

### Alterado

- O único limite de conversa entre agentes passou a ser o da aresta (o "↻" da ligação): saiu o teto de visitas da bancada, junto com o item "Limite de conversa entre agentes…" do menu. E a fila de mensagens esperando leitura num agente passou a contar por remetente, com o mesmo limite da aresta — antes eram 5 por destino, de quem fosse, e um maestro com time grande tinha respostas recusadas (ADR-077).
- Cada bancada na barra lateral virou um card — fundo e contorno próprios, mais alto e com espaço entre um e outro —, com o nome em cima e o cronômetro embaixo.
- O agente que acionou outro e parou esperando a resposta não apita mais nem fica "terminou": o card mostra **⏳ aguardando <vizinho>** até a resposta chegar, ou "terminou" quando o vizinho encerra sem responder (ADR-067).
- O card do maestro não tem mais o `+` de puxar ligação: ele já alcança todos os terminais da bancada (ADR-066).
- A bancada que precisa de você ganha uma borda laranja que gira devagar — na barra lateral, na pastilha do trilho e na aba —, no lugar do aro parado: chama o olho sem piscar. Com "reduzir movimento" do sistema, fica só a borda.
- A ampulheta de "em segundo plano" passa a vir do próprio Claude Code — o que ainda está rodando de fundo —, e não mais do marcador que o agente lembra de escrever (ADR-067).

### Corrigido

- As bancadas da barra lateral não piscam mais ao clicar num projeto (ou em qualquer coisa que redesenhe a barra): o cronômetro, o indicador de atividade e a borda já aparecem no lugar, em vez de surgirem um instante depois.
- O app não cai mais, sem aviso e sem relatório, quando quem chamou o socket de controle desiste antes da resposta — o gancho do agente com o app ocupado por mais de 1 s, ou um agente interrompido no meio de um `egeon send`. Era a queda repetida em bancadas com muitos agentes (morte por SIGPIPE).
- `egeon send` e `egeon peek` voltam a aceitar só o id do vizinho da mesma bancada (`testador` em vez de `testes-bancada/testador`), como o manual diz.
- Renomear um terminal ou marcá-lo como maestro pelo formulário não abre mais uma conversa nova: o agente reinicia e retoma a mesma conversa (desde que o CLI e a pasta sejam os mesmos). O ultracode e o endereço de nó web também não se perdem mais ao aplicar o formulário.
- ⌘-clique em caminho relativo no terminal abre o arquivo mesmo com a pontuação da frase grudada (`docs/a.md.`, `(README.md)`), e passa a funcionar também em nome solto, sem barra (`README.md`, `main.swift:42`), quando o arquivo existe na pasta do terminal.

### Removido

- O **VSCode** no canvas (nó de editor, o code-server): sai o card, a ferramenta da barra e o item **Novo VSCode** do menu — **Novo web** passa a ser ⌘3. O app não sobe mais o code-server, e bancadas e templates salvos com card de editor abrem sem ele (ADR-076).
- A extensão **Egeon Spec** do editor (code-server): o preview de markdown com comentário inline e o botão **Request changes** que mandava os comentários ao agente. O `.md` volta a abrir como texto no editor, e a extensão que as versões anteriores instalaram é apagada no arranque (ADR-075).
- O modo **mosaico** saiu: a bancada tem canvas e chat, e o chat passou para ⌥⌘2. Bancada que estava em mosaico abre no canvas (ADR-073).


## [1.2.0] - 2026-10-06

### Adicionado

- Terminal **maestro**: marque "Maestro" no formulário de um agente e ele monta a bancada sozinho — cria terminais, escolhe CLI, modelo, esforço, papel e regras de cada um, liga as arestas e define as regras da bancada, tudo num plano validado inteiro antes de aplicar (`egeon bench`, `egeon models`, `egeon plan`, `egeon apply`) (ADR-066).
- O maestro é o mestre da bancada: alcança todo terminal e recebe a resposta de todos sem setas no canvas — as setas ficam para quem conversa entre si (ADR-066).
- O maestro abre terminais normais — servidor de dev, watcher, log — com o comando de cada um, roda comandos neles com `egeon send` e lê a saída com `egeon peek` (ADR-066).
- Quando o maestro monta ou desmonta o time, os cards se arrumam sozinhos: ele fica onde você o pôs, os agentes à direita seguindo as setas (quem recebe vai para a direita, no meio de quem manda; quem conversa nos dois sentidos fica empilhado), com espaço para as setas, e os shells embaixo. Ele também move e redimensiona qualquer terminal (ADR-066).
- O card do maestro é dourado — borda mais grossa, título e controles — e o cabeçalho mostra "· maestro" (ADR-066).
- Skill `egeon-maestro` para o Claude Code (e `egeon guide` para os outros CLIs): o manual de como desenhar uma bancada — quando vale um time, topologias, modelo e esforço por papel, como escrever papel e regras, limites de conversa e o formato do plano (ADR-066).

### Corrigido

- A ligação entre dois cards um embaixo do outro não dá mais a volta inteira por baixo para entrar pela esquerda: ela desce reta da base do de cima ao topo do de baixo, e os controles dela (direção, limite, remover) aparecem centrados no meio da linha.
- Remover uma bancada apagando as worktrees não congela mais o app: o git e o disco trabalham em segundo plano, a bancada mostra "removendo…" na barra lateral e uma cortina por cima até sair da lista, e as outras bancadas seguem usáveis enquanto isso.

## [1.1.1] - 2026-10-01

### Corrigido

- A faixa "Copiando o que o git não versiona…" não fica mais presa na tela quando outra bancada é removida (ou a lista muda) durante a cópia: ela é apagada na bancada que pediu, pelo id, e não pela posição na lista.

## [1.1.0] - 2026-10-01

### Adicionado

- Multi-projetos no formulário do workspace: dê um nome e escolha algumas das pastas; a bancada dele abre todas juntas numa pasta só, e em worktree cria a mesma branch em cada repositório, lado a lado — ou uma branch própria no repo que você quiser, sem mudar a pasta (ADR-065).
- O seletor de modelo mostra os modelos pelo nome ("Opus 5.5", "Fable 5.1"), lidos do Claude Code instalado — atualizar o CLI atualiza a lista; versões anteriores ficam num submenu e os apelidos seguem disponíveis como "sempre o mais recente" (ADR-064).
- O slider de esforço mostra só os níveis que o modelo aceita, com o "auto" dizendo o padrão dele (ex.: "auto (medium)"); modelo sem esforço deixa o slider desligado (ADR-064).
- A faixa de modelo e esforço só aparece quando há o que escolher: Codex e Gemini, sem lista de modelos no `agents.json`, ficam com o cabeçalho de antes (ADR-064).
- Botão de ultracode na faixa do cabeçalho, independente do nível de esforço; também por `/model?target=…&ultracode=on|off` (ADR-064).
- Modelo e esforço (`--effort`: low · medium · high · xhigh · max) numa faixa própria no cabeçalho do card de agente, embaixo do nome: o esforço é um slider com uma marca por nível (a primeira é o auto, o padrão do modelo), que também responde à rolagem e só aplica 1s depois de você soltar. Também no formulário e por `/model?target=…&effort=…`; trocar reinicia o terminal e a conversa continua (ADR-064).

### Alterado

- Copiar para a worktree nova o que o git não versiona ficou uns 6× mais rápido: cada entrada (ex.: `node_modules`) é clonada inteira de uma vez no APFS, em vez de arquivo por arquivo, e sem pausa entre os repositórios — `nexus-web-app` + `nexus-backend` de ~21 s para ~3 s. Quem personalizou o `worktree-copy.sh` continua com o script dele.
- Bancada de multi-projeto só nasce em worktree: o + do multi-projeto abre direto o formulário de worktree, e "Nova bancada…" não aparece para ele (ADR-065).
- Modelo, esforço e ultracode ficam numa barra à parte embaixo do cabeçalho do card, com fundo próprio e o rótulo em cima de cada controle (ADR-064).
- Terminal novo sugere a configuração do CLI (ex.: `~/.claude-agro`) escolhida por último naquele workspace; escolher o padrão apaga a lembrança. O padrão aparece pelo caminho que o CLI usa sem configuração (`~/.claude`, `~/.codex`), não mais como "padrão da CLI".
- Formulário de terminal refeito: Shell e Agente viram abas, e os campos seguem a aba — shell tem nome, comando e pasta; agente tem CLI em radios, modelo e esforço, configuração (popup com as descobertas, e um + ao lado do título para outra), pasta, e papel e regras lado a lado. Campo que o CLI não tem não aparece.
- A pasta do terminal é uma lista de radios — root e as subpastas da bancada que são repositório (em multi-projeto, cada repo), sempre relativas —, com um + ao lado do título para outra pasta (ADR-065).

### Corrigido

- Abrir o chat de uma bancada com histórico longo não carrega mais centenas de mensagens de uma vez: a descida animada até o fim passava pelo topo e disparava o "carregar mais" a cada quadro; agora entram só as 60 do fim (ADR-045).
- O comando de um terminal shell agora é guardado: antes ele se perdia ao salvar como componente e ao editar o terminal.
- Depois de trocar de modelo, o seletor do cabeçalho não mostra mais o modelo antigo (ex.: "haiku (fable)") até o novo responder: só conta resposta dada depois do arranque atual.
- Trocar de bancada pelo teclado (⌘1…⌘9, ⌘]/⌘[, ⌘→/⌘←) não apaga mais a ampulheta de "em segundo plano" do terminal que estava focado: atalho do app deixou de contar como você digitando nele (ADR-063).

## [1.0.0] - 2026-09-28

Primeira versão estável. Consolida tudo o que existe até aqui: um canvas macOS em
que cada nó é uma ferramenta de trabalho real, feito para dirigir vários agentes de
IA em paralelo.

### Adicionado

#### Canvas e vistas
- Canvas infinito com quatro tipos de nó: editor (code-server), terminal, terminal
  com agente de IA e navegador. O canvas cresce quando se arrasta ou rola além da
  borda, e um botão enquadra todos os nós.
- Três vistas dos **mesmos** nós, sem reiniciar processo: canvas, mosaico (arranjo
  arrastável) e chat, com ⌥⌘1/2/3 (ADR-016, ADR-023, ADR-029).
- Barras flutuantes em vidro; a barra lateral recolhe com ⌘/ (ADR-025).
- Mão do ponteiro em tudo que responde a clique (ADR-048).

#### Organização do trabalho
- Hierarquia workspace → projeto → bancada, com foto ou inicial no workspace,
  reposicionamento por arrasto nos três níveis, selos de contagem e gaveta para
  projetos guardados (ADR-043, ADR-051, ADR-052).
- Abas com as bancadas abertas no topo, com os mesmos badges da barra lateral.
  Fechar a aba não encerra a bancada. Arrastar reordena; ⌘1…⌘9, ⌘]/⌘[, ⌘→/⌘← e ⌘W
  navegam; a faixa volta no arranque (ADR-061, ADR-062).
- Worktree git por bancada e por terminal, e remover a bancada oferece apagar as
  worktrees dela (ADR-017, ADR-018, ADR-021).
- Templates de bancada e de nó, com componente de nó independente de CLI
  (`byAgent`) (ADR-057).

#### Agentes
- Agente plugável por `~/.egeon/agents.json`, com `claude`, `codex`, `opencode` e
  `gemini` já configurados (ADR-009).
- Prompt injetado na sessão viva do CLI, com fila por terminal (ADR-007).
- Estado de cada terminal pelos ganchos do CLI: preparando, trabalhando,
  ⏳ em segundo plano, terminou (verde) e precisa de você (laranja, com som)
  (ADR-024, ADR-034).
- Protocolo de fim de turno pedido ao modelo: `[[ED:ok]]`, `[[ED:ask]]` e
  `[[ED:wait]]` (ADR-011, ADR-063).
- Modelo por nó, trocado pelo cabeçalho, que mostra o modelo literal em uso; trocar
  reinicia o processo e retoma a conversa (ADR-035).
- Papel e regras separados, com regra da bancada somada à do nó, entrando depois do
  papel no system prompt (ADR-056).
- A conversa de cada agente sobrevive a rebuild e reinício do app (ADR-014).

#### Coordenação entre agentes
- Arestas desenhadas no canvas dizem quem pode acionar quem; o par nasce
  bidirecional (ADR-012, ADR-028).
- Comando `egeon` dentro dos terminais: `peers`, `send`, `status`, `peek` e
  `trace`. A identidade de quem chama vem do pid da conexão, nunca do texto
  (ADR-040, ADR-054).
- Guardas de cadeia fora do prompt: aresta obrigatória, `maxSends` por aresta,
  `maxVisits` por bancada e teto de fila (ADR-012).
- Skill `egeon` publicada no Claude Code, para que "pede pro fulano" acione o
  vizinho em vez de um subagente; mensagens chegam com o envelope `[ED]`, e quem
  recebe responde ao remetente (ADR-054, ADR-055, ADR-058).

#### Chat
- Modo chat da bancada: participantes com cor e estado, composer com `@menção`,
  linha do tempo plana e turno ao vivo lido do transcript (ADR-039, ADR-042).
- Passos de ferramenta recolhidos, agrupados numa capa que aprofunda ao clique; diff
  lado a lado sempre visível; leitura com realce por linguagem (ADR-041, ADR-044,
  ADR-046, ADR-049, ADR-050, ADR-053).
- Histórico persistido pelo app por bancada, e "Limpar a bancada", que espera os
  agentes e arquiva chat e trilha (ADR-037, ADR-059).

#### Trilha da bancada
- `egeon trace` grava um Markdown por bancada, carimbado com quem, CLI, modelo e
  conversa; o shell registra os comandos sozinho (ADR-036).

#### Terminal
- Arrastar arquivo para o terminal cola o caminho; imagem vira anexo no Claude Code
  (ADR-026).
- ⌘-clique em caminho de arquivo ou URL abre, com sublinhado e mão ao passar o
  mouse; ⌘-clique no caminho do card abre a pasta no Finder.
- Voz pelo CLI dentro do terminal, com o microfone pedido pelo app (ADR-027).

#### Editor
- code-server embutido no canvas (ADR-003) e extensão própria de review inline de
  Markdown, com comentários ancorados em conteúdo (ADR-004, ADR-005, ADR-005b).

#### Operação
- Socket de controle HTTP em `~/.egeon/sock`, que é como se dirige e se testa o app
  de fora.
- Dois flavors que convivem, estável e dev, com config, socket, log e porta próprios
  (ADR-015, ADR-033).
- `install.sh`, `dist.sh` (zip universal e arm64) e `cert.sh` (identidade de
  assinatura estável).

### Corrigido
- O fim de turno não é mais lido cedo demais quando o gancho `Stop` chega antes da
  última linha do transcript, o que deixava o card em "terminou" (ADR-063).
- Limpar a bancada espera os agentes assentarem antes de arquivar (ADR-059).
- Remoção de worktree em que o git desiste no meio não é mais dada como falha
  (ADR-060).

## [0.4.0] - 2026-08-26

Pré-release.

### Adicionado
- Modo chat: participantes, composer estilo Slack, envio real e respostas dos
  agentes.
- Trilha da bancada com `egeon trace`, e histórico do chat persistido com
  "Limpar a bancada".
- Modelo por nó de agente, com o modelo literal no cabeçalho.
- Estado "preparando" até o `SessionStart` do CLI.
- Linha de ida e volta entre agentes com ponta nas duas extremidades.
- Arrastar arquivo para o terminal.

### Corrigido
- Uma segunda instância do mesmo flavor não sobe mais.
- O socket de controle confere se continua dono do arquivo dele.
- O `install.sh` instala só em `/Applications` e denuncia cópias gêmeas.

## [0.2.0] - 2026-08-18

### Adicionado
- Primeiro empacotamento para distribuição: zip universal e zip arm64.

## [0.1.0] - 2026-08-18

Primeira versão para passar adiante (tag `v0`).

### Adicionado
- Canvas infinito com nós de editor, terminal, agente de IA e navegador.
- Canvas e mosaico como duas vistas dos mesmos nós.
- Worktree por sessão e por terminal.
- Ligações entre agentes com quatro guardas, e `egeon peers` / `egeon send`.
- Aviso de "terminou" e "precisa de você" vindo do gancho do CLI.
- Socket de controle em `~/.egeon/sock`.

[Unreleased]: https://github.com/JulioRennan/egeon-deck/compare/v1.8.0...HEAD
[1.8.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.7.1...v1.8.0
[1.7.1]: https://github.com/JulioRennan/egeon-deck/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/JulioRennan/egeon-deck/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.4...v1.0.0
[0.4.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.2...v0.4
[0.2.0]: https://github.com/JulioRennan/egeon-deck/compare/v0...v0.2
[0.1.0]: https://github.com/JulioRennan/egeon-deck/releases/tag/v0
