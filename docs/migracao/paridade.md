# Paridade de testes — Swift → Rust/Flutter

Gerado por `docs/migracao/gerar-paridade.py`; o que o casamento por nome não alcança está em `docs/migracao/paridade-manual.json`. Regerar ao fim de cada marco.

- Testes do Swift (`legado/app/Tests`): **633**
- Testes em Rust: 1415 · em Dart: 692

| Situação | Quantos |
|---|---:|
| PORTADO | 614 |
| PARCIAL | 2 |
| PROVÁVEL | 2 |
| CONFERIR | 0 |
| NÃO PORTA | 15 |
| LACUNA | 0 |

PORTADO = casou por nome ou está no manual; PARCIAL = tem o teste de um lado e falta o do outro (o que falta está na linha); PROVÁVEL = casou por palavras (conferir à mão); CONFERIR = o arquivo de teste cita a classe do Swift, mas nenhum teste casa pelo nome; NÃO PORTA = o teste não faz sentido fora do AppKit (motivo na linha); LACUNA = ainda sem teste correspondente.

## Lacunas e a conferir

| Arquivo | Teste | Situação | De quem é |
|---|---|---|---|
| ChatComposerTests.swift | `testTypingDoesNotRemeasureThread` | PARCIAL | ui: teste de que a largura nova remede a thread |
| ChatStepToggleTests.swift | `testOpenStepPaintsHeaderAndBodyDifferently` | PARCIAL | ui: teste de cor de `step-title` × `step-body` no chat |

## Por arquivo

### ActiveWorkbenchesTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ActiveWorkbenchesTests.testOnlyLiveOnesNewestFirstSplitAt24Hours` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::so_as_de_pe_mais_novas_primeiro_cortadas_em_24_horas`, `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::instante_no_futuro_conta_como_agora_e_a_borda_de_24h_ja_e_parada`, `ui/test/features/sidebar/sidebar_page_test.dart::a aba Ativas separa as últimas 24 horas das paradas` (manual) |
| `ActiveWorkbenchesTests.testNeverRanGoesLastAndTiesKeepListOrder` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::nunca_rodou_vai_por_ultimo_e_o_empate_guarda_a_ordem_da_lista` (manual) |
| `ActiveWorkbenchesTests.testEmpty` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::vazio`, `ui/test/features/sidebar/sidebar_page_test.dart::sem nada de pé, a aba Ativas diz como abrir uma` (manual) |

### ActivitySummaryTests.swift — 2/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ActivitySummaryTests.testOnlyStartingIsPreparing` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::only_starting_is_preparing` (exato) |
| `ActivitySummaryTests.testAnyOtherActivityIsNotPreparing` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::any_other_activity_is_not_preparing` (exato) |

### ActivityTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ActivityTests.testOnlyAskingInterrupts` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::only_asking_and_failed_interrupt` (o Rust também cobre Failed (ADR-072)) |
| `ActivityTests.testColorSeparatesTheTwoStops` | PORTADO | `rust/crates/egeon-core/src/runtime/org.rs::rotulo_glifo_e_cor_do_cabecalho` (o rótulo, o glifo e o tom do cabeçalho saem prontos do core (`activity_view`); a UI só desenha) |
| `ActivityTests.testLabels` | PORTADO | `rust/crates/egeon-core/src/runtime/org.rs::rotulo_glifo_e_cor_do_cabecalho` (o rótulo, o glifo e o tom do cabeçalho saem prontos do core (`activity_view`); a UI só desenha) |
| `ActivityTests.testBackgroundIsAnHourglassWithoutAlarm` | PORTADO | `rust/crates/egeon-core/src/runtime/actor/dispatch_commands.rs::segundo_plano_e_ampulheta_sem_alarme` (o Dispatcher põe a ampulheta pelo [[ED:wait]] com fundo, e o activity_view do core dá rótulo, glifo e tom) |
| `ActivityTests.testAwaitingNamesThePeers` | PORTADO | `rust/crates/egeon-core/src/runtime/actor/dispatch_commands.rs::aguardando_diz_o_nome_dos_vizinhos` (quem acionou o vizinho fica aguardando com o nome dele; o activity_view junta os nomes com vírgula, sem tom) |

### AgentProfileTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AgentProfileTests.testClaudeCodeFactoryProfileTemplating` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::perfil_de_fabrica_do_claude_monta_a_linha_de_comando` (manual) |
| `AgentProfileTests.testDefaultModelMeansNoFlag` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::modelo_padrao_e_nao_passar_flag` (manual) |
| `AgentProfileTests.testProfileWithoutDeclarationsReturnsNil` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::perfil_sem_declaracoes_devolve_nada` (manual) |
| `AgentProfileTests.testClaudeCodeEffortTemplating` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::esforco_do_claude` (manual) |
| `AgentProfileTests.testEffortChoiceAppliesToNodeOnly` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::escolha_de_esforco_mexe_so_no_esforco` (manual) |

### AgentRulesTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AgentRulesTests.testNothingWhenThereAreNoRules` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::sem_regras_nada` (manual) |
| `AgentRulesTests.testASingleBlockCarriesNoOrigin` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::um_bloco_so_nao_carrega_origem` (manual) |
| `AgentRulesTests.testBothBlocksAreNamedAndOrdered` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::dois_blocos_nomeados_e_em_ordem` (manual) |
| `AgentRulesTests.testUserTextIsNotRewritten` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::texto_do_usuario_nao_e_reescrito` (manual) |
| `AgentRulesTests.testHeaderStatesPrecedenceOverTheRole` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::cabecalho_diz_a_precedencia` (manual) |
| `SystemPromptOrderTests.testRulesComeAfterTheRole` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::regras_vem_depois_do_papel` (manual) |
| `SystemPromptOrderTests.testRulesAloneStillReachTheAgent` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::so_regras_ainda_chegam_ao_agente` (manual) |

### ApiFailureTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ApiFailureTests.testKinds` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/failure.rs::kinds` (exato) |
| `ApiFailureTests.testScheduleAndGivingUp` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/failure.rs::schedule_and_giving_up` (exato) |
| `ApiFailureTests.testReadFromQueryAndWording` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/failure.rs::read_from_query_and_wording` (exato) |
| `ApiFailureTests.testStatesInTheRestOfTheApp` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::only_asking_and_failed_interrupt`, `rust/crates/egeon-core/src/features/activity/tests.rs::failed_tells_why`, `rust/crates/egeon-core/src/features/activity/tests.rs::states_that_come_back_alone_do_not_notify` (a cor vermelha de Failed é da UI e não tem teste) |

### AppClaimsTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AppClaimsTests.testAppWithoutMarkIsNeverClosed` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::app_sem_marca_nunca_e_fechado` (manual) |
| `AppClaimsTests.testOpenerLeavingClosesTheApp` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::quem_abriu_saindo_fecha_o_app` (manual) |
| `AppClaimsTests.testHeirIsTheLastUser` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::o_herdeiro_e_o_ultimo_a_usar` (manual) |
| `AppClaimsTests.testDeadHeirDoesNotHoldTheApp` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::herdeiro_morto_nao_segura_o_app` (manual) |
| `AppClaimsTests.testOpenerIsOnlyTheAppTheLaunchdOpened` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::o_opener_e_so_o_app_que_o_launchd_abriu` (manual) |
| `AppClaimsTests.testContainerOwners` | PORTADO | `rust/crates/egeon-core/src/features/processes/tests.rs::donos_dos_containers` (manual) |
| `AppClaimsTests.testSocketPeers` | PORTADO | `rust/crates/egeon-core/src/ports/procs.rs::socket_ligado_ao_app_aparece_como_conectado`, `rust/crates/egeon-driver/src/apps/mod.rs::lsof_liga_cada_socket_ao_processo_dono` (manual) |

### AppEnvironmentTests.swift — 6/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AppEnvironmentTests.testEnrichedPathKeepsCurrentAndDoesNotDuplicate` | PORTADO | `rust/crates/egeon-core/src/features/terminal/environment.rs::diretorio_que_ja_esta_no_path_nao_muda_de_lugar`, `rust/crates/egeon-core/src/features/terminal/environment.rs::cli_vai_na_frente_de_tudo_no_path`, `rust/crates/egeon-core/src/features/terminal/environment.rs::enriquecer_o_path_ja_enriquecido_nao_muda_nada` (manual) |
| `AppEnvironmentTests.testEnrichedPathOnlyAddsDirectoriesThatExist` | PORTADO | `rust/crates/egeon-core/src/features/terminal/environment.rs::diretorios_existentes_entram_na_frente_na_ordem_da_lista`, `rust/crates/egeon-core/src/features/terminal/environment.rs::sem_path_herdado_o_filho_ainda_recebe_o_cli` (a existência vem de um predicado injetado, não do disco) |
| `AppEnvironmentTests.testShellQuoteNeutralizesMetacharacters` | PORTADO | `rust/crates/egeon-core/src/features/terminal/model.rs::shell_quote_neutraliza_metacaracteres` (manual) |
| `AppEnvironmentTests.testChildEnvironmentDropsClaudeCodeVariables` | PORTADO | `rust/crates/egeon-core/src/features/terminal/environment.rs::filho_nao_herda_variaveis_claude_code`, `rust/crates/egeon-core/src/features/terminal/environment.rs::cli_vai_na_frente_de_tudo_no_path`, `rust/crates/egeon-driver/tests/environment.rs::filho_lancado_nao_enxerga_claude_code_nem_procedencia_herdada` (manual) |
| `TerminalDropTests.testFileDropBecomesQuotedPathsWithTrailingSpace` | PORTADO | `rust/crates/egeon-core/src/features/terminal/drop.rs::caminhos_citados_so_quando_precisa_e_espaco_no_fim`, `rust/crates/egeon-core/src/runtime/actor/terminal_commands.rs::arrasto_de_arquivos_escreve_os_caminhos_citados` (manual) |
| `TerminalDropTests.testEmptyPasteboardIsNothing` | PORTADO | `rust/crates/egeon-core/src/features/terminal/drop.rs::arrasto_sem_caminho_nao_escreve_nada` (a metade do `accepts` é da UI, que só manda o arrasto quando há arquivo) |
| `TerminalDropTests.testAcceptsFileURLs` | NÃO PORTA | `accepts` olha os tipos do NSPasteboard; no app novo é a UI que decide o que aceita e manda só caminhos ou imagem ao core |

### AppUpdateTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AppUpdateTests.testVersionsCompareAsNumbers` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::versoes_comparam_como_numeros` (manual) |
| `AppUpdateTests.testReleaseParsing` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::leitura_da_release` (manual) |
| `AppUpdateTests.testPolicyNeverDownloadsWithoutTheOptionAndPromptsOnlyAtLaunchOrOnRequest` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::a_politica_nunca_baixa_sem_a_opcao_e_so_avisa_na_abertura_ou_a_pedido` (manual) |
| `AppUpdateTests.testPromptSaysWhatRestartingCostsAndWhatTheClickAuthorizes` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::o_aviso_diz_o_que_reiniciar_custa_e_o_que_o_clique_autoriza` (manual) |
| `AppUpdateTests.testPublishedKeyIsAUsableKey` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::a_chave_publicada_e_uma_chave_usavel` (manual) |
| `AppUpdateTests.testPrepareStagesASignedNewerApp` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::prepare_deixa_pronto_um_app_assinado_e_mais_novo`, `rust/crates/egeon-driver/tests/installer.rs::prepara_o_app_assinado_ao_lado_do_destino` (a regra no core (instalador de mentira) e o app assinado de verdade no driver) |
| `AppUpdateTests.testPrepareRefusesWhatItCannotTrust` | PORTADO | `rust/crates/egeon-core/src/features/update/tests.rs::prepare_recusa_o_que_nao_da_para_confiar`, `rust/crates/egeon-driver/tests/installer.rs::app_adulterado_nao_chega_ao_destino` (assinatura/versão/app errado no core; codesign do bundle adulterado no driver) |
| `AppUpdateTests.testSwapReplacesTheBundleAndLeavesNothingBehind` | PORTADO | `rust/crates/egeon-driver/tests/installer.rs::troca_o_bundle_e_nao_deixa_nada_para_tras` (manual) |
| `AppUpdateTests.testSwapWaitsForTheAppToLeave` | PORTADO | `rust/crates/egeon-driver/tests/installer.rs::a_troca_espera_o_app_sair` (manual) |

### AttentionRingTests.swift — 1/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `AttentionRingTests.testHiddenUntilTurnedOn` | NÃO PORTA | CALayer/NSView do AppKit (camada, animação, frame); o anel é widget da UI (commons/widgets/attention_ring.dart) e não tem teste em Dart |
| `AttentionRingTests.testBothTonesSpinAndOffStops` | NÃO PORTA | CALayer/NSView do AppKit (camada, animação, frame); o anel é widget da UI (commons/widgets/attention_ring.dart) e não tem teste em Dart |
| `AttentionRingTests.testFollowsTheHostSize` | NÃO PORTA | CALayer/NSView do AppKit (camada, animação, frame); o anel é widget da UI (commons/widgets/attention_ring.dart) e não tem teste em Dart |
| `AttentionRingTests.testOrangeBeatsGreen` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::orange_beats_green` (manual) |

### CanvasDocumentGrowthTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `CanvasDocumentGrowthTests.testPanPastRightEdgeGrowsDocument` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::pan além da borda direita cresce o documento` (manual) |
| `CanvasDocumentGrowthTests.testPanPastBottomEdgeGrowsDocument` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::pan além da borda de baixo cresce o documento` (manual) |
| `CanvasDocumentGrowthTests.testDocumentNeverShrinks` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::o documento nunca encolhe` (manual) |
| `CanvasDocumentGrowthTests.testGrowthStopsAtCeiling` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::o crescimento para no teto` (manual) |

### CanvasFitTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `CanvasFitTests.testFitsWideContentByWidth` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::conteúdo largo cabe pela largura` (manual) |
| `CanvasFitTests.testNeverZoomsInPastOneHundred` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::nunca amplia além de 100%` (manual) |
| `CanvasFitTests.testClampsToMinimumStep` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::prende no menor passo` (manual) |
| `CanvasFitTests.testDegenerateInputsFallBackToOne` | PORTADO | `ui/test/features/canvas/domain/canvas_viewport_test.dart::entradas degeneradas caem em 1` (manual) |

