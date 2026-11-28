# Conferência visual · app × v3

> 2026-11-19. Referências em tamanho real: `.omc/refs-v3/NN-*.png` (capturas
> das telas "v3 — canvas final" do canvas do Julio). App: dev flavor, capturas
> por `curl --unix-socket ~/.egeon-next-dev/sock "http://eg/shot?target=window"`
> com o app na frente. Cada item só fecha com a captura do app ao lado da
> referência, conferida pelo maestro.

## Casca e barra de topo (refs 01, 03)

- [x] (captura nativa conferida; tela cheia/arrasto pedem olhada do Julio) Barra de topo com a altura da barra de título do sistema, centro alinhado aos semáforos.
- [x] Toggle Canvas/Chat só ícone (revisor aprovou na rodada 2).
- [x] (pulso com os valores da v3) Trilho: botão da gaveta com selo de contagem (laranja, "2"); cada bancada com ponto de estado no canto (verde terminou, laranja esperando, spinner trabalhando); marcador à esquerda na selecionada.
- [x] (valores do frameGlow conferidos; pixels da borda iguais à ref) Moldura da bancada tingida na cor da bancada (ref 03: troca para lilás em "migracao-flutter").

## Gaveta de bancadas (refs 02, 12)

- [x] Sem título "Bancadas", sem X, sem fixar. Uma linha só: abas "Todas 13" / "Ativas 12" com sublinhado (ponto laranja na Ativas) + buscar, filtrar, +, recolher.
- [x] Workspace: avatar-letra, nome, "3 bancadas", ponto de atenção à direita.
- [x] (stack: lacuna do core) Projeto: pasta + nome + contagem; selos de stack embaixo (lacuna do core: lugar previsto, sem dado falso).
- [x] (preço em linha própria conferido; estado ao vivo conferido com o core novo) Tile da bancada: **título** (cor da bancada) / **linha de estado** ("● 1 terminou ◌ 2 em trabalho", "● 2 esperando você") / **preço embaixo** em mono. Hoje: estado e preço na mesma linha e o estado SEMPRE "Parada" — o estado tem de refletir os agentes de verdade.
- [x] Selecionada com fundo destacado e fio à esquerda; não selecionadas com fio fino.
- [ ] ("parada há X": lacuna do core — last_active) "› 1 parada há mais de 3 dias" recolhível; "Gaveta vazia" / "Gaveta · 2".

## Barra de ações (refs 01, 04, 05, 06)

- [x] Ícone de "Enquadrar todos" igual ao da v3 (alvo com cantos), não o de expandir.
- [x] (revisor, por medidas; não capturado — só abre com clique) Menu do terminal de agente (ref 04): "Componentes salvos", nome na cor, meta "Claude Code · Opus 5.5 · alto", fio, "+ Configurar novo terminal…".
- [x] (revisor, por medidas; não capturado — só abre com clique) Menu Template (ref 05): "Salvar como template…", "Atualizar “Equipe redesign”".
- [x] (revisor, por medidas; não capturado — só abre com clique) Menu de cor (ref 06): título "Cor da bancada" + nome da bancada na cor à direita; grade 6×2; selecionada com anel duplo.

## Chip e painel de consumo (refs 07, 08, 09, 14)

- [x] (captura conferida) Chip: SÓ dois tempos — martelo em `running` (azul) com o tempo trabalhando, mão em `attention` (laranja) com o tempo parado — fio vertical, custo, chevron. Hoje: três tempos e ícones cinza.
- [x] (por imagem; sem dado: Log, turnos, branch, Abrir Consumo) Painel: "egeon-deck" na cor + "⑂ redesign-canvas" + ✕; Trabalhando / Parado / Total em mono grande (Total = custo); "9 turnos"; barra de proporção colorida por agente; segmentado Log | Por agente | Por modelo; rodapé "Abrir Consumo e custo" (link) e "Zerar cronômetro" (perigo).
- [ ] Log: agente na cor + hora + "precisa de você" (laranja) + custo à direita; o que fez; "modelo · entrada / saída tokens".
- [x] (sem "turnos"/filtro: lacuna) Por agente / Por modelo: "Clique para filtrar o log"; nome na cor, custo, barra, "N turnos", tokens.

## Cards (refs 01, `Nos-A-maestro`)

- [x] Maestro em amarelo (id-sand) — faixa, cabeçalho, nome, etiqueta, borda/brilho. (revisor aprovou; captura conferida)
- [x] Maestro com todos os controles (causa: parse do context nulo na UI; corrigido, captura conferida após reabrir).
- [x] Linha de controles: "modelo Opus 5.5 ▾ │ esforço alto ▾ │ ◉ auto … contexto ▬ 31% ↻": esforço em português, fios separando, ícone de limpar = ↻ da v3 (hoje vassoura).
- [x] "precisa de você" (revisor, ref 01): borda laranja e ponto laranja no cabeçalho, barra de contexto laranja a partir de 80%.
- [x] (subtítulo: "N pendentes" do core; formato v3 = decisão 50) Fila de prompts: título + "para revisor · 2 de 4", item feito riscado, item em trabalho com spinner.

## Chat (refs 10, 11, 12, 14)

- [x] Participantes: nome na cor + endereço mono + ícone de estado à direita (spinner, ponto laranja, check verde, círculo vazio); SEM a linha do papel. Fila como participante ("Fila de prompts · deck/fila → revisor · 2 de 4").
- [x] Separador "Hoje"; bolha do usuário à direita com "você · 22:40".
- [x] Cabeçalho da mensagem do agente: nome na cor + "Opus 5.5 · 23:08 · US$ 1,12".
- [x] Passos recolhidos "› 3 passos · leu …" e expandidos (ref 11).
- [x] Citação "maestro → revisor  Revisar o diff… 23:31".
- [x] ("Concluído": lacuna do core) Bloco de saída de comando + "✓ Concluído · 23 testes ok".
- [x] Pedido de permissão DENTRO do cartão do composer, no topo: ponto laranja, "revisor quer editar `lib/canvas/toolbar.dart`", Permitir (primário) · Sempre · Negar.

## Composer (refs 01, 13)

- [x] (sem o "+": o chat não anexa — lacuna; traits do maestro dependem da faixa do maestro) Ícones "+" (anexar), "/" em quadrado, "@"; "Para maestro ▾" na cor do agente; à direita "Opus 5.5 · medium" do destinatário (o app já sabe pelo estado do agente) e enviar (azul quando há texto).
- [x] Altura e largura como na v3.

## Janela estreita

- [x] Tamanho mínimo da janela; nada sobrepõe nem estoura nesse mínimo.

## Exceções v3 > DS

- Pulso de atenção e de "terminou" (AttentionRing): valores da v3 (`.pulse`/`.pulse-g`: 0→5px, cor @0x66 → transparente, 1600 ms, cubic-bezier(.4,0,.6,1)) no lugar do `eg-halo` do DS (attention-soft, 6/8px). A v3 usa esse pulso no trilho e no card.
- Pedido de permissão: o "quer usar X — detalhe" do Swift virou "quer editar/escrever/rodar … <alvo>" (verbo traduzido da ferramenta na UI, `toolVerb`), como na v3. Só rótulo; o pedido e a resposta ao core não mudam. Comando longo: até 3 linhas e dica com o texto inteiro, como o toolTip do Swift.
