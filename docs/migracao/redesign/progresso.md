# Redesign — progresso das etapas

Orquestração: maestro `claude` · dev `dev` (Sonnet, médio) · revisor `revisor`
(Opus, alto). Uma etapa por vez. Cada etapa só fecha com o revisor aprovando
e `fvm flutter analyze && fvm flutter test` passando.

Fonte do DS no repo: `design/system/` (cópia do DS v21:
tokens, tema Dart, paleta do terminal, READMEs, fontes `.ttf` + OFL).

| # | Etapa | Plano | Estado |
|---|---|---|---|
| E0 | Fundação do DS: fontes, tema, vidro, paridade, amostra | `../4-design-system.md` | aprovada (846 testes, analyze limpo) |
| E1 | Componentes base | `01-commons.md` | aprovada (977 testes, analyze limpo) |
| E2 | Moldura da janela | `02-home.md` | aprovada (1037 testes, analyze limpo) |
| E3 | Barra lateral | `03-sidebar.md` | aprovada (1082 testes, analyze limpo) |
| E4 | Canvas | `04-canvas.md` | aprovada (1097 testes, analyze limpo) |
| E5 | Nós | `05-node.md` | aprovada (1096 testes, analyze limpo) |
| E6 | Chat | `06-chat.md` | aprovada (1122 testes, analyze limpo) |
| E7 | Consumo | `07-usage.md` | aprovada (1127 testes, analyze limpo) |
| E8 | Demais módulos e limpeza do tema antigo | `08-demais.md` | aprovada (1107 testes, analyze limpo) |

## Decisões tomadas pelo Julio (2026-11-19)

- Seguir o DS Egeon (Graphite); nada da UI provisória é reaproveitado.
- Fontes: Noto Sans e JetBrains Mono `.ttf` completas, normal e itálico, embutidas.
- Nome "Egeon" em Noto Sans 600.
- Ícones: traço 1.5 na grade de 16, caminhos portados do componente `Icon` do DS e das telas do canvas (o pacote Lucide não tem traço 1.5 exato) — opção prevista no README Flutter do DS.
- Vidro (blur gaussiano 20, saturação 130%) só no que flutua.

## Registro