### ChatBlockLayoutTests.swift — 2/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatBlockLayoutTests.testCollapsedStepIsOneLineAndOpenOneIsTaller` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::passo_recolhido_e_uma_linha_e_o_aberto_tem_comando_e_saida` (o texto da linha (chevron, título, contagem, comando e saída) é do core; que a linha aberta seja mais alta é medida de view e fica na UI) |
| `ChatBlockLayoutTests.testEveryRowGetsAHeightAndBubbleSharesWidth` | NÃO PORTA | altura e largura de bolha são medida do TextKit; no app novo quem mede é a UI (Flutter) e ainda não há teste de widget do chat |
| `ChatBlockLayoutTests.testNarrowerThreadMakesProseTaller` | NÃO PORTA | quebra de linha por largura é medida de TextKit; fica na UI (Flutter), sem teste de widget do chat ainda |
| `ChatBlockLayoutTests.testUnchangedBubbleIsReusedAndChangedOneIsNot` | NÃO PORTA | cache de medida por bolha é do NSTableView/TextKit; no app novo o ListView do Flutter mede sozinho e o core só manda o diff de blocos |
| `ChatBlockLayoutTests.testAgentPromptMentionsWithoutArrow` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::prompt_de_agente_menciona_sem_seta` (manual) |
| `ChatBlockLayoutTests.testMeasuresOffMainThread` | NÃO PORTA | medir fora da main é detalhe de threading do AppKit; sem equivalente no Flutter |

### ChatBlocksTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatBlocksTests.testOneRowPerBlockWithStableIds` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::uma_linha_por_bloco_com_id_estavel` (manual) |
| `ChatBlocksTests.testStepsCollapseUntilOpenedByIdButDiffNeverDoes` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::passos_recolhem_ate_abrir_por_id_mas_o_diff_nunca` (manual) |
| `ChatBlocksTests.testContiguousStepsCollapseIntoOneGroup` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::passos_seguidos_viram_uma_capa` (manual) |
| `ChatBlocksTests.testLiveTurnGetsStatusRowAndNoTime` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::turno_ao_vivo_ganha_linha_de_status_e_nao_tem_hora` (manual) |
| `ChatBlocksTests.testTypingAndAgentToAgentPrompt` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::digitando_e_prompt_de_agente_para_agente` (manual) |
| `ChatBlocksTests.testMentionOnlyWhenNotContinuous` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::mencao_so_quando_nao_e_continua` (manual) |
| `ChatBlocksTests.testActivityDoesNotChangeBlocks` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::atividade_nao_muda_as_linhas` (manual) |

### ChatClearTests.swift — 2/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatClearTests.testClearingTheHistoryTakesTheUnconfirmedEchoWithIt` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::limpar_o_historico_leva_o_eco_junto`, `rust/crates/egeon-core/src/features/chat/routes.rs::clear_arquiva_leva_o_eco_e_avisa_a_ui` (manual) |
| `ChatClearTests.testClearingResetsTheThreadState` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::limpar_zera_o_estado_da_thread` (manual) |

### ChatComposerTests.swift — 0/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatComposerTests.testHeightChangeFiresOnlyWhenHeightChanges` | NÃO PORTA | altura desejada do NSTextView do composer e callback de mudança de altura: medida de view, fica na UI (Flutter); sem teste de widget do chat ainda |
| `ChatComposerTests.testTypingDoesNotRemeasureThread` | PARCIAL | `ui/test/features/chat/chat_page_test.dart::digitar não remonta a thread` (falta: largura nova remede a thread (o Swift prova `builds + 1` ao mudar a largura; o teste Dart cobre só o digitar)) |

### ChatHistoryTests.swift — 10/10

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatHistoryTests.testCurrentLivesAtWorkbenchRoot` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::a_corrente_mora_na_raiz_da_bancada` (manual) |
| `ChatHistoryTests.testRoundTrip` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::ida_e_volta`, `rust/crates/egeon-core/src/features/chat/tests.rs::formato_da_linha_e_o_do_swift` (manual) |
| `ChatHistoryTests.testSameTurnIsNotWrittenTwice` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::o_mesmo_turno_nao_e_gravado_duas_vezes` (manual) |
| `ChatHistoryTests.testArchiveIsNamedByConversationPeriod` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::o_arquivo_leva_o_periodo_da_conversa` (manual) |
| `ChatHistoryTests.testArchiveMovesCurrentAndStartsFresh` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::arquivar_move_a_corrente_e_recomeca` (manual) |
| `ChatHistoryTests.testArchiveOnEmptyIsNoop` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::arquivar_sem_conversa_nao_faz_nada` (manual) |
| `ChatHistoryTests.testSamePeriodTwiceGetsDistinctNames` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::mesmo_periodo_duas_vezes_tem_nomes_distintos` (manual) |
| `TranscriptLastTurnTests.testLastTurnCarriesPromptAndReply` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::ultimo_turno_leva_prompt_e_resposta` (manual) |
| `TranscriptLastTurnTests.testTailThatLosesThePromptFallsBackToWholeFile` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::cauda_que_perde_o_prompt_volta_ao_arquivo_inteiro` (manual) |
| `TranscriptLastTurnTests.testEmptyOrMissing` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::ultimo_turno_vazio_ou_ausente` (manual) |

### ChatLazyLoadTests.swift — 3/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatLazyLoadTests.testOnlyVisibleRowsExistAndScrollingReusesThem` | NÃO PORTA | reuso de células do NSTableView (rowsCreated); no Flutter é ListView.builder, sem teste de widget do chat ainda |
| `ChatLazyLoadTests.testTextComesRenderedFromMeasurement` | NÃO PORTA | o texto renderizado (NSAttributedString) vem da medição do TextKit; no app novo o core manda spans e a UI desenha |
| `ChatLazyLoadTests.testRowsInsertedAboveKeepTheReaderInPlace` | NÃO PORTA | manter a linha no mesmo ponto da tela quando entra histórico em cima é ancoragem de rolagem da view; o core só entrega inserts (histórico_carrega_em_janelas_ao_rolar_ate_o_topo) e a UI ancora |
| `ChatLazyLoadTests.testHistoryLoadsInWindowsWhenScrolledToTop` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::historico_carrega_em_janelas_ao_rolar_ate_o_topo` (o gesto de rolar até o topo é da UI; o core recebe `scroll top` e cresce a janela (rota coberta em chat/routes.rs::scroll_top_cresce_a_janela_uma_vez)) |
| `ChatLazyLoadTests.testOpeningLoadsOnlyTheLastWindowAfterTheDescentSettles` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::a_descida_animada_nao_carrega_mais` (a animação de descida de 0,35 s é da UI; a regra (aberta a conversa de 300 turnos, só uma janela) está no core) |
| `ChatLazyLoadTests.testAnimatedDescentPassingTheTopDoesNotLoadMore` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::a_descida_animada_nao_carrega_mais` (manual) |

### ChatModelTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MentionParserTests.testMentionAtCaretWithQuery` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::mencao_no_cursor_com_consulta` (manual) |
| `MentionParserTests.testBareAtOpensEmptyQuery` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::arroba_sozinho_abre_consulta_vazia` (manual) |
| `MentionParserTests.testSpaceClosesMention` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::espaco_fecha_a_mencao` (manual) |
| `MentionParserTests.testAtInsideWordIsNotMention` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::arroba_dentro_de_palavra_nao_e_mencao` (manual) |
| `MentionParserTests.testCaretBeforeAtIsNotMention` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::cursor_antes_do_arroba_nao_e_mencao` (manual) |
| `MentionParserTests.testInsertReplacesTypedMention` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::inserir_troca_a_mencao_digitada` (manual) |
| `MentionParserTests.testCandidatesFilterCaseInsensitive` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::candidatos_sem_caixa` (manual) |
| `AgentPaletteTests.testColorIsDeterministic` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::cor_do_agente_e_deterministica` (manual) |
| `ChatParticipantTests.testFromNodesFiltersAndDerives` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::participantes_vem_dos_nos_agentes_e_shells` (manual) |

### ChatScrollTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatScrollTests.testNewRowIsReachedEvenBeforeTheTableRelayouts` | PORTADO | `ui/test/features/chat/chat_page_test.dart::mensagem nova com você no fim: continua no fim` (no Flutter é o ScrollController da thread, não o relayout da NSTableView) |
| `ChatScrollTests.testThreadCountsAsAtBottomWhileTheAnimatedDropIsStillRunning` | PORTADO | `ui/test/features/chat/chat_page_test.dart::descida animada em curso conta como "no fim"`, `ui/test/features/chat/chat_page_test.dart::pegar a thread na mão no meio da descida cancela a descida` (a regra do core que a acompanha (descida não carrega histórico) está em ChatLazyLoadTests) |
| `ChatScrollTests.testSendingScrollsToBottomEvenFromAboveIt` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::eco_pendente_fica_na_linha_do_tempo`, `rust/crates/egeon-core/src/features/chat/routes.rs::compose_poe_o_texto_na_caixa_e_so_envia_com_send`, `ui/test/features/chat/chat_page_test.dart::mandar de um ponto acima do fim leva ao fim` (o gesto é da UI; do core, o eco como última bolha) |

### ChatStepTests.swift — 8/8

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatStepTests.testBashResultFillsCommandOutputAndError` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::resultado_do_bash_preenche_comando_saida_e_erro` (manual) |
| `ChatStepTests.testEditShowsDiffAtToolUseAndPatchWhenResultArrives` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::edicao_mostra_o_diff_no_uso_e_o_patch_quando_o_resultado_chega` (manual) |
| `ChatStepTests.testWriteIsAllAddedAndReadCountsLines` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::write_e_tudo_adicionado_e_read_conta_linhas` (manual) |
| `ChatStepTests.testReadShowsTheFileContentHighlightedByExtension` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::leitura_mostra_o_conteudo_do_arquivo` (manual) |
| `ChatStepTests.testOutputIsCappedByLinesAndBytes` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::saida_tem_teto_de_linhas_e_de_bytes` (manual) |
| `ChatStepTests.testDiffIsCapped` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::diff_tem_teto` (manual) |
| `ChatStepTests.testStepPartRoundTripsAndOldFlatFormDecodes` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::passo_de_cadeia_vai_e_volta_e_a_forma_antiga_decodifica` (manual) |
| `ChatStepTests.testMarkdownBlocksAndSpans` | PORTADO | `rust/crates/egeon-core/src/features/chat/markdown.rs::blocos_titulo_lista_codigo_e_negrito` (a asserção de fonte em negrito no NSAttributedString é da UI; o core entrega o span `bold`) |

### ChatStepToggleTests.swift — 4/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatStepToggleTests.testToggleOpensStepAndDiffAndClosesAgain` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::alternar_abre_o_passo_e_o_diff_continua_aberto`, `rust/crates/egeon-core/src/features/chat/routes.rs::expand_abre_o_passo_e_pede_a_remontagem` (manual) |
| `ChatStepToggleTests.testOpenStepPaintsHeaderAndBodyDifferently` | PARCIAL | falta: teste Dart que compare a cor/decoração de `step-title` e `step-body` (o Swift prova brilho diferente entre cabeçalho e miolo) |
| `ChatStepToggleTests.testClickingTheGroupCoverCyclesTheLevels` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::clicar_na_capa_cicla_os_niveis` (manual) |
| `ChatStepToggleTests.testCoverClosesWhenAStepWasOpenedByHand` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::a_capa_fecha_quando_um_passo_foi_aberto_a_mao` (manual) |
| `ChatStepToggleTests.testRowTogglesOnlyOnTheTitleStrip` | PORTADO | `ui/test/features/chat/chat_page_test.dart::aberto mostra comando e saída; só o título responde ao clique` (o clique no corpo não alterna; só o do título) |

### ChatThreadReuseTests.swift — 1/1

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ChatThreadReuseTests.testRefreshWithoutChangeDoesNotRebuild` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::refresh_sem_mudanca_nao_renasce` (manual) |

### ChatThreadTests.swift — 21/21

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ClaudeTranscriptTests.testParsesPromptStepsAndReply` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::transcript_vira_prompt_passos_e_resposta` (manual) |
| `ClaudeTranscriptTests.testChainKeepsProseAndStepsInOrder` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::cadeia_guarda_prosa_e_passos_em_ordem` (manual) |
| `ClaudeTranscriptTests.testTurnWithoutPartsDecodesAndRebuildsChain` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::turno_sem_parts_decodifica_e_reconstroi_a_cadeia` (manual) |
| `ClaudeTranscriptTests.testChainPartsRoundTripWithSendTarget` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::elos_da_cadeia_voltam_do_disco_com_o_destino_do_envio` (manual) |
| `ClaudeTranscriptTests.testLiveTurnReportsWhatIsHappeningNow` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::turno_ao_vivo_diz_o_que_acontece_agora` (manual) |
| `ClaudeTranscriptTests.testAgentEnvelopeIsUnwrapped` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::envelope_de_agente_e_desembrulhado` (manual) |
| `ClaudeTranscriptTests.testOldEgeonTagIsStillUnwrapped` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::marca_antiga_ainda_e_desembrulhada` (manual) |
| `ClaudeTranscriptTests.testSendStepCarriesTarget` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::passo_de_envio_leva_o_destino` (manual) |
| `ClaudeTranscriptTests.testAssistantBeforeAnyPromptIsIgnored` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::assistente_antes_de_qualquer_prompt_e_ignorado` (manual) |
| `ChatThreadTests.testBuildInterleavesByTime` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::thread_intercala_por_tempo` (manual) |
| `ChatThreadTests.testConsecutiveReplyHasNoQuote` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::resposta_consecutiva_nao_cita` (manual) |
| `ChatThreadTests.testInterleavedPromptQuotesAgentsLastReply` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::prompt_intercalado_cita_a_ultima_resposta_do_agente` (manual) |
| `ChatThreadTests.testPendingDropsWhatTranscriptConfirmed` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::eco_sai_quando_o_transcript_confirma` (manual) |
| `ChatThreadTests.testAgentMessagesAreTheirOwnBubbles` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::mensagens_entre_agentes_sao_bolhas_proprias` (manual) |
| `ChatThreadTests.testSendTargetIgnoresHeredocNoise` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::alvo_do_envio_ignora_ruido_de_heredoc` (manual) |
| `ChatThreadTests.testLegacyExchangeDecodesToNothing` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::elo_extinto_decodifica_para_nada` (manual) |
| `ChatThreadTests.testReplyToAgentMessageQuotesTheSender` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::resposta_a_mensagem_de_agente_cita_o_remetente` (manual) |
| `ChatThreadTests.testUnknownSenderKeepsRawAddress` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::remetente_desconhecido_guarda_o_endereco_cru` (manual) |
| `ChatThreadTests.testPendingEchoSitsInTimeline` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::eco_pendente_fica_na_linha_do_tempo` (manual) |
| `ChatThreadTests.testOneNewTurnConfirmsOnePending` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::um_turno_novo_confirma_um_eco` (manual) |
| `ChatThreadTests.testKnownTurnDoesNotConfirmNewPending` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::turno_conhecido_nao_confirma_eco_novo` (manual) |

### ClaudeSkillTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ClaudeSkillTests.testFrontmatterIsReadableByTheCLI` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::frontmatter_da_skill_e_legivel_pelo_cli` (manual) |
| `ClaudeSkillTests.testTextValuesUseBlockScalarsSoPunctuationCannotBreakTheYAML` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::valores_de_texto_usam_bloco_para_a_pontuacao_nao_quebrar_o_yaml` (manual) |
| `ClaudeSkillTests.testTriggerPhrasesAreInTheFrontmatter` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::frases_de_gatilho_estao_no_frontmatter` (manual) |
| `ClaudeSkillTests.testBodyTeachesPeersBeforeSubagent` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::corpo_ensina_vizinhos_antes_de_subagente` (manual) |
| `ClaudeSkillTests.testBodyTeachesAnsweringWhoeverCalledYou` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::corpo_ensina_a_responder_a_quem_acionou` (manual) |
| `ClaudeSkillTests.testSkillLivesAtTheRootOfEachConfig` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::skill_mora_na_raiz_de_cada_config` (manual) |
| `ClaudeSkillTests.testInstallWritesIntoEveryConfig` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::install_escreve_em_toda_config_e_reescreve`, `rust/crates/egeon-core/src/features/agent/tests.rs::install_apaga_a_pasta_da_primeira_tentativa` (manual) |
| `ClaudeSkillTests.testConfigDirectoriesIncludeTheEnvironmentOne` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::configuracoes_incluem_a_do_ambiente_sem_repetir` (manual) |
| `ClaudeSkillTests.testMaestroSkillFrontmatterIsReadableAndGated` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::skill_do_maestro_tem_frontmatter_legivel_e_com_porteiro` (a parte que confere os campos do plano (MaestroPlan.Node.Keys) é do dono do maestro) |

### ClaudeTranscriptLiveTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ClaudeTranscriptLiveTests.testScanRecordsByteOffsetOfEachPrompt` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::varredura_guarda_o_byte_de_cada_prompt` (manual) |
| `ClaudeTranscriptLiveTests.testLiveTurnReadsFromKnownPromptOffset` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::leitura_ao_vivo_parte_do_offset_do_prompt` (manual) |
| `ClaudeTranscriptLiveTests.testStaleOffsetFallsBackToTail` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::offset_velho_volta_para_a_cauda` (manual) |

### ClaudeTrustTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ClaudeTrustTests.testWorktreeInheritsWhatTheRepositoryAccepted` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::worktree_herda_o_que_o_repositorio_aceitou` (manual) |
| `ClaudeTrustTests.testNothingWhenOriginNotAcceptedOrTargetAlready` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::nada_quando_origem_nao_aceitou_ou_alvo_ja_aceito` (manual) |
| `ClaudeTrustTests.testMultiFolderNeedsEveryRepository` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::multiprojeto_precisa_de_todos_os_repositorios` (manual) |
| `ClaudeTrustTests.testPrivatePrefixIsKept` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::prefixo_private_e_mantido` (manual) |
| `ClaudeTrustTests.testAcceptedParentCounts` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::pai_aceito_conta` (manual) |
| `ClaudeTrustTests.testSourcesFromRealGit` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::fontes_com_git_de_verdade` (manual) |

### ContextGaugeTests.swift — 15/15

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ContextGaugeTests.testShowsTheShareInUseRoundedUp` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::medidor_mostra_a_fatia_arredondada_para_cima`, `ui/test/features/node/agent/context_reading_test.dart::mostra a fatia em uso, arredondada para cima` (manual) |
| `ContextGaugeTests.testHueGoesFromGreenToRedAsTheWindowFills` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::matiz_vai_do_verde_ao_vermelho`, `ui/test/features/node/agent/context_reading_test.dart::o matiz vai do verde ao vermelho conforme a janela enche` (manual) |
| `ContextGaugeTests.testIndicatorWithoutReadingShowsADash` | PORTADO | `ui/test/features/node/agent/context_indicator_test.dart::sem leitura mostra um travessão; com leitura, a porcentagem` (manual) |
| `ContextGaugeTests.testAskedLargeWindowWinsOverTheCatalog` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::janela_grande_pedida_vence_o_catalogo` (manual) |
| `ContextGaugeTests.testUsageAboveTheCatalogWindowMeansTheLargeOne` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::uso_acima_da_janela_do_catalogo_e_a_grande` (manual) |
| `ContextGaugeTests.testFullWindowStopsAtAHundred` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::janela_cheia_para_em_cem`, `ui/test/features/node/agent/context_reading_test.dart::janela cheia para em 100%` (manual) |
| `ContextGaugeTests.testUnknownWindowHasNoGauge` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::janela_desconhecida_nao_tem_medidor` (manual) |
| `ContextGaugeTests.testShortNumbers` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::numeros_curtos`, `ui/test/features/node/agent/context_reading_test.dart::números curtos` (manual) |
| `ContextGaugeTests.testRegistryReadsTheWindowNotTheMaximum` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::registro_le_a_janela_e_nao_o_maximo` (manual) |
| `ContextGaugeTests.testCatalogWithoutSchemaIsOld` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::catalogo_sem_schema_e_antigo` (manual) |
| `ContextTokensTests.testCountsThePromptOfTheLastAnswerWithoutOutput` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::contexto_conta_o_prompt_da_ultima_resposta_sem_a_saida` (manual) |
| `ContextTokensTests.testSkipsSubagentsAndFabricatedAnswers` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::contexto_pula_subagente_e_resposta_fabricada` (manual) |
| `ContextTokensTests.testCompactionHidesTheOldNumberUntilTheNextAnswer` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::compactar_esconde_o_numero_velho_ate_a_proxima_resposta` (manual) |
| `ContextTokensTests.testQuotingTheBoundaryIsNotCompaction` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::citar_o_marcador_nao_e_compactar` (manual) |
| `ContextTokensTests.testNoAnswerYet` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::contexto_sem_resposta_ainda` (manual) |

### DiffHunkTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `DiffHunkTests.testParsesHeadersAndKinds` | PORTADO | `rust/crates/egeon-core/src/features/chat/diff_hunk.rs::le_cabecalho_e_tipos` (manual) |
| `DiffHunkTests.testDiffWithoutHeaderHasNoNumbers` | PORTADO | `rust/crates/egeon-core/src/features/chat/diff_hunk.rs::diff_sem_cabecalho_nao_tem_numeros` (manual) |
| `DiffHunkTests.testRowsPairRemovalsWithAdditionsLikeGitHub` | PORTADO | `rust/crates/egeon-core/src/features/chat/diff_hunk.rs::linhas_pareiam_remocoes_com_adicoes_como_o_github` (manual) |
| `DiffHunkTests.testStructuredPatchKeepsHunkHeader` | PORTADO | `rust/crates/egeon-core/src/features/chat/diff_hunk.rs::cabecalho_do_structured_patch` (manual) |

### DispatchRequestTests.swift — 10/10

| Teste | Situação | Onde / motivo |
|---|---|---|
| `DispatchRequestTests.testRawIsTheTextItself` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::raw_is_the_text_itself` (exato) |
| `DispatchRequestTests.testRawWithoutTextIsNothing` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::raw_without_text_is_nothing` (exato) |
| `DispatchRequestTests.testTaskWrapsWithHeaderAndApply` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::task_wraps_with_header_and_apply` (exato) |
| `DispatchRequestTests.testRemovedReviewKindDeliversNothing` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::removed_review_kind_delivers_nothing` (exato) |
| `DispatchRequestTests.testSenderTurnsAnyKindIntoTheAgentEnvelope` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::sender_turns_any_kind_into_the_agent_envelope` (exato) |
| `DispatchRequestTests.testEnvelopeWithoutTextIsNothing` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::envelope_without_text_is_nothing` (exato) |
| `DispatchRequestTests.testMissingKindDefaultsToRaw` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::missing_kind_defaults_to_raw` (exato) |
| `DispatchRequestTests.testMessageToShellIsRawAndToAgentIsEnveloped` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::message_to_shell_is_raw_and_to_agent_is_enveloped` (exato) |
| `DispatchRequestTests.testSlashCommandGoesRawWithNoticeBefore` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::slash_command_goes_raw_with_notice_before` (exato) |
| `DispatchRequestTests.testPathOrTextIsNotACommand` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/request.rs::path_or_text_is_not_a_command` (exato) |

### EdgeControllerTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `EdgeControllerTests.testEdgeIsBornBidirectional` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::a_ligacao_nasce_nos_dois_sentidos` (manual) |
| `EdgeControllerTests.testDuplicateEdgeIsIgnored` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::ligacao_repetida_e_ignorada` (manual) |
| `EdgeControllerTests.testRemoveTakesBothDirections` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::remover_leva_os_dois_sentidos` (manual) |
| `EdgeControllerTests.testApplyEmptyDirectionCreatesThenOnlyQueries` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::direcao_vazia_cria_e_depois_so_consulta` (manual) |
| `EdgeControllerTests.testApplyNoneUndoesTheEdge` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::none_desfaz_a_ligacao` (manual) |
| `EdgeControllerTests.testApplyRejectsUnknownNode` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::no_desconhecido_ou_igual_e_recusado` (manual) |
| `EdgeControllerTests.testCycleIsFoundBreadthFirst` | PORTADO | `rust/crates/egeon-core/src/features/canvas/tests.rs::o_ciclo_e_achado_em_largura` (manual) |

### EdgeCurveTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `EdgeCurveTests.testStackedCardsConnectBottomToTop` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::cards empilhados ligam a base ao topo` (manual) |
| `EdgeCurveTests.testSlightlyShiftedColumnIsStillStacked` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::coluna levemente deslocada ainda é empilhada` (manual) |
| `EdgeCurveTests.testSideBySideStaysDirect` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::lado a lado continua direta` (manual) |
| `EdgeCurveTests.testTargetBehindAndNotStackedStillLoops` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::destino atrás e fora da coluna ainda volta por baixo` (manual) |
| `EdgeCurveTests.testOverlappingCardsDoNotStack` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::cards sobrepostos não ganham rota vertical` (manual) |
| `EdgeCurveTests.testStackedEndpointsPointAlongTheColumn` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::as pontas da rota empilhada apontam ao longo da coluna` (manual) |
| `EdgeCurveTests.testControlsCenterOnAVerticalEdge` | PORTADO | `ui/test/features/canvas/domain/edge_curve_test.dart::os controles ficam no meio da linha de pé e acima na deitada` (manual) |

### EdgeLinkTests.swift — 8/8

| Teste | Situação | Onde / motivo |
|---|---|---|
| `EdgeLinkTests.testPairOrdersByName` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::par_ordena_por_nome` (manual) |
| `EdgeLinkTests.testCollapseJoinsBothDirectionsIntoOneLink` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::colapsar_junta_os_dois_sentidos_numa_ligacao` (manual) |
| `EdgeLinkTests.testCollapseLimitOfAToBWins` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::colapsar_vale_o_limite_de_a_para_b` (manual) |
| `EdgeLinkTests.testCycledNeverReachesNoDirection` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::ciclo_nunca_chega_a_nenhum_sentido` (manual) |
| `EdgeLinkTests.testEdgesMaterializesOnlyActiveDirections` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::so_os_sentidos_ativos_viram_arestas` (manual) |
| `EdgeLinkTests.testLinkEqualityIgnoresDirection` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::igualdade_da_ligacao_ignora_a_direcao` (manual) |
| `EdgeLinkTests.testDecodeDistinguishesAbsentFromNull` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::leitura_distingue_ausente_de_null` (manual) |
| `EdgeLinkTests.testEdgeEqualityIgnoresLimit` | PORTADO | `rust/crates/egeon-core/src/features/edge/model.rs::igualdade_da_aresta_ignora_o_limite` (manual) |

### EffortDialTests.swift — 10/12

| Teste | Situação | Onde / motivo |
|---|---|---|
| `EffortDialTests.testStartsOnTheCurrentLevel` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::dial_comeca_no_nivel_atual`, `ui/test/features/node/agent/effort_dial_view_test.dart::testStartsOnTheCurrentLevel: a marca fica no nível que o core ` (manual) |
| `EffortDialTests.testKeepsAnUnknownCurrentLevel` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::dial_guarda_nivel_desconhecido`, `ui/test/features/node/agent/effort_dial_view_test.dart::testKeepsAnUnknownCurrentLevel: o nível fora da lista aparece ` (manual) |
| `EffortDialTests.testTextTakesOnlyItsWidthAndTheControlsStayRight` | NÃO PORTA | largura preferida do texto e posição do slider/pílula (fittingSize, frames do NSView); layout é da UI |
| `EffortDialTests.testAutoShowsTheModelLevelDimmedAndLitPill` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::auto_mostra_o_nivel_do_modelo`, `ui/test/features/node/agent/effort_dial_view_test.dart::testAutoShowsTheModelLevelDimmedAndLitPill: em auto a barra ` (a opacidade do slider e a pílula acesa são da UI; a regra (marca no nível do modelo, em auto) é do core) |
| `EffortDialTests.testTogglingAutoOffKeepsTheLevelTheModelWasUsing` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::desligar_o_auto_mantem_o_nivel_que_o_modelo_usava`, `ui/test/features/node/agent/effort_dial_view_test.dart::testTogglingAutoOffKeepsTheLevelTheModelWasUsing: a pílula ` (manual) |
| `EffortDialTests.testTogglingAutoOffWithoutKnownLevelPicksTheMiddle` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::desligar_o_auto_sem_nivel_conhecido_pega_o_meio`, `ui/test/features/node/agent/effort_dial_view_test.dart::testTogglingAutoOffWithoutKnownLevelPicksTheMiddle: a marca ` (manual) |
| `EffortDialTests.testTogglingAutoOnFromALevel` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::ligar_o_auto_a_partir_de_um_nivel`, `ui/test/features/node/agent/effort_dial_view_test.dart::testTogglingAutoOnFromALevel: ligar o auto devolve a intenção; ` (manual) |
| `EffortDialTests.testTouchingTheSliderLeavesAuto` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::tocar_na_barra_sai_do_auto`, `ui/test/features/node/agent/effort_dial_view_test.dart::testTouchingTheSliderLeavesAuto: tocar na barra em auto manda ` (manual) |
| `EffortDialTests.testNoEffortModelHasNoAutoPill` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::modelo_sem_esforco_nao_tem_o_que_ligar`, `ui/test/features/node/agent/effort_dial_view_test.dart::testNoEffortModelHasNoAutoPill: sem níveis a barra desliga, ` (manual) |
| `EffortDialTests.testAccessoryRowGrowsTheHeader` | NÃO PORTA | altura do cabeçalho do NodeView com a linha acessória (headerExtent, frame do corpo); layout do nó é da UI |
| `LastModelSinceTests.testIgnoresAnswersFromBeforeTheLaunch` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::modelo_descarta_resposta_anterior_ao_arranque` (manual) |
| `LastModelSinceTests.testKeepsAnswersAfterTheLaunch` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::modelo_mantem_resposta_posterior_ao_arranque` (manual) |

### FlavorTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `FlavorTests.testConfigDirectoriesAreSeparate` | PORTADO | `rust/crates/egeon-core/src/commons/paths.rs::pastas_do_estavel_e_do_dev_sao_separadas` (as pastas do app novo são .egeon-next e .egeon-next-dev (não .egeon/.egeon-dev); o teste Rust prova que são distintas; nunca_as_pastas_do_swift prova que não pisam nas do Swift) |
| `FlavorTests.testConfigBuildsInsideOwnDirectory` | PORTADO | `rust/crates/egeon-core/src/commons/paths.rs::caminhos_dentro_da_pasta` (manual) |
| `FlavorTests.testLogsAreSeparate` | PORTADO | `rust/crates/egeon-core/src/commons/paths.rs::logs_do_estavel_e_do_dev_sao_separados` (decisão 38) |
| `FlavorTests.testCurrentWithoutBundleIsStable` | PORTADO | `rust/crates/egeon-core/src/commons/paths.rs::sem_a_variavel_e_estavel` (sem bundle vira 'sem variável de ambiente de sabor') |

### FolderAccessTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `FolderAccessTests.testReadableMissingAndBlocked` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::pasta_legivel_ausente_e_bloqueada` (manual) |
| `FolderAccessTests.testNamesTheProtectedFolderAsSettingsShowsIt` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::nomeia_a_pasta_protegida_como_o_ajustes_mostra` (manual) |
| `FolderAccessTests.testServiceOfEachProtectedFolder` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::o_servico_de_cada_pasta_protegida` (manual) |
| `FolderAccessTests.testRequestOutsideAnAppIsJustTheCheck` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::pedir_sem_o_que_zerar_e_so_a_conferencia`, `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::pasta_protegida_negada_zera_o_servico_e_confere_de_novo` (manual) |

### HandCursorTests.swift — 1/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `HandCursorTests.testClickableViewsDefineTheirCursor` | PORTADO | `ui/test/commons/hand_cursor_test.dart::pega o clicável sem cursor e deixa passar o que tem a mão` (a régua (expectHandOnEveryClickable, em ui/test/support/hand_cursor.dart) roda sobre cada tela; a lista fixa de classes do Swift não existe em Flutter) |
| `HandCursorTests.testTheHandCoversTheWholeViewOnlyWhenClickable` | NÃO PORTA | resetCursorRects de NSView/NSButton (AppKit); em Flutter a mão é um MouseRegion e a régua da outra é o que há |

### HookEventTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `HookEventTests.testTheKnownEvents` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::the_known_events` (exato) |
| `HookEventTests.testUnknownEventDoesNotParse` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::unknown_event_does_not_parse` (exato) |
| `HookEventTests.testExpectedListsAllCases` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::expected_lists_all_cases` (exato) |

### KeyMonitorTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `KeyMonitorTests.testPlainKeysReachThePty` | PORTADO | `rust/crates/egeon-core/src/runtime/actor/dispatch_commands.rs::digitar_no_terminal_fecha_a_permissao_e_zera_a_cadeia`, `ui/test/features/node/terminal/terminal_key_mapper_test.dart::as teclas comuns chegam ao pty` (qual tecla chega ao pty é da UI (`reachesPty`); a tecla que chega vira `dispatch_user_typed` no core) |
| `KeyMonitorTests.testTabShortcutsDoNotCountAsTyping` | PORTADO | `ui/test/features/node/terminal/terminal_key_mapper_test.dart::os atalhos de aba não contam como digitação` (qual tecla chega ao pty é da UI (`reachesPty`); a tecla que chega vira `dispatch_user_typed` no core) |
| `KeyMonitorTests.testPasteStillCounts` | PORTADO | `rust/crates/egeon-core/src/runtime/actor/dispatch_commands.rs::digitar_no_terminal_fecha_a_permissao_e_zera_a_cadeia`, `ui/test/features/node/terminal/terminal_key_mapper_test.dart::colar continua contando` (qual tecla chega ao pty é da UI (`reachesPty`); a tecla que chega vira `dispatch_user_typed` no core) |

### MaestroControllerTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MaestroControllerTests.testOnlyAMaestroMayAsk` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::only_a_maestro_may_ask` (exato) |
| `MaestroControllerTests.testBenchMarksWhoIsAsking` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::bench_marks_who_is_asking` (exato) |
| `MaestroControllerTests.testDryRunChangesNothing` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::dry_run_changes_nothing` (exato) |
| `MaestroControllerTests.testInvalidPlanChangesNothingAndListsErrors` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::invalid_plan_changes_nothing_and_lists_errors` (exato) |
| `MaestroControllerTests.testApplyCommitsFirstThenTouchesTheScreenAndLeavesATrace` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::apply_commits_first_then_touches_the_screen_and_leaves_a_trace` (exato) |
| `MaestroControllerTests.testPlanThatChangesNothingDoesNotTouchAnything` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::plan_that_changes_nothing_does_not_touch_anything` (exato) |

### MaestroLinksLayoutTests.swift — 15/15

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MaestroLinksLayoutTests.testMaestroReachesEveryoneAndAgentsReachBack` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::maestro_reaches_everyone_and_agents_reach_back` (exato) |
| `MaestroLinksLayoutTests.testDrawnEdgeWinsOverTheImplicitOne` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::drawn_edge_wins_over_the_implicit_one` (exato) |
| `MaestroLinksLayoutTests.testWithoutMaestroNothingIsAdded` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::without_maestro_nothing_is_added` (exato) |
| `MaestroLinksLayoutTests.testLayoutPutsMaestroLeftTeamInGridShellsBelow` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::layout_puts_maestro_left_team_in_grid_shells_below` (exato) |
| `MaestroLinksLayoutTests.testMaestroKeepsItsPlaceAndTheTeamFollowsIt` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::maestro_keeps_its_place_and_the_team_follows_it` (exato) |
| `MaestroLinksLayoutTests.testLinkedAgentsGetRoomForTheArrows` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::linked_agents_get_room_for_the_arrows` (exato) |
| `MaestroLinksLayoutTests.testPlanDoesNotMoveTheMaestro` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::plan_does_not_move_the_maestro` (exato) |
| `MaestroLinksLayoutTests.testLinkedTeamFlowsLeftToRightAndCentersTheTarget` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::linked_team_flows_left_to_right_and_centers_the_target` (exato) |
| `MaestroLinksLayoutTests.testCycleIsAnchoredOnTheTarget` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::cycle_is_anchored_on_the_target` (exato) |
| `MaestroLinksLayoutTests.testOnlyTwoWayPairsStackInOneColumn` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::only_two_way_pairs_stack_in_one_column` (exato) |
| `MaestroLinksLayoutTests.testChainOfOneWayArrowsMakesColumns` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::chain_of_one_way_arrows_makes_columns` (exato) |
| `MaestroLinksLayoutTests.testOneWayCycleDoesNotHang` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::one_way_cycle_does_not_hang` (exato) |
| `MaestroLinksLayoutTests.testPlanFrameMovesAndResizesACard` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::plan_frame_moves_and_resizes_a_card` (exato) |
| `MaestroLinksLayoutTests.testPlanWithLayoutIsNotEmpty` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::plan_with_layout_is_not_empty` (exato) |
| `MaestroLinksLayoutTests.testGuideExampleIsAValidPlan` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::guide_example_is_a_valid_plan` (exato) |

### MaestroPermissionsTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MaestroPermissionsTests.testApproverIsTheMaestroAndNeverTheAsker` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::approver_is_the_maestro_and_never_the_asker` (exato) |
| `MaestroPermissionsTests.testNoticeIsOneShortLineWithTheCommands` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::notice_is_one_short_line_with_the_commands` (exato) |
| `MaestroPermissionsTests.testListingShowsOnlyTheTeamsToolRequests` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::listing_shows_only_the_teams_tool_requests` (exato) |
| `MaestroPermissionsTests.testAnswerRefusals` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::answer_refusals` (exato) |
| `MaestroPermissionsTests.testAnswerGoesThroughAndIsTraced` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::answer_goes_through_and_is_traced` (exato) |
| `MaestroPermissionsTests.testOnlyTheUserGrantsIt` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::only_the_user_grants_it` (exato) |

### MaestroPlanTests.swift — 39/39

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MaestroPlanTests.testAbsentNullAndValueAreThreeDifferentThings` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::absent_null_and_value_are_three_different_things` (exato) |
| `MaestroPlanTests.testUnknownKeyIsAnErrorNamingTheField` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unknown_key_is_an_error_naming_the_field` (exato) |
| `MaestroPlanTests.testUnknownTopLevelKeyIsAnError` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unknown_top_level_key_is_an_error` (exato) |
| `MaestroPlanTests.testBrokenJSONSaysSo` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::broken_json_says_so` (exato) |
| `MaestroPlanTests.testEmptyBodyIsAnError` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::empty_body_is_an_error` (exato) |
| `MaestroPlanTests.testNewAgentGetsDefaultsAndNoDrawnEdge` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::new_agent_gets_defaults_and_no_drawn_edge` (exato) |
| `MaestroPlanTests.testPlanCanStillDrawAMaestroEdgeWithItsOwnLimit` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::plan_can_still_draw_a_maestro_edge_with_its_own_limit` (exato) |
| `MaestroPlanTests.testShellNodeRejectsAgentFields` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::shell_node_rejects_agent_fields` (exato) |
| `MaestroPlanTests.testShellGetsCommandAndOneWayLink` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::shell_gets_command_and_one_way_link` (exato) |
| `MaestroPlanTests.testChangingAShellCommandRestartsIt` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::changing_a_shell_command_restarts_it` (exato) |
| `MaestroPlanTests.testConfigMustBeOneTheCLIKnows` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::config_must_be_one_the_cli_knows` (exato) |
| `MaestroPlanTests.testIdMustBeASlug` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::id_must_be_a_slug` (exato) |
| `MaestroPlanTests.testUnknownModelIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unknown_model_is_refused` (exato) |
| `MaestroPlanTests.testEffortMustBelongToTheChosenModel` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::effort_must_belong_to_the_chosen_model` (exato) |
| `MaestroPlanTests.testCLIThatDoesNotTakeModelSaysSo` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::cli_that_does_not_take_model_says_so` (exato) |
| `MaestroPlanTests.testUnknownCLIListsTheKnownOnes` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unknown_cli_lists_the_known_ones` (exato) |
| `MaestroPlanTests.testMissingFolderIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::missing_folder_is_refused` (exato) |
| `MaestroPlanTests.testUpdateKeepsWhatIsAbsentAndTheConversation` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::update_keeps_what_is_absent_and_the_conversation` (exato) |
| `MaestroPlanTests.testNullGoesBackToTheDefault` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::null_goes_back_to_the_default` (exato) |
| `MaestroPlanTests.testSwitchingCLIDropsTheConversation` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::switching_cli_drops_the_conversation` (exato) |
| `MaestroPlanTests.testRoleWrittenByThePlanBeatsTheCLIOverride` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::role_written_by_the_plan_beats_the_cli_override` (exato) |
| `MaestroPlanTests.testSameValuesDoNotRestart` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::same_values_do_not_restart` (exato) |
| `MaestroPlanTests.testChangingFolderStartsAFreshConversation` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::changing_folder_starts_a_fresh_conversation` (exato) |
| `MaestroPlanTests.testOnlyWhatChangedIsValidated` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::only_what_changed_is_validated` (exato) |
| `MaestroPlanTests.testOtherMaestroAndNonTerminalNodesAreOffLimits` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::other_maestro_and_non_terminal_nodes_are_off_limits` (exato) |
| `MaestroPlanTests.testChainGuardsHaveACeiling` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::chain_guards_have_a_ceiling` (exato) |
| `MaestroPlanTests.testUnlinkOfARemovedNodeIsNotAnError` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unlink_of_a_removed_node_is_not_an_error` (exato) |
| `MaestroPlanTests.testBenchOnlyKeysAreIgnoredButMaestroIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::bench_only_keys_are_ignored_but_maestro_is_refused` (exato) |
| `MaestroPlanTests.testKindDoesNotChange` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::kind_does_not_change` (exato) |
| `MaestroPlanTests.testMaestroCannotTouchItself` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::maestro_cannot_touch_itself` (exato) |
| `MaestroPlanTests.testBusyNodeIsNotRestartedNorRemoved` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::busy_node_is_not_restarted_nor_removed` (exato) |
| `MaestroPlanTests.testBackgroundNodeNeedsForceButWorkingNeverPasses` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::background_node_needs_force_but_working_never_passes` (exato) |
| `MaestroPlanTests.testBenchRulesRestartTheOtherAgentsButNotTheMaestro` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::bench_rules_restart_the_other_agents_but_not_the_maestro` (exato) |
| `MaestroPlanTests.testRemovingTakesItsEdgesAlong` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::removing_takes_its_edges_along` (exato) |
| `MaestroPlanTests.testEdgeToMissingNodeIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::edge_to_missing_node_is_refused` (exato) |
| `MaestroPlanTests.testUnlinkBoth` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::unlink_both` (exato) |
| `MaestroPlanTests.testErrorsAccumulateInsteadOfStoppingAtTheFirst` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::errors_accumulate_instead_of_stopping_at_the_first` (exato) |
| `MaestroPlanTests.testLayoutOnlyWhenTheTeamChangesUnlessAsked` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::layout_only_when_the_team_changes_unless_asked` (exato) |
| `MaestroPlanTests.testSummaryReadsLikeTheTrace` | PORTADO | `rust/crates/egeon-core/src/features/maestro/tests.rs::summary_reads_like_the_trace` (exato) |

### MarkdownLinkTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MarkdownLinkTests.testMarkdownLinkShowsLabelAndCarriesURL` | PORTADO | `rust/crates/egeon-core/src/features/chat/markdown.rs::link_mostra_o_rotulo_e_leva_a_url` (manual) |
| `MarkdownLinkTests.testBracketsWithoutSchemeStayText` | PORTADO | `rust/crates/egeon-core/src/features/chat/markdown.rs::colchetes_sem_esquema_ficam_texto` (manual) |
| `MarkdownLinkTests.testBareURLBecomesLink` | PORTADO | `rust/crates/egeon-core/src/features/chat/markdown.rs::url_solta_vira_link` (manual) |
| `MarkdownLinkTests.testLinkifyKeepsExistingLink` | PORTADO | `rust/crates/egeon-core/src/features/chat/markdown.rs::linkify_respeita_o_link_que_ja_existe` (manual) |

### ModelCatalogTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ModelCatalogTests.testReadsTheTableAndSkipsDecoysAndRepeats` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::le_a_tabela_e_pula_iscas_e_repeticoes` (manual) |
| `ModelCatalogTests.testEffortLevelsFollowCapabilities` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::niveis_de_esforco_seguem_as_capacidades` (manual) |
| `ModelCatalogTests.testFeaturedIsTheNewestOfEachFamilyInMenuOrder` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::destaque_e_o_mais_novo_de_cada_familia_na_ordem_do_menu` (manual) |
| `ModelCatalogTests.testResolvesWhatTheNodeAskedOrTheTranscriptRecorded` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::resolve_o_que_o_no_pediu_ou_o_transcript_gravou` (manual) |
| `ModelCatalogTests.testBinaryWithoutTableGivesNothing` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::binario_sem_tabela_nao_da_nada` (manual) |
| `ModelCatalogTests.testUltracodeMovesTheLevelToTheEnvironment` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::ultracode_leva_o_nivel_para_o_ambiente` (manual) |
| `ModelChoiceOfferTests.testFlagWithEmptyListOffersNothing` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::faixa_do_cabecalho_so_com_o_que_escolher` (manual) |