- E0 entregue ao dev.
- E0 aprovada pelo revisor e conferida pelo maestro (analyze limpo, 846 testes). Nova dependência: material_ui (BSD). DS v22 corrigido: shadow-modal 0x8C, mono-meta 450.
- E1 entregue ao dev. Telas de referência lidas do canvas da v3.
- E1 rodada 1 (C1–C3) em revisão; ícones sem pacote, com parser de SVG path próprio. Componentes do DS (bundle.js, index.d.ts) lidos do DS publicado.
- E1: danger-solid sem estados no token; o DS tinha hex soltos no bundle.css (#f37571 hover, #d94d4a pressionado). Viraram tokens danger-hover/danger-pressed no DS v23 e em design/system/tokens.json. Overlay sob o tema anotado para a E2 (H6b).
- E1 aprovada (rodadas 1 e 2) e conferida pelo maestro: analyze limpo, 977 testes. Componentes em ui/lib/commons/widgets/eg/. bundle.css do DS no repo. Movimento reduzido desacelera (3200/1800 ms), como o DS.
- Aresta dev↔revisor subiu para 10 envios (a cadeia estourou 6/6 na E1).
- Achado: o core guarda a cor da bancada em 24 nomes antigos (WorkbenchColor), o DS tem 12 identidades. Provisório na E2: a UI mapeia cada nome antigo para a identidade mais próxima e grava, para cada identidade, um nome antigo fixo; formato de ~/.egeon intacto. Decisão pendente com o Julio.
- E2 entregue ao dev.
- Decisão 45: janela sem barra pelo runner, sem window_manager.
- Conflito para a E4: v3 pede ⌘1–⌘4 nas ferramentas; o porte fiel usa ⌘1–⌘9 para ir à aba/bancada n. Decidir com o Julio.
- E2 aprovada pelo revisor e conferida pelo maestro (analyze limpo, 1037 testes).
- E3 entregue ao dev.
- E3: falta no core (levantado pelo dev): idade da última atividade (last_active), stack do projeto, Encerrar terminais, Abrir no Finder, Renomear projeto, Recolher tudo. Só 'Recolher paradas há mais de X' depende de last_active (o filtro 'Paradas' sai da atividade que o core já manda — corrigido pelo revisor). A UI esconde/desabilita. Levar ao Julio.
- A cadeia dev↔revisor estoura o limite a cada etapa (o usuário não digita e a cadeia não zera): o maestro faz a ponte das revisões.
- E3 aprovada (duas rodadas) e conferida pelo maestro: analyze limpo, 1082 testes.
- E4 entregue ao dev; ⌘1–⌘9 seguem no porte fiel até o Julio decidir.
- E4 r1 reprovada: dica de ferramenta é de vidro (erro do maestro: 'um BackdropFilter só' não é regra; o DS diz um por peça visível), posições 16/+10, zoom w500. Template ▾ e Cor da bancada entram na r2 (V4/V5). Aceitos e anotados: zoom nos passos do porte (25…300%), tooltips sem atalho até decidir ⌘1–⌘4, Shell/Agente num botão até a r2.
- E4 r2: falta no core (UI degrada): contagem de envios usados por ligação (EdgeLabel sem 'N/M', sem estados running/gasto da aresta); cor por componente salvo. Esmaecer nós fora do foco não existe no porte: fora. Sombra de arrasto do card vai para a E5.
- E4 aprovada (duas rodadas) e conferida pelo maestro: analyze limpo, 1097 testes. Dois ajustes finos (cabeçalho do menu de cor, cor do texto da dica) vão junto da E5.
- E5 entregue ao dev.
- E5 r1: falta no core (UI degrada): descrição curta dos modelos; 'auto mode' da v3 (aprovar ações, shift+tab) não existe — a pastilha sai da faixa e o auto do esforço vira 'Automático' no menu de esforço (o revisor apontou que a pastilha enganava); 'Recarregar' do shell e selo 'rodando/exit/ocioso'; cor por agente (provisório: maestro sand, demais Identity.auto).
- E5 r1 aprovada exceto a pastilha auto (corrigida acima). Cursor grab no cabeçalho do card (ADR-048, do porte) corrigido junto.
- E5 aprovada (duas rodadas) e conferida pelo maestro: analyze limpo, 1096 testes. Pendente do core: subtítulo da fila 'para … · N de M'.
- E6 entregue ao dev.
- E6 r1: falta no core: modelo da resposta na linha de meta da mensagem. Custo/hora da mensagem vão para o hover (DS). Cor do agente unificada entre card e chat (uma função em commons/utils). Composer também no canvas (v3), reaproveitando o cubit do chat.
- E6 r2: falta no core: modelo/esforço do destinatário ao lado do enviar (ChatParticipantInfo); anexar arquivo (o chat do porte não anexa); flag 'maestro' no participante do chat (sem ele, o maestro tem a cor do id em vez de sand fixo). Composer do canvas = ChatDock com os cubits do chat, sem rota nova. Enquadrar não desconta a altura do composer.
- E6: composer flutua sobre a conversa (v3), mesma camada do canvas; campo nasce com 2 linhas. Decisão do maestro: o composer usa o vidro padrão do DS, não a variante mais densa da v3 (78%/8%/sombra 45%).
- E6 aprovada e conferida pelo maestro: analyze limpo, 1122 testes. ShellLayers em commons/widgets. Ajuste fino (pé a 20 do fundo) vai com a E7.
- E7 entregue ao dev.
- E7: falta no core: log por turno (hora, agente, o que fez, modelo, tokens, custo) — sem ele não há visão Log nem filtro ao clicar nem escopo/Limpar; branch no topo do painel; 'Parado' (o core tem esperando você/erro); 'Abrir Consumo e custo' sem tela destino.
- E7 aprovada e conferida pelo maestro: analyze limpo, 1127 testes.
- E8 entregue ao dev (D4 sem mexer nos atalhos ⌘1–⌘9; D6 conferência visual fica com o Julio).
- E8 r1: falta no core: CPU e memória por processo (ProcessRow só traz pid/node/orphan/age/command). Aviso de versão continua Dialog (escolha obrigatória).
- E8 r2 reprovada: voltam testes de paridade do EffortDial (régua do legado), 4 de diálogo e tabs_cubit_test; trilho ganha arrastar para reordenar e 'Fechar bancada' no menu de contexto (decisão do maestro: nada de funcionalidade perdida com a saída das abas); véus viraram tokens overlay-2..12 no DS v26; CHANGELOG ajustado.
- E8 aprovada e conferida pelo maestro. Fechamento: analyze limpo, 1107 testes, nenhum resto do tema antigo, nenhum hex fora de theme/, CHANGELOG com as linhas do redesign. Nada commitado. Pendente: conferência visual no app (Julio); decisões 46, ⌘1–⌘4 e cor da bancada; lista do que falta no core (acima).
- Consumo (dev2): aba Log do painel sai da UI até o core mandar o log por turno (hora, agente, o que fez, modelo, tokens, custo, "precisa de você"). O formato de socket é decisão nova: vai para `3-proposta.html` e passa pelo Julio; nada nasce só na UI. Também faltam no painel: "9 turnos", branch, "Clique para filtrar o log" e "Abrir Consumo e custo". Chat: anexar arquivo (o "+" do composer saiu até existir).
- Halo de atenção (dev2): o `AttentionRing` (`ui/lib/commons/widgets/eg/attention_ring.dart`) passou a seguir o `.pulse`/`.pulse-g` da v3 (0px a 0x66 → 70%: 5px transparente → 100%: 0px, `cubic-bezier(.4,0,.6,1)`, 1600 ms) e não o `eg-halo` do DS (0→6px `attention-soft` → 8px transparente). Exceção deliberada, v3 > DS, por fidelidade pedida pelo Julio; quem comparar com o DS não deve achar que é erro. Vale para o laranja (precisa de você) e o verde (terminou, `color: success`).
- Fila: o card mostra o subtítulo do Swift ("nada pendente" / "N pendentes", `QueueNode.swift:143`), que o core agora entrega no retrato dos nós (`NodeView.subtitle`, `Actor::nodes_state`); a UI só mostra. O formato da v3 ("para revisor · 2 de 4") é a decisão 50 de `3-proposta.html`, aberta para o Julio. Levantamento completo das lacunas do core em `lacunas-core.md`; as que já têm dado no core (parada há X, flag maestro, modelo por resposta) viraram as decisões 47–49.