### MultiProjectTests.swift — 29/29

| Teste | Situação | Onde / motivo |
|---|---|---|
| `MultiProjectTests.testDecodesOldProjectsAsFolders` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::projeto_antigo_abre_como_pasta` (manual) |
| `MultiProjectTests.testMembersRoundTrip` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::membros_vao_e_voltam` (manual) |
| `MultiProjectTests.testMembersSkipMissingAndMulti` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::membros_pulam_o_que_sumiu_e_o_multi`, `rust/crates/egeon-core/src/features/workspace/tests.rs::membros_do_multi_na_ordem_dele_sem_os_que_sumiram` (manual) |
| `MultiProjectTests.testNewMultiResolvesFoldersToProjectIDs` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::multi_novo_resolve_as_pastas_para_ids` (manual) |
| `MultiProjectTests.testMultiCanUseFolderAddedInTheSameForm` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::multi_pode_usar_pasta_adicionada_no_mesmo_formulario` (manual) |
| `MultiProjectTests.testEditingKeepsIDAndFolderMatchingIgnoresMultis` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::editar_guarda_o_id_e_a_pasta_ignora_multis` (manual) |
| `MultiProjectTests.testRemovedMultiWithWorkbenchesStays` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::multi_tirado_com_bancada_fica` (manual) |
| `MultiProjectTests.testRemovedMultiWithoutWorkbenchesGoes` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::multi_tirado_sem_bancada_vai_embora` (manual) |
| `MultiProjectTests.testLinkNamesDisambiguateSameFolderName` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::nomes_de_link_desambiguam_a_mesma_pasta` (manual) |
| `MultiProjectTests.testWorktreeRootLivesUnderCommonParentAndProjectName` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::raiz_da_worktree_mora_sob_o_pai_comum_e_o_nome_do_projeto` (manual) |
| `MultiProjectTests.testCommonParentFallsBackToFirstWhenOnlyRootIsShared` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::pai_comum_cai_no_primeiro_quando_so_a_raiz_e_comum` (manual) |
| `MultiProjectTests.testMovingTiedProjectsToAnotherWorkspaceIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::projeto_amarrado_nao_muda_de_workspace` (manual) |
| `MultiProjectTests.testLinkSyncCreatesReplacesAndKeepsForeignFiles` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::sincronizar_cria_troca_e_guarda_o_que_nao_e_link` (manual) |
| `MultiProjectTests.testPruneRootOnlyRemovesLinkOnlyFolders` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::podar_so_apaga_pasta_so_de_links`, `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::subpastas_de_verdade_nao_incluem_links` (manual) |
| `MultiProjectBranchTests.testEveryRepoFollowsTheWorkbenchBranchByDefault` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::todo_repo_segue_a_branch_da_bancada_por_padrao` (manual) |
| `MultiProjectBranchTests.testOverrideChangesOnlyThatRepo` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::a_troca_muda_so_aquele_repo` (manual) |
| `MultiProjectBranchTests.testRootIsNamedAfterTheWorkbenchBranchWhateverTheRepoBranches` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::a_raiz_leva_o_nome_da_branch_da_bancada_seja_qual_for_a_do_repo` (manual) |
| `FolderSuggestionsTests.testOnlyWhatIsInsideTheWorkbenchRelative` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::so_o_que_esta_dentro_da_bancada_relativo` (manual) |
| `FolderSuggestionsTests.testRepoChildrenAreFoldersOrLinksWithGit` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::filhos_de_repo_sao_pastas_ou_links_com_git` (o teste Rust também confere que pasta oculta com .git fica de fora) |
| `RootOptionTests.testRootIsShownForEmpty` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::a_raiz_aparece_como_root_para_vazio` (manual) |
| `RootOptionTests.testFolderOptionsStartAtRootAndKeepACustomCurrent` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::a_lista_de_pasta_comeca_na_raiz_e_guarda_a_atual_customizada` (manual) |
| `ShellCommandTests.testShellCommandRoundTripsAndInstantiates` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::o_comando_do_shell_vai_e_volta_e_instancia` (manual) |
| `ShellCommandTests.testCaptureKeepsShellCommand` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::capturar_guarda_o_comando_do_shell` (manual) |
| `ShellCommandTests.testAgentLegacyRootCmdStillMigratesToByAgent` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::campos_da_raiz_antigos_viram_o_mapa_do_cli` (confere que cmd da raiz vai para o mapa do CLI e não é regravado na raiz; que `command` fica nulo vem implícito) |
| `LastConfigTests.testRememberAndForget` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::lembrar_e_esquecer`, `rust/crates/egeon-core/src/features/workspace/tests.rs::lembrar_a_configuracao_e_apagar_com_o_padrao` (manual) |
| `ConfigItemsTests.testDefaultIsShownByPathAndNotRepeated` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::o_padrao_aparece_pelo_caminho_e_nao_se_repete` (manual) |
| `ConfigItemsTests.testMissingCurrentIsKept` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::a_atual_que_sumiu_da_lista_fica` (manual) |
| `ConfigItemsTests.testProfileDefaultComesFromTheGlob` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::configuracoes_incluem_a_do_ambiente_sem_repetir`, `rust/crates/egeon-core/src/features/agent/tests.rs::configuracoes_descobertas_so_diretorios` (config_glob == ~/.claude* num teste; default_config_path == ~/.claude no outro) |
| `MultiRequiresWorktreeTests.testOnlyMultiRequiresWorktree` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::so_o_multi_exige_worktree` (manual) |

### NewProjectTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `NewProjectTests.testSuggestsTheParentMostProjectsShare` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::sugere_a_pasta_mae_que_mais_projetos_dividem` (manual) |
| `NewProjectTests.testTieGoesToTheNewestProject` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::empate_fica_com_o_projeto_mais_novo` (manual) |
| `NewProjectTests.testIgnoresMultiProjectsAndFallsBackWhenEmpty` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::ignora_multi_projeto_e_cai_no_padrao_quando_vazio` (manual) |
| `NewProjectTests.testNewFolderIsCreatedWithTildePath` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::pasta_nova_e_criada_com_caminho_com_til` (manual) |
| `NewProjectTests.testExistingFolderIsAdoptedNotRecreated` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::pasta_existente_e_adotada_nao_recriada` (manual) |
| `NewProjectTests.testRefusals` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::recusas`, `rust/crates/egeon-core/src/features/workspace/tests_multi.rs::as_mensagens_das_recusas` (manual) |

### NodeConfigTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `NodeConfigTests.testLegacySessionIdIsAbsorbedOnLoad` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::nome_antigo_da_sessao_e_absorvido_na_carga` (manual) |
| `NodeConfigTests.testLegacyNamesNeverGoBackToDisk` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::nomes_antigos_nunca_voltam_ao_disco` (manual) |
| `NodeConfigTests.testMigrationDoesNotOverwriteNewName` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::migracao_nao_sobrescreve_o_nome_novo` (manual) |
| `NodeConfigTests.testWithoutConversationClearsConversationAndKeepsAssembly` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::sem_conversa_limpa_a_conversa_e_guarda_a_montagem` (manual) |
| `NodeConfigTests.testFormEditKeepsConversationWithSameCLIAndFolder` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::edicao_do_formulario_guarda_a_conversa_com_mesmo_cli_e_pasta` (manual) |
| `NodeConfigTests.testFormEditDropsConversationWhenFolderOrCLIChanges` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::edicao_largua_a_conversa_se_a_pasta_ou_o_cli_mudam` (manual) |
| `NodeConfigTests.testFormEditKeepsWebAddress` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::edicao_do_formulario_guarda_o_endereco_web` (manual) |

### NodeTemplateCrossCLITests.swift — 11/11

| Teste | Situação | Onde / motivo |
|---|---|---|
| `NodeTemplateCrossCLITests.testTheRoleCrossesEveryCLI` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::o_papel_atravessa_todo_cli` (manual) |
| `NodeTemplateCrossCLITests.testCLISpecificValuesDoNotLeak` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::valor_de_um_cli_nao_vaza_para_outro` (manual) |
| `NodeTemplateCrossCLITests.testEditingUnderAnotherCLIKeepsWhatTheFirstOneHad` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::editar_sob_outro_cli_guarda_o_que_o_primeiro_tinha` (manual) |
| `NodeTemplateCrossCLITests.testRememberingOneCLIKeepsTheOthers` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::lembrar_um_cli_guarda_os_outros` (manual) |
| `NodeTemplateCrossCLITests.testReopeningDoesNotPromoteOneCLIsTextToGeneral` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::reabrir_nao_promove_o_texto_de_um_cli_a_geral` (manual) |
| `NodeTemplateCrossCLITests.testTheAgentMapSurvivesInTheNode` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::o_mapa_de_cli_sobrevive_no_no` (manual) |
| `NodeTemplateCrossCLITests.testRulesOverrideRatherThanAdd` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::regra_por_cli_substitui_em_vez_de_somar` (manual) |
| `NodeTemplateCrossCLITests.testInstantiateUsesTheChosenCLI` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::instanciar_usa_o_cli_escolhido` (manual) |
| `NodeTemplateCrossCLITests.testLegacyRootFieldsBecomeTheAgentMap` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::campos_da_raiz_antigos_viram_o_mapa_do_cli`, `rust/crates/egeon-core/src/features/node/tests.rs::comando_de_shell_fica_na_raiz_e_o_mapa_ja_escrito_ganha` (manual) |
| `NodeTemplateCrossCLITests.testCaptureSplitsRoleFromCLI` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::captura_separa_o_papel_do_cli` (manual) |
| `NodeTemplateCrossCLITests.testEffortTravelsWithItsCLI` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::esforco_viaja_com_o_cli` (manual) |

### NodeTemplateTests.swift — 3/3

| Teste | Situação | Onde / motivo |
|---|---|---|
| `NodeTemplateTests.testCaptureCopiesAssemblyOnly` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::captura_copia_so_a_montagem` (manual) |
| `NodeTemplateTests.testInstantiateBuildsNodeWithoutConversation` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::instanciar_monta_o_no_sem_conversa` (manual) |
| `NodeTemplateTests.testIdentifierIsPredictable` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::identificador_e_previsivel` (manual) |

### PeekGuardTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `PeekGuardTests.testYouMayPeekAnyone` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/tests.rs::you_may_peek_anyone` (exato) |
| `PeekGuardTests.testAgentMayPeekOnlyItsPeers` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/tests.rs::agent_may_peek_only_its_peers` (exato) |
| `PeekGuardTests.testAgentMayAlwaysPeekItself` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/tests.rs::agent_may_always_peek_itself` (exato) |
| `EgeonCLIBodyTests.testPeekIsOfferedAndDocumented` | PORTADO | `rust/crates/egeon-cli/tests/commands.rs::peek_leva_as_linhas_so_quando_dadas`, `rust/crates/egeon-cli/tests/commands.rs::sem_argumento_ou_comando_desconhecido_imprime_o_uso_e_sai_com_2` (o script bash virou o binário `egeon`; o teste confere a rota /peek e o texto de uso embutido (24 linhas, até o allow)) |
| `EgeonCLIBodyTests.testMaestroCommandsAndGuide` | PORTADO | `rust/crates/egeon-cli/tests/commands.rs::leituras_sao_get_e_devolvem_o_corpo_como_veio`, `rust/crates/egeon-cli/tests/commands.rs::plan_e_apply_levam_o_plano_do_stdin`, `rust/crates/egeon-cli/tests/commands.rs::guide_imprime_o_manual_embutido_sem_o_app` (manual) |

### PermissionDeskTests.swift — 16/16

| Teste | Situação | Onde / motivo |
|---|---|---|
| `PermissionDeskTests.testAskReadsToolSummaryAndDetail` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::ask_reads_tool_summary_and_detail` (exato) |
| `PermissionDeskTests.testSetModeSuggestionIsDropped` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::set_mode_suggestion_is_dropped` (exato) |
| `PermissionDeskTests.testPayloadWithoutToolIsRefused` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::payload_without_tool_is_refused` (exato) |
| `PermissionDeskTests.testSummaryByTool` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::summary_by_tool` (exato) |
| `PermissionDeskTests.testHookOutputShapes` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::hook_output_shapes` (exato) |
| `PermissionDeskTests.testAnsweredOnceThenGone` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::answered_once_then_gone` (exato) |
| `PermissionDeskTests.testDropMakesItGone` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::drop_makes_it_gone` (exato) |
| `PermissionDeskTests.testAsksOfTheSameTerminalCoexist` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::asks_of_the_same_terminal_coexist` (exato) |
| `PermissionDeskTests.testAsksExpireWithTheHook` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::asks_expire_with_the_hook` (exato) |
| `PermissionDeskTests.testRenameFollowsTheWorkbench` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::rename_follows_the_workbench` (exato) |
| `PermissionQuestionTests.testQuestionsAreRead` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::questions_are_read` (exato) |
| `PermissionQuestionTests.testOtherToolsHaveNoQuestions` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::other_tools_have_no_questions` (exato) |
| `PermissionQuestionTests.testChoicesMustCoverEveryQuestionWithinItsOptions` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::choices_must_cover_every_question_within_its_options` (exato) |
| `PermissionQuestionTests.testAnswerOutputKeepsInputAndJoinsMultiSelect` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::answer_output_keeps_input_and_joins_multi_select` (exato) |
| `PermissionQuestionTests.testDeskRefusesBadChoicesAndKeepsTheAskOpen` | PORTADO | `rust/crates/egeon-core/src/features/permission/tests.rs::desk_refuses_bad_choices_and_keeps_the_ask_open` (exato) |
| `PermissionQuestionTests.testQuestionToolLineOnlyForHookedProfile` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::linha_da_pergunta_so_para_perfil_com_gancho` (manual) |

### ProcessTableTests.swift — 14/14

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ProcessTableTests.testDescendantsOfTheAppAreOwnedAndInheritTheNode` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::descendentes_do_app_sao_dele_e_herdam_o_no` (manual) |
| `ProcessTableTests.testUnreadableShellTakesTheNodeFromItsChild` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::shell_ilegivel_pega_o_no_do_filho` (manual) |
| `ProcessTableTests.testMarkedProcessOutsideTheAppIsAnOrphanWithItsChildren` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::marcado_fora_do_app_e_orfao_com_os_filhos` (manual) |
| `ProcessTableTests.testOtherFlavorAndItsTreeAreNotOurs` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::outro_flavor_e_a_arvore_dele_nao_sao_nossos`, `rust/crates/egeon-core/src/features/processes/model.rs::core_novo_e_outro_app_e_tem_deck_proprio` (manual) |
| `ProcessTableTests.testAppOpenedFromATerminalIsNotAnOrphan` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::app_aberto_de_um_terminal_nao_e_orfao` (manual) |
| `ProcessTableTests.testLegacyTargetWithoutDeckStillCounts` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::alvo_antigo_sem_deck_ainda_conta` (manual) |
| `ProcessTableTests.testProcargsParsing` | PORTADO | `rust/crates/egeon-driver/src/procs/macos.rs::procargs_separa_argumentos_do_ambiente` (manual) |
| `ProcessTableTests.testOrderAndAge` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::ordem_e_idade` (manual) |
| `ProcessTableTests.testChildEnvironmentDropsInheritedMarks` | PORTADO | `rust/crates/egeon-core/src/features/terminal/environment.rs::procedencia_herdada_sai_pela_lista_da_montagem`, `rust/crates/egeon-driver/tests/environment.rs::filho_lancado_nao_enxerga_claude_code_nem_procedencia_herdada` (manual) |
| `ProcessTableTests.testCLIOffersPs` | PORTADO | `rust/crates/egeon-cli/tests/commands.rs::ps_orphans_e_kill` (manual) |
| `ProcessTableTests.testDescendantsCrossProcessGroups` | PORTADO | `rust/crates/egeon-core/src/ports/procs.rs::descendentes_atravessam_grupos_e_deixam_a_raiz_de_fora` (manual) |
| `ProcessTableTests.testReapTakesOldOrphansButSparesTheClaudeDaemon` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::limpeza_leva_orfao_velho_e_poupa_o_daemon_do_claude` (manual) |
| `ProcessTableTests.testPolicyFileFillsMissingKeys` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::arquivo_da_politica_completa_o_que_falta` (manual) |
| `ProcessTableTests.testRelaunchLoopWithoutReadableMarkIsAdoptedByItsChildren` | PORTADO | `rust/crates/egeon-core/src/features/processes/model.rs::laco_que_relanca_sem_marca_legivel_e_adotado_pelos_filhos` (manual) |

### PromptQueueTests.swift — 26/26

| Teste | Situação | Onde / motivo |
|---|---|---|
| `PromptQueueTests.testDestinationFallsBackToFirstLinked` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::destino_cai_no_primeiro_ligado` (manual) |
| `PromptQueueTests.testMoveStaysInsideTheList` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::mover_fica_dentro_da_lista`, `ui/test/features/node/queue/prompt_queue_test.dart::subir e descer não sai da lista` (manual) |
| `PromptQueueTests.testDragMoveCountsOnlyTheRowsThatStayed` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::arrasto_conta_so_as_linhas_que_ficaram`, `ui/test/features/node/queue/prompt_queue_test.dart::o arrasto conta só as linhas que ficaram no lugar` (manual) |
| `PromptQueueTests.testRunnerWaitsForWorkThenFinishesAndSendsNextOnlyInAuto` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_runner_espera_o_trabalho_fecha_e_so_no_automatico_manda_o_proximo` (manual) |
| `PromptQueueTests.testRunnerGivesUpOnLostDelivery` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_runner_desiste_de_entrega_perdida` (manual) |
| `PromptQueueTests.testRunnerStartsAutoWhenIdleAndNothingInFlight` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_runner_comeca_o_automatico_quando_ocioso_e_nada_em_andamento` (manual) |
| `PromptQueueTests.testAutoWalksTheQueueOneTurnAtATime` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_automatico_anda_a_fila_um_turno_por_vez` (manual) |
| `PromptQueueTests.testManualSendWithoutLinkOrWithFailureKeepsItemPending` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::envio_manual_sem_ligacao_ou_com_falha_mantem_o_item_pendente`, `ui/test/features/node/queue/queue_cubit_test.dart::sem ligação, mandar mostra o aviso e ele some sozinho` (manual) |
| `PromptQueueTests.testSendingOverAnInFlightItemClosesIt` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::mandar_por_cima_de_um_item_em_andamento_o_encerra`, `ui/test/features/node/queue/queue_cubit_test.dart::mandar por cima de uma em andamento fecha a anterior` (manual) |
| `PromptQueueTests.testImagesGoAsAbsolutePathsAndLeaveWithTheItem` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::imagens_vao_como_caminho_absoluto_e_saem_com_o_item` (manual) |
| `PromptQueueTests.testTargetsChangingNotifiesTheView` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::mudar_os_ligados_avisa_a_view` (manual) |
| `PromptQueueTests.testEnterAfterAnOpenTaskInsertsBelowItAndBlankOnesGoAway` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::enter_depois_de_uma_tarefa_aberta_insere_abaixo_e_as_em_branco_somem`, `ui/test/features/node/queue/queue_cubit_test.dart::Enter numa tarefa aberta abre outra logo abaixo dela` (manual) |
| `PromptQueueTests.testCheckboxMarksDoneByHandAndBack` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::checkbox_marca_feito_a_mao_e_volta`, `ui/test/features/node/queue/queue_cubit_test.dart::o checkbox marca e desmarca à mão; limpar tira o que foi` (manual) |
| `PromptQueueTests.testAttachAndDetachImages` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::anexar_e_desanexar_imagens` (manual) |
| `PromptQueueTests.testFooterOnlyGoesToAgentsAndCarriesTheShortID` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::rodape_so_vai_para_agente_e_leva_o_id_curto` (manual) |
| `PromptQueueTests.testAgentTicksAsksAndNotesByShortID` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_agente_marca_pergunta_e_comenta_pelo_id_curto` (manual) |
| `PromptQueueTests.testOpenQuestionHoldsTheQueueUntilYouReply` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::pergunta_aberta_segura_a_fila_ate_voce_responder` (manual) |
| `PromptQueueTests.testCommentBeforeSendingGoesWithTheTask` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::comentario_antes_de_enviar_vai_com_a_tarefa` (manual) |
| `PromptQueueTests.testOldFileWithoutThreadStillLoads` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::arquivo_antigo_sem_thread_ainda_abre` (manual) |
| `PromptQueueTests.testHeadlineIsTheFirstLineShortened` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::a_manchete_e_a_primeira_linha_encurtada` (manual) |
| `PromptQueueTests.testReplySaysWhichTaskByItsFirstLine` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::a_resposta_diz_de_que_tarefa_fala_pela_primeira_linha` (manual) |
| `PromptQueueTests.testChatSummarySaysWhatTheQueueNeeds` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::o_resumo_do_chat_diz_o_que_a_fila_precisa` (manual) |
| `PromptQueueTests.testDraggedWidthHoldsWithinLimits` | PORTADO | `ui/test/features/node/queue/prompt_queue_test.dart::a largura arrastada fica dentro dos limites` (manual) |
| `PromptQueueTests.testPanelLeavesRoomForTheConversation` | PORTADO | `ui/test/features/node/queue/prompt_queue_test.dart::o painel deixa espaço para a conversa` (manual) |
| `PromptQueueTests.testSentTaskOnlyMovesOnThroughTheThread` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::tarefa_enviada_so_anda_pela_thread` (manual) |
| `PromptQueueTests.testTaskDoneByHandCanStillBeEdited` | PORTADO | `rust/crates/egeon-core/src/features/queue/tests.rs::tarefa_feita_a_mao_ainda_pode_ser_editada` (manual) |

### RetiredNodeTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `RetiredNodeTests.testWorkbenchDropsEditorAndKeepsTheRest` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::bancada_tira_o_editor_e_guarda_o_resto` (manual) |
| `RetiredNodeTests.testOtherBadNodeIsStillAnError` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::outro_no_ruim_continua_sendo_erro` (manual) |
| `RetiredNodeTests.testWorkbenchTemplateDropsEditor` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::template_de_bancada_tira_o_editor` (manual) |
| `RetiredNodeTests.testNodeComponentOfEditorKindIsSkipped` | PORTADO | `rust/crates/egeon-core/src/features/node/tests.rs::componente_do_tipo_editor_e_pulado` (manual) |

### SenderBacklogTests.swift — 2/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `SenderBacklogTests.testCountsOnlyTheSender` | PROVÁVEL | `rust/crates/egeon-core/src/features/dispatch/request.rs::backlog_counts_only_the_sender` (provável) |
| `SenderBacklogTests.testWholeTeamCountsOneEach` | PROVÁVEL | `rust/crates/egeon-core/src/features/dispatch/request.rs::backlog_whole_team_counts_one_each` (provável) |

### ShellEncoderTests.swift — 1/1

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ShellEncoderTests.testEncodesSpacePlusAndUTF8ByteByByte` | PORTADO | `rust/crates/egeon-cli/src/encode.rs::espaco_mais_e_utf8_byte_a_byte` (manual) |

### SidebarDropTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `SidebarDropTests.testCountSealCentersTheDigit` | PORTADO | `ui/test/commons/count_seal_test.dart::o dígito $value fica no centro do selo` (um teste por valor (1, 5 e 12)) |
| `SidebarDropTests.testWorkbenchDropsIntoTheProjectUnderTheCursor` | PORTADO | `ui/test/features/sidebar/sidebar_drop_test.dart::a bancada cai no projeto sob o cursor` (manual) |
| `SidebarDropTests.testMovingDownInsideTheSameProjectDiscountsItself` | PORTADO | `ui/test/features/sidebar/sidebar_drop_test.dart::para baixo no próprio projeto a linha que sai não conta` (manual) |
| `SidebarDropTests.testDraggingEndsInAMoveAndTheGuideGoesAway` | PORTADO | `ui/test/features/sidebar/sidebar_page_test.dart::a bancada cai no fim do projeto, com guia onde vai entrar`, `ui/test/features/sidebar/sidebar_page_test.dart::desistir no meio não move nada` (o laço começar/arrastar/soltar/desistir é testado com gestos no widget) |
| `SidebarDropTests.testDroppingBelowTheDrawerStoresTheProject` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::soltar_na_gaveta_guarda_o_projeto_e_fora_dela_tira`, `ui/test/features/sidebar/sidebar_drop_test.dart::a gaveta: abaixo da tampa guarda; acima dela, tira`, `ui/test/features/sidebar/sidebar_drop_test.dart::a gaveta existe mesmo vazia ou fechada: é o alvo do primeiro guardado` (manual) |
| `SidebarDropTests.testProjectAndWorkspaceTargets` | PORTADO | `ui/test/features/sidebar/sidebar_drop_test.dart::projeto solto sobre outro workspace entra nele`, `ui/test/features/sidebar/sidebar_drop_test.dart::o workspace passa pela metade do card vizinho para trocar`, `ui/test/features/sidebar/sidebar_page_test.dart::as órfãs não se arrastam` (manual) |

### SlashCommandTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `SlashCommandTests.testActiveQueryOnlyAtStartAndBeforeSpace` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::comando_so_no_comeco_e_antes_do_espaco` (manual) |
| `SlashCommandTests.testInsertKeepsTheRestOfTheMessage` | PORTADO | `rust/crates/egeon-core/src/features/chat/parsers.rs::inserir_mantem_o_resto_da_mensagem` (manual) |
| `SlashCommandTests.testMatchingPrefersPrefixAndPluginShortName` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::matching_prefere_prefixo_e_nome_curto_do_plugin` (manual) |
| `SlashCommandTests.testSearchMatchesEveryWordInNameAliasOrDescription` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::busca_casa_cada_palavra_no_nome_apelido_ou_descricao` (manual) |
| `SlashCommandTests.testFrontmatterFoldedQuotedAndHidden` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::frontmatter_dobrado_aspas_e_oculto` (manual) |
| `SlashCommandTests.testCatalogReadsUserProjectAndEnabledPlugins` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::catalogo_le_usuario_projeto_e_plugins_ligados` (manual) |
| `SlashCommandTests.testRegistryReadsBuiltinsAndBundledSkillsFromBinary` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::registro_le_embutidos_e_skills_do_binario` (manual) |
| `SlashCommandTests.testSkillListingKeepsOrderAndRestartsOnInitial` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::listagem_da_sessao_mantem_a_ordem_e_recomeca_no_inicial` (manual) |
| `SlashCommandTests.testCatalogMergesSyncedSessionAndBinary` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::catalogo_junta_sincronizado_sessao_e_binario` (manual) |

### StopReportTests.swift — 13/13

| Teste | Situação | Onde / motivo |
|---|---|---|
| `StopReportTests.testQueryCarriesBackgroundAndLastMessage` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::query_carries_background_and_last_message` (exato) |
| `StopReportTests.testPageWatchersAreNotBackgroundWork` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::page_watchers_are_not_background_work` (exato) |
| `StopReportTests.testQueryWithoutFieldsIsUnknown` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::query_without_fields_is_unknown` (exato) |
| `StopReportTests.testPendingPeerBeatsAsk` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::pending_peer_beats_ask` (exato) |
| `StopReportTests.testBackgroundCountDecidesWaitAndSilence` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::background_count_decides_wait_and_silence` (exato) |
| `StopReportTests.testOkBeatsLongLivedBackground` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::ok_beats_long_lived_background` (exato) |
| `StopReportTests.testBackgroundTasksAreDescribedForTheLog` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::background_tasks_are_described_for_the_log` (exato) |
| `StopReportTests.testReplyIsRecognizedFromEitherSide` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::reply_is_recognized_from_either_side` (exato) |
| `StopReportTests.testAskBeatsBackground` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::ask_beats_background` (exato) |
| `StopReportTests.testWithoutPayloadTheMarkerDecides` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::without_payload_the_marker_decides` (exato) |
| `StopReportTests.testPeerWaitKeepsOrderAndNoDuplicates` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::peer_wait_keeps_order_and_no_duplicates` (exato) |
| `StopReportTests.testPeerWaitResolvesOnlyWhoIsThere` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::peer_wait_resolves_only_who_is_there` (exato) |
| `StopReportTests.testPeerWaitFollowsRename` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/stop.rs::peer_wait_follows_rename` (exato) |

### SyntaxLiteTests.swift — 8/8

| Teste | Situação | Onde / motivo |
|---|---|---|
| `SyntaxLiteTests.testLanguageComesFromExtensionOnly` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::linguagem_vem_so_da_extensao` (manual) |
| `SyntaxLiteTests.testLanguageFromFenceLabelAndFromCommand` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::linguagem_pelo_rotulo_e_pelo_comando` (manual) |
| `SyntaxLiteTests.testSwiftAndShellTokens` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::tokens_de_swift_e_shell` (manual) |
| `SyntaxLiteTests.testFencedBlockKeepsItsLabel` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::bloco_cercado_guarda_o_rotulo` (manual) |
| `SyntaxLiteTests.testPython` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::python` (manual) |
| `SyntaxLiteTests.testTypeScriptAndDart` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::typescript_e_dart` (manual) |
| `SyntaxLiteTests.testHTML` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::html` (manual) |
| `SyntaxLiteTests.testJSONAndPlain` | PORTADO | `rust/crates/egeon-core/src/features/chat/syntax.rs::json_e_plain` (manual) |

### SystemNoticeTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `SystemNoticeTests.testAskingCarriesWhatIsWaiting` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::asking_carries_what_is_waiting` (exato) |
| `SystemNoticeTests.testFinishedWithoutDetail` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::finished_without_detail` (exato) |
| `SystemNoticeTests.testStatesThatComeBackAloneDoNotNotify` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::states_that_come_back_alone_do_not_notify` (exato) |
| `SystemNoticeTests.testLongDetailIsClipped` | PORTADO | `rust/crates/egeon-core/src/features/activity/tests.rs::long_detail_is_clipped` (exato) |

### TabDragLayoutTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `TabDragLayoutTests.testOffsetsStackWithTheGap` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::deslocamentos_empilham_com_o_vao`, `ui/test/features/tabs/tab_drag_layout_test.dart::os x empilham com o espaço entre as pastilhas` (manual) |
| `TabDragLayoutTests.testStandingStillKeepsThePosition` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::parado_guarda_a_posicao`, `ui/test/features/tabs/tab_drag_layout_test.dart::parado, a pastilha mantém a posição` (manual) |
| `TabDragLayoutTests.testTouchingTheNeighbourIsNotEnough` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::encostar_na_vizinha_nao_basta`, `ui/test/features/tabs/tab_drag_layout_test.dart::encostar na vizinha não basta: só troca depois do centro dela` (manual) |
| `TabDragLayoutTests.testDraggingToTheEndAndToTheStart` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::arrastar_ate_o_fim_e_ate_o_comeco`, `ui/test/features/tabs/tab_drag_layout_test.dart::arrastar até o fim e até o começo` (manual) |
| `TabDragLayoutTests.testBeyondTheEdgesClampsInsteadOfOverflowing` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::alem_das_bordas_prende_em_vez_de_estourar`, `ui/test/features/tabs/tab_drag_layout_test.dart::para fora da faixa prende nas pontas em vez de estourar o índice` (manual) |
| `TabDragLayoutTests.testMovedTakesOutAndPutsBackIn` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::moved_tira_e_poe_de_volta`, `ui/test/features/tabs/tab_drag_layout_test.dart::moved tira de um lugar e põe no outro` (manual) |
| `TabDragLayoutTests.testUnknownIndexIsInert` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::indice_desconhecido_e_inerte`, `ui/test/features/tabs/tab_drag_layout_test.dart::índice desconhecido é inerte: bancada que saiu no meio do arrasto` (manual) |

### TerminalLinkTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `TerminalLinkTests.testRelativePathResolvesAgainstTheDirectoriesInOrder` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::relativo_resolve_nas_pastas_em_ordem` (manual) |
| `TerminalLinkTests.testLineAndColumnSuffixIsDropped` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::sufixo_de_linha_e_coluna_sai` (manual) |
| `TerminalLinkTests.testAFileWhoseNameEndsInColonDigitsWinsOverTheSuffix` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::arquivo_com_dois_pontos_no_nome_vence_o_sufixo` (manual) |
| `TerminalLinkTests.testHomeIsExpanded` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::home_e_expandida` (a home vem por parâmetro (a pasta padrão da configuração), não de NSHomeDirectory) |
| `TerminalLinkTests.testMissingFileOpensNothing` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::arquivo_que_nao_existe_nao_abre_nada`, `rust/crates/egeon-core/src/features/terminal/link.rs::espaco_horizontal_nas_pontas_sai_como_no_swift` (manual) |
| `TerminalLinkTests.testUrlsPassThroughUntouched` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::url_passa_intacta` (manual) |
| `TerminalLinkTests.testProsePunctuationIsDropped` | PORTADO | `rust/crates/egeon-core/src/features/terminal/link.rs::pontuacao_da_frase_sai` (manual) |
| `TerminalLinkTests.testWordUnderTheColumn` | PORTADO | `rust/crates/egeon-terminal/src/link.rs::palavra_sob_a_coluna`, `rust/crates/egeon-terminal/tests/interaction.rs::link_implicito_e_nome_solto` (a palavra sob a coluna é achada no terminal (`link_at` devolve `LinkHit::Word`)) |
| `TerminalLinkTests.testBareNameResolvesThroughTheWord` | PORTADO | `rust/crates/egeon-terminal/src/link.rs::pontuacao_da_frase_sai_da_palavra`, `rust/crates/egeon-core/src/features/terminal/link.rs::nome_solto_resolve`, `rust/crates/egeon-core/src/runtime/actor/terminal_commands.rs::cmd_clique_em_nome_solto_entrega_o_soltar_e_abre_se_existe` (dividido em três: a palavra no terminal, a resolução no core e o ⌘-clique no ator) |

### TraceTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `TraceEntryTests.testMarkdownStampsWhoAndWith` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::markdown_carimba_quem_e_com_que` (manual) |
| `TraceEntryTests.testMissingIdentityLeavesNoStampLine` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::sem_identidade_nao_deixa_linha_de_carimbo` (manual) |
| `TraceEntryTests.testTextIsTrimmedAndCapped` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::texto_e_aparado_e_cortado` (manual) |
| `TraceEntryTests.testSplitsAddress` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::separa_o_endereco` (manual) |
| `TraceLogTests.testFolderIsTheWorkbenchID` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::a_pasta_e_o_id_da_bancada` (manual) |
| `TraceLogTests.testArchiveMovesTraceAndNextEntryStartsFresh` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::arquivar_move_a_trilha_e_a_proxima_entrada_abre_outra` (manual) |
| `TraceLogTests.testHeaderCarriesNameAndIDOnceThenAgentsInterleaveInOrder` | PORTADO | `rust/crates/egeon-core/src/features/trace/tests.rs::cabecalho_uma_vez_e_os_agentes_em_ordem` (manual) |

### TranscriptMarkerTests.swift — 14/14

| Teste | Situação | Onde / motivo |
|---|---|---|
| `TranscriptMarkerTests.testOkAtEndOfLastReply` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::ok_at_end_of_last_reply` (manual) |
| `TranscriptMarkerTests.testAskWins` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::ask_wins` (manual) |
| `TranscriptMarkerTests.testWaitMeansBackground` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::wait_means_background` (manual) |
| `TranscriptMarkerTests.testLowestOfTheThreeWins` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::lowest_of_the_three_wins` (manual) |
| `TranscriptMarkerTests.testWaitIsStrippedFromTheChat` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::wait_is_stripped_from_the_chat` (manual) |
| `TranscriptMarkerTests.testLegacyInstructionStillTeachesWait` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::legacy_instruction_still_teaches_wait` (manual) |
| `TranscriptMarkerTests.testOnlyTheLastReplyCounts` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::only_the_last_reply_counts` (manual) |
| `TranscriptMarkerTests.testMentionAboveDoesNotOverrideFinalMarker` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::mention_above_does_not_override_final_marker` (manual) |
| `TranscriptMarkerTests.testSkipsTrailingToolUseOnlyLines` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::skips_trailing_tool_use_only_lines` (manual) |
| `TranscriptMarkerTests.testCarriesTheLineTimestamp` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::carries_the_line_timestamp` (manual) |
| `TranscriptMarkerTests.testNoMarkerIsNil` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::no_marker_is_nil` (manual) |
| `TranscriptMarkerTests.testReadsOnlyTheTailOfTheFile` | PORTADO | `rust/crates/egeon-core/src/features/dispatch/marker.rs::reads_only_the_tail_of_the_file` (manual) |
| `TranscriptModelTests.testLastAssistantModelWins` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::o_ultimo_modelo_vence` (manual) |
| `TranscriptModelTests.testSyntheticIsSkipped` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::sintetico_e_pulado` (manual) |

### UnversionedCopyTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `UnversionedCopyTests.testScriptWrittenByTheAppIsStockEvenWithAnotherHeader` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::script_escrito_pelo_app_e_de_fabrica_mesmo_com_outro_cabecalho` (manual) |
| `UnversionedCopyTests.testEditedScriptIsNotStock` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::script_editado_nao_e_de_fabrica` (manual) |
| `UnversionedCopyTests.testCopiesUntrackedAndIgnoredButNotTracked` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::copia_o_nao_rastreado_e_o_ignorado_mas_nao_o_versionado` (o clone real (clonefile) é do driver; o teste Rust usa um clonador de cópia comum atrás da interface FileCloner) |
| `UnversionedCopyTests.testExistingDestinationIsKept` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::o_destino_que_ja_existe_fica` (manual) |

### UsageTests.swift — 12/12

| Teste | Situação | Onde / motivo |
|---|---|---|
| `UsageTests.testEntriesCountEachMessageOnce` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::entradas_contam_cada_mensagem_uma_vez` (manual) |
| `UsageTests.testCacheWriteWithoutSplitIsFiveMinutes` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::escrita_de_cache_sem_divisao_e_de_cinco_minutos` (manual) |
| `UsageTests.testPriceKeysAndCost` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::chaves_de_preco_e_custo` (manual) |
| `UsageTests.testLedgerReadsOnlyCompleteLinesAndKeepsTheCursor` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::registro_le_so_linhas_completas_e_guarda_o_cursor` (manual) |
| `UsageTests.testTraceConversations` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::conversas_da_trilha` (manual) |
| `UsageTests.testTurnCarriesItsUsage` | PORTADO | `rust/crates/egeon-core/src/features/chat/tests.rs::o_turno_carrega_o_seu_consumo` (manual) |
| `UsageTests.testMoneyText` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::texto_do_dinheiro` (manual) |
| `UsageTests.testPriceChangeOnlyCountsFromThenOn` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::preco_novo_so_conta_dali_para_frente` (manual) |
| `UsageTests.testTokensWithoutPriceFreezeWhenThePriceArrives` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::tokens_sem_preco_congelam_quando_o_preco_chega` (manual) |
| `UsageTests.testLegacyLedgerReadsTokensAsPending` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::registro_antigo_le_tokens_como_pendentes` (manual) |
| `UsageTests.testPricesFromTheClaudeCodeCatalog` | PORTADO | `rust/crates/egeon-core/src/features/agent/tests.rs::precos_do_catalogo_do_claude_code` (manual) |
| `UsageTests.testCatalogOverBuiltInAndFileOverBoth` | PORTADO | `rust/crates/egeon-core/src/features/usage/tests.rs::precos_em_camadas` (manual) |

### ViewModeTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `ViewModeTests.testRawValuesAreFileFormat` | PORTADO | `ui/test/core/domain/view_mode_test.dart::os nomes são formato de arquivo e parâmetro de rota` (no Rust o raw() do ViewMode não é afirmado literalmente; só a ida e volta de "view" em todo_campo_da_bancada_vai_e_volta) |
| `ViewModeTests.testMissingViewDefaultsToCanvas` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::modo_desconhecido_vira_canvas`, `ui/test/core/domain/view_mode_test.dart::ausente vira canvas e chat é lido` (manual) |
| `ViewModeTests.testUnknownViewFallsBackToCanvas` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::modo_desconhecido_vira_canvas`, `ui/test/core/domain/view_mode_test.dart::modo desconhecido ou aposentado (mosaico) abre no canvas` (manual) |
| `ViewModeTests.testRemovedMosaicOpensInCanvas` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::modo_desconhecido_vira_canvas`, `ui/test/core/domain/view_mode_test.dart::modo desconhecido ou aposentado (mosaico) abre no canvas` (o Rust testa view:"mosaic" sem o bloco mosaic com proporções (serde ignora campo desconhecido); ViewMode.all só é afirmado no Dart) |

### WorkbenchCleanerTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchCleanerTests.testArchivesOnlyAfterTheAgentsSettle` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::so_arquiva_depois_que_os_agentes_assentam` (manual) |
| `WorkbenchCleanerTests.testStuckAgentDoesNotHoldTheCleanupForever` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::agente_atolado_nao_prende_a_limpeza_para_sempre` (manual) |
| `WorkbenchCleanerTests.testAgentsWithoutClearAreSkippedAndDoNotDelayArchiving` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::agentes_sem_clear_sao_pulados_e_nao_atrasam_o_arquivamento` (manual) |
| `WorkbenchCleanerTests.testAgentAskingForPermissionIsNotWaitedFor` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::agente_pedindo_permissao_nao_e_esperado` (manual) |
| `WorkbenchCleanerTests.testDispatchFailureCountsAsSkipped` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::falha_no_despacho_conta_como_pulado` (manual) |

### WorkbenchClockTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchClockTests.testPhasesRunTogether` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::as_fases_andam_juntas` (manual) |
| `WorkbenchClockTests.testFailedIsNeitherWaitingNorRunning` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::falha_nao_e_espera_nem_trabalho` (manual) |
| `WorkbenchClockTests.testAddCapsLongGaps` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::somar_limita_os_buracos_longos` (manual) |
| `WorkbenchClockTests.testFormat` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::formato_de_relogio`, `ui/test/features/workbench/clock_test.dart::o formato é mm:ss, e h:mm:ss a partir de uma hora` (manual) |
| `WorkbenchClockTests.testTickAccumulatesPersistsAndResets` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::o_tique_soma_grava_e_zera` (manual) |
| `WorkbenchClockTests.testOldFileTakesLastActiveFromModificationDate` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::arquivo_antigo_tira_o_last_active_da_data_de_modificacao` (manual) |

### WorkbenchColorTests.swift — 8/8

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchColorTests.testPicksTheLeastUsedAndTheFirstOnTies` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::escolhe_a_menos_usada_e_a_primeira_no_empate` (manual) |
| `WorkbenchColorTests.testStatusColorsStayOutOfTheAutomaticChoice` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::cores_de_estado_ficam_fora_da_escolha_automatica` (manual) |
| `WorkbenchColorTests.testOldListGetsDistinctColorsInOrderAndKeepsWhatItHad` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::lista_antiga_ganha_cores_distintas_em_ordem_e_guarda_o_que_tinha` (manual) |
| `WorkbenchColorTests.testNewBenchIsColoredAgainstTheOthers` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::bancada_nova_e_colorida_contra_as_outras` (manual) |
| `WorkbenchColorTests.testColorRoundTripsAndUnknownOneDoesNotBreakTheList` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::cor_vai_e_volta_e_a_desconhecida_nao_quebra_a_lista`, `ui/test/theme/workbench_palette_test.dart::sem cor, ou com cor que saiu da paleta, vale o destaque do app` (manual) |
| `WorkbenchColorTests.testColorIsFoundByCaseOrMenuLabel` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::cor_achada_pelo_nome_ou_pelo_rotulo` (manual) |
| `WorkbenchColorTests.testPaletteHasTwentyFourNamedColors` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::paleta_tem_vinte_e_quatro_cores_com_nome`, `ui/test/theme/workbench_palette_test.dart::a paleta tem 24 cores com rótulo e nome únicos` (manual) |
| `WorkbenchColorTests.testColorsSavedBeforeTheBigPaletteStillDecode` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::cores_gravadas_antes_da_paleta_grande_ainda_abrem`, `ui/test/theme/workbench_palette_test.dart::as cores gravadas antes da paleta grande continuam lendo` (manual) |

### WorkbenchConfigTests.swift — 17/17

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchConfigTests.testAddressIsWorkbenchSlashNode` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::endereco_e_bancada_barra_no` (manual) |
| `WorkbenchConfigTests.testTargetsAreOutgoingEdgesOnly` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::alvos_sao_so_as_arestas_de_saida` (manual) |
| `WorkbenchConfigTests.testOldMaxVisitsIsIgnored` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::maxvisits_antigo_e_ignorado` (manual) |
| `WorkbenchConfigTests.testResolveCwdThreeForms` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::resolve_cwd_nas_tres_formas` (o home entra como parâmetro em vez de NSHomeDirectory()) |
| `WorkbenchConfigTests.testResolvedDirectoryWithoutCwdIsTheRoot` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::diretorio_resolvido_sem_cwd_e_a_raiz` (manual) |
| `WorkbenchTemplateTests.testCaptureStripsConversationAndReducesWebToOrigin` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::captura_tira_a_conversa_e_reduz_o_web_a_origem`, `rust/crates/egeon-core/src/features/workbench/tests.rs::origem_da_url_do_template` (manual) |
| `WorkbenchTemplateTests.testInstantiateZeroesConversationAgain` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::instanciar_zera_a_conversa_de_novo` (manual) |
| `NodeWorktreeTests.testSameBranchInsideGoesAlong` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::mesma_branch_dentro_da_bancada_vai_junto` (manual) |
| `NodeWorktreeTests.testOtherBranchInsideGetsOwnWorktree` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::outra_branch_dentro_da_bancada_ganha_worktree_propria` (manual) |
| `NodeWorktreeTests.testNeighborRepoWithBranchGetsOwnWorktree` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::repo_vizinho_com_branch_ganha_worktree_propria_mesmo_na_mesma_branch` (manual) |
| `NodeWorktreeTests.testEmptyBranchStays` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::branch_vazia_fica` (manual) |
| `NodeWorktreeTests.testNonGitFolderNeverGetsWorktree` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::pasta_fora_de_git_nunca_ganha_worktree` (manual) |
| `WorkbenchIDTests.testNewIDIsEightHex` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::id_novo_tem_oito_hex_e_nao_repete` (manual) |
| `WorkbenchIDTests.testLegacyFileGetsAnIDAndKeepsIt` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::arquivo_antigo_ganha_id_e_o_guarda` (manual) |
| `WorkbenchIDTests.testStoredIDWins` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::id_gravado_vence` (manual) |
| `WorkbenchIDTests.testSameNameDifferentIDs` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::mesmo_nome_ids_diferentes` (manual) |
| `WorkbenchIDTests.testRulesSurviveARoundTrip` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::regras_sobrevivem_a_gravar_e_reler`, `rust/crates/egeon-core/src/features/workbench/tests.rs::todo_campo_da_bancada_vai_e_volta` (manual) |

### WorkbenchLookupTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchLookupTests.testIndexAndIdAreTwoWays` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::indice_e_id_andam_nos_dois_sentidos` (manual) |
| `WorkbenchLookupTests.testOutOfRangeAndUnknownAreNilAndNotACrash` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::fora_da_faixa_e_desconhecido_sao_none_e_nao_pânico` (manual) |
| `WorkbenchLookupTests.testIdSurvivesRemovalWhilePositionDoesNot` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::id_sobrevive_a_remocao_e_a_posicao_nao` (manual) |
| `WorkbenchLookupTests.testRenameKeepsTheId` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::rename_mantem_o_id` (manual) |
| `WorkbenchLookupTests.testAddressSplitsOnTheFirstSlashOnly` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::endereco_parte_na_primeira_barra` (o split mora em commons::ids::Address::parse (retorna Err em vez de nil)) |

### WorkbenchRemovalTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchRemovalTests.testAllRemovedSucceeds` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::tudo_removido_tem_sucesso` (manual) |
| `WorkbenchRemovalTests.testLeftoversCountAsRemovedAndGoToSweep` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::sobras_contam_como_removidas_e_vao_para_a_faxina` (manual) |
| `WorkbenchRemovalTests.testFailureKeepsGoingAndIsReported` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::falha_segue_adiante_e_e_relatada` (manual) |
| `WorkbenchRemovalTests.testNothingToRemoveSucceeds` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_clean.rs::nada_a_remover_tem_sucesso` (manual) |

### WorkbenchShellLayoutTests.swift — 2/2

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchShellLayoutTests.testBarSpansFullWidthInEveryMode` | PORTADO | `ui/test/features/home/home_shell_page_test.dart::a barra corre de borda a borda em todo modo` (geometria de view: a medida fica na UI (WorkbenchShell/NSView virou HomeShellPage)) |
| `WorkbenchShellLayoutTests.testOnlyContentYieldsToSidebar` | PORTADO | `ui/test/features/home/home_shell_page_test.dart::só o conteúdo cede à barra lateral, e só no chat` (geometria de view: a medida fica na UI; no Flutter o canvas corre por baixo do vidro da barra lateral e só o chat cede) |

### WorkbenchStoreTests.swift — 5/5

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchStoreTests.testLegacyFileCountsOnlyWhenTheNewOneNeverExisted` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::arquivo_antigo_so_vale_quando_o_novo_nunca_existiu` (manual) |
| `WorkbenchStoreTests.testEmptyListIsAStateAndDoesNotBringOldWorkbenchesBack` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::lista_vazia_e_um_estado_e_nao_traz_as_antigas_de_volta` (manual) |
| `WorkbenchStoreTests.testNewFileWinsOverLegacy` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::o_arquivo_novo_vence_o_antigo` (manual) |
| `WorkbenchStoreTests.testBrokenNewFileDoesNotFallBackToLegacy` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::arquivo_novo_quebrado_nao_cai_no_antigo` (manual) |
| `WorkbenchStoreTests.testNothingOnDiskStartsEmpty` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::sem_nada_em_disco_comeca_vazio` (manual) |

### WorkbenchTabOrderTests.swift — 4/4

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchTabOrderTests.testFileWithoutTheKeyStillLoads` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::arquivo_sem_a_chave_carrega` (manual) |
| `WorkbenchTabOrderTests.testTabOrderSurvivesARoundTrip` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::a_ordem_da_aba_vai_e_volta` (manual) |
| `WorkbenchTabOrderTests.testClosedWorkbenchHasNoOrder` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::bancada_fechada_nao_tem_ordem` (manual) |
| `WorkbenchTabOrderTests.testRestoreOrderFollowsTheSavedPositions` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::reabrir_segue_as_posicoes_gravadas` (manual) |

### WorkbenchTabTests.swift — 9/9

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchTabTests.testTabsFollowTheOrderYouOpenedThem` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::abas_seguem_a_ordem_em_que_voce_abriu` (manual) |
| `WorkbenchTabTests.testClosedWorkbenchesAreNotTabs` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::bancada_fechada_nao_e_aba` (manual) |
| `WorkbenchTabTests.testTabOfARemovedWorkbenchDisappears` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::aba_de_bancada_removida_some` (manual) |
| `WorkbenchTabTests.testAllThreeBadgesShowTogetherInAFixedOrder` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::os_tres_avisos_juntos_em_ordem_fixa`, `ui/test/features/tabs/workbench_tabs_bar_test.dart::os avisos saem na ordem fixa: trabalhando, atenção, pronto` (manual) |
| `WorkbenchTabTests.testBackgroundShowsTheHourglassNotTheSpinner` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::fundo_mostra_a_ampulheta_e_nao_o_spinner` (manual) |
| `WorkbenchTabTests.testActivityIsMatchedByWorkbenchName` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::atividade_casa_pelo_nome_da_bancada` (manual) |
| `WorkbenchTabTests.testQuietWorkbenchHasNoBadge` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::bancada_quieta_nao_tem_selo` (manual) |
| `WorkbenchTabTests.testWorkingAndDoneAreDifferentBadges` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::trabalhando_e_terminou_sao_selos_diferentes` (manual) |
| `WorkbenchTabTests.testClosingATabPicksTheNeighbour` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::fechar_uma_aba_escolhe_a_vizinha` (manual) |

### WorkbenchTabsBarTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkbenchTabsBarTests.testEveryTabGetsAVisiblePill` | PORTADO | `ui/test/features/tabs/workbench_tabs_bar_test.dart::toda aba ganha uma pastilha visível, dentro da faixa` (geometria de view: a medida fica na UI) |
| `WorkbenchTabsBarTests.testTabsAreLaidOutSideBySide` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::deslocamentos_empilham_com_o_vao`, `ui/test/features/tabs/workbench_tabs_bar_test.dart::as pastilhas ficam lado a lado, sem empilhar no mesmo x` (a conta dos x é do core (tab_offsets); a medida na tela é da UI) |
| `WorkbenchTabsBarTests.testEmptyBarHidesItself` | PORTADO | `ui/test/features/tabs/tabs_page_test.dart::com menos de duas abas a faixa some; com duas, aparece` (o Dart é mais estrito: some com menos de duas abas (o Swift só com zero); lista vazia some e duas aparecem nos dois) |
| `WorkbenchTabsBarTests.testMovingATabRearrangesThePills` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::moved_tira_e_poe_de_volta`, `ui/test/features/tabs/workbench_tabs_bar_test.dart::arrastar além do limiar reordena e avisa a ordem final`, `ui/test/features/tabs/tab_drag_layout_test.dart::moved tira de um lugar e põe no outro` (manual) |
| `WorkbenchTabsBarTests.testMovingToAnImpossiblePlaceDoesNothing` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::moved_tira_e_poe_de_volta`, `rust/crates/egeon-core/src/features/workbench/tests_tabs.rs::indice_desconhecido_e_inerte`, `ui/test/features/tabs/tab_drag_layout_test.dart::índice desconhecido é inerte: bancada que saiu no meio do arrasto` (o Swift move por id (nil para id desconhecido); o porte move por índice (moved devolve a lista igual para índice fora da faixa)) |
| `WorkbenchTabsBarTests.testReorderingFromTheAppKeepsTheSameViews` | PORTADO | `ui/test/features/tabs/workbench_tabs_bar_test.dart::a ordem que vem do core reordena sem recriar as pastilhas` (identidade de widget: só faz sentido na UI) |
| `WorkbenchTabsBarTests.testStateChangeKeepsTheSameViews` | PORTADO | `ui/test/features/tabs/workbench_tabs_bar_test.dart::trocar só o estado não remonta as pastilhas` (identidade de widget: só faz sentido na UI) |

### WorkspaceMoveTests.swift — 6/6

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkspaceMoveTests.testWorkspaceChangesPlace` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::workspace_muda_de_lugar` (manual) |
| `WorkspaceMoveTests.testProjectMovesInsideAndBetweenWorkspaces` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::projeto_anda_dentro_e_entre_workspaces` (manual) |
| `WorkspaceMoveTests.testWorkbenchReordersInsideItsProject` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::bancada_reordena_dentro_do_projeto` (manual) |
| `WorkspaceMoveTests.testWorkbenchChangesProjectAndLandsAmongItsNewSiblings` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::bancada_muda_de_projeto_e_cai_entre_as_novas_vizinhas` (manual) |
| `WorkspaceMoveTests.testProjectGoesInAndOutOfTheDrawer` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::projeto_entra_e_sai_da_gaveta` (manual) |
| `WorkspaceMoveTests.testMapPointsEveryMovedIndexToItsNewHome` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::mapa_leva_cada_indice_movido_para_a_casa_nova` (manual) |

### WorkspaceTests.swift — 12/12

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorkspaceTests.testProjectOwnsPathIgnoringTildeAndTrailingSlash` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::projeto_e_dono_do_caminho_ignorando_til_e_barra_final` (manual) |
| `WorkspaceTests.testProjectForFolderNamesAfterFolderAndAbbreviates` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::projeto_para_pasta_leva_o_nome_da_pasta_e_abrevia` (manual) |
| `WorkspaceTests.testDecodeFillsIDAndProjectNameDefaults` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::leitura_preenche_id_e_nome_do_projeto` (manual) |
| `WorkspaceTests.testWorkbenchProjectRoundTrips` | PORTADO | `rust/crates/egeon-core/src/features/workbench/tests.rs::todo_campo_da_bancada_vai_e_volta` (o campo `project` da bancada vai e volta junto com os demais) |
| `WorkspaceTests.testReconcileCreatesDefaultWorkspaceAndOneProjectPerRepo` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::concilia_cria_o_workspace_padrao_e_um_projeto_por_repo` (manual) |
| `WorkspaceTests.testReconcileBindsWorktreeToMainRepoProject` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::concilia_liga_a_worktree_ao_projeto_do_repo_principal` (manual) |
| `WorkspaceTests.testReconcileKeepsExistingAssignmentAndReportsNoChange` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::concilia_guarda_a_atribuicao_existente_e_diz_que_nada_mudou` (manual) |
| `WorkspaceTests.testReconcileReassignsUnknownProjectID` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::concilia_realoca_id_de_projeto_desconhecido` (manual) |
| `WorkspaceTests.testReconcileCreatesMissingProjectInFirstWorkspace` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests.rs::concilia_cria_o_projeto_que_falta_no_primeiro_workspace` (manual) |
| `WorkspaceTests.testRowsFollowWorkspaceProjectOrderThenOrphans` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::linhas_seguem_workspace_projeto_e_depois_as_orfas` (manual) |
| `WorkspaceTests.testCollapsedWorkspaceHidesProjectsAndCollapsedProjectHidesWorkbenches` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::workspace_recolhido_esconde_projetos_e_projeto_recolhido_esconde_bancadas`, `ui/test/features/sidebar/sidebar_page_test.dart::workspace recolhido esconde os projetos` (a conta das linhas é do core; o Dart só confere que a barra esconde os projetos do workspace recolhido) |
| `WorkspaceTests.testMembershipAndAncestors` | PORTADO | `rust/crates/egeon-core/src/features/workspace/tests_tree.rs::pertencimento_e_ancestrais` (manual) |

### WorktreeRemoveTests.swift — 7/7

| Teste | Situação | Onde / motivo |
|---|---|---|
| `WorktreeRemoveTests.testRemovesTheFolderAndTheRegistration` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::remove_a_pasta_e_o_registro` (manual) |
| `WorktreeRemoveTests.testRegistrationLookupSurvivesSymlinkedPaths` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::a_busca_do_registro_sobrevive_a_caminho_com_symlink` (o teste Rust só roda em macOS (/var -> /private/var); em outros sistemas retorna sem verificar) |
| `WorktreeRemoveTests.testFinishesTheRemovalGitGaveUpOn` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::termina_a_remocao_em_que_o_git_desistiu` (manual) |
| `WorktreeRemoveTests.testKeepsTheFolderWhileTheWorktreeIsStillRegistered` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::guarda_a_pasta_enquanto_a_worktree_esta_registrada` (manual) |
| `WorktreeRemoveTests.testRemovalFinishesEvenWithSomebodyWritingInTheFolder` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::a_remocao_termina_mesmo_com_alguem_escrevendo_na_pasta` (manual) |
| `WorktreeRemoveTests.testReportsLeftoversWhenNobodyCanDeleteTheFolder` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::avisa_das_sobras_quando_ninguem_consegue_apagar_a_pasta` (manual) |
| `WorktreeRemoveTests.testNothingToFinishWhenTheFolderIsAlreadyGone` | PORTADO | `rust/crates/egeon-core/src/features/worktree/tests.rs::nada_a_terminar_quando_a_pasta_ja_sumiu` (manual) |
