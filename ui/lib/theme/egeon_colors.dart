import 'package:material_ui/material_ui.dart';

/// Cores do tema escuro (o único), copiadas do `tokens.json` do design system;
/// mudou lá, o teste de paridade aponta. Acesse com `context.eg`.
@immutable
class EgeonColors extends ThemeExtension<EgeonColors> {
  const EgeonColors({
    required this.obsidian,
    required this.graphite,
    required this.carbon,
    required this.steel,
    required this.steelActive,
    required this.lineSubtle,
    required this.line,
    required this.lineStrong,
    required this.lineHover,
    required this.controlBorder,
    required this.controlBorderHover,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSoft,
    required this.onAccent,
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.onPrimary,
    required this.focusRing,
    required this.attention,
    required this.attentionSoft,
    required this.running,
    required this.runningSoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerHover,
    required this.dangerPressed,
    required this.onAttention,
    required this.onDanger,
    required this.waiting,
    required this.waitingSoft,
    required this.idRose,
    required this.idClay,
    required this.idSand,
    required this.idOlive,
    required this.idMoss,
    required this.idJade,
    required this.idTeal,
    required this.idSky,
    required this.idSlate,
    required this.idIris,
    required this.idOrchid,
    required this.idMauve,
    required this.onIdentity,
    required this.diffAddBg,
    required this.diffAddWord,
    required this.diffAddFg,
    required this.diffDelBg,
    required this.diffDelWord,
    required this.diffDelFg,
    required this.synText,
    required this.synComment,
    required this.synKeyword,
    required this.synString,
    required this.synNumber,
    required this.synFunction,
    required this.synType,
    required this.synConstant,
    required this.synTag,
    required this.synPunct,
    required this.termBg,
    required this.termFg,
    required this.termCursor,
    required this.termSelection,
    required this.termBlack,
    required this.termRed,
    required this.termGreen,
    required this.termYellow,
    required this.termBlue,
    required this.termMagenta,
    required this.termCyan,
    required this.termWhite,
    required this.termBrightBlack,
    required this.termBrightRed,
    required this.termBrightGreen,
    required this.termBrightYellow,
    required this.termBrightBlue,
    required this.termBrightMagenta,
    required this.termBrightCyan,
    required this.termBrightWhite,
    required this.scrim,
    required this.edge,
  });

  /// Obsidian — fundo do app: barra lateral, barra de título e abas, fundo do terminal. A camada mais funda.
  final Color obsidian;

  /// Graphite — superfície principal (~65% da tela): canvas, chat, painéis de conteúdo.
  final Color graphite;

  /// Carbon — superfície elevada (~20%): inputs, cards, menus, popovers, diálogos, toasts, botão secundário, bolha do usuário.
  final Color carbon;

  /// Steel — superfície de hover: itens de lista, abas, botões fantasma, linhas de tabela.
  final Color steel;

  /// Pressionado e selecionado sem acento; trilho do toggle e do slider.
  final Color steelActive;

  /// Fio interno mínimo: linhas de tabela, grade de pontos do canvas.
  final Color lineSubtle;

  /// Borda de superfícies elevadas (menus, popovers, diálogos, pastilhas, botão secundário).
  final Color line;

  /// Borda de controles (input, select, etiqueta de atributo). Abaixo de 3:1 de propósito: o campo também se identifica pelo fundo carbon e pelo rótulo.
  final Color lineStrong;

  /// Borda de input e select em hover.
  final Color lineHover;

  /// Borda de checkbox, radio e trilho do toggle em repouso. Borda do composer em foco.
  final Color controlBorder;

  /// Borda de checkbox e radio em hover (≥ 3:1 sobre carbon).
  final Color controlBorderHover;

  /// Texto principal sobre todas as superfícies (≥ 11.7:1).
  final Color textPrimary;

  /// Texto de apoio, rótulos, ícones padrão e metadados que precisam ser lidos (≥ 5:1 sobre todas as superfícies).
  final Color textSecondary;

  /// Texto de baixa prioridade: placeholders, hora, atalhos, fases zeradas. Valor da paleta original, abaixo de 4.5:1 (3.25:1 sobre graphite): nunca para informação que o usuário precisa ler para agir.
  final Color textMuted;

  /// Texto e ícones de controles desabilitados. Isento de contraste mínimo; nunca para informação.
  final Color textDisabled;

  /// Acento azul-gelo dessaturado: anel de foco, seleção, controles ligados (toggle, checkbox, slider), links. Como texto, ≥ 8:1 sobre todas as superfícies.
  final Color accent;

  /// Links e controles ligados em hover.
  final Color accentHover;

  /// Controles ligados pressionados.
  final Color accentPressed;

  /// Fundo de item selecionado (aba, item da barra lateral, ferramenta ativa). Sempre com texto text-primary ou accent.
  final Color accentSoft;

  /// Texto e ícone sobre fundo accent (toggle e checkbox ligados, ≥ 10:1).
  final Color onAccent;

  /// Fundo do botão primário: azul-aço sólido, a versão firme do acento. Um só por região. Texto on-primary a 5.4:1.
  final Color primary;

  /// Botão primário em hover (texto on-primary a 4.8:1).
  final Color primaryHover;

  /// Botão primário pressionado.
  final Color primaryPressed;

  /// Rótulo e ícone do botão primário (≥ 4.8:1 em todos os estados).
  final Color onPrimary;

  /// Anel de foco: 2px sólido colado ao controle, sem vão. ≥ 8:1 sobre todas as superfícies.
  final Color focusRing;

  /// Precisa de você: permissão, pergunta, decisão pendente. Laranja, como no app e no site. A ÚNICA cor que pode 'chamar' (halo pulsante). Dot, glifo, contador, badge — nunca bloco grande. ≥ 7.2:1 sobre todas as superfícies.
  final Color attention;

  /// Halo do pulso de atenção e fundo do badge e do banner de atenção.
  final Color attentionSoft;

  /// Trabalhando: spinner e aresta com tráfego. ≥ 6.9:1 sobre as surfaces.
  final Color running;

  /// Fundo suave de 'trabalhando', quando preciso.
  final Color runningSoft;

  /// Terminou: dot e check. Some quando você entra na bancada. ≥ 8.7:1 sobre as surfaces.
  final Color success;

  /// Fundo suave de 'terminou', quando preciso.
  final Color successSoft;

  /// Falhou e ações destrutivas (texto do botão perigo, campo com erro, octógono do cronômetro). ≥ 4.6:1 sobre graphite e carbon.
  final Color danger;

  /// Hover do botão perigo e fundo do badge e do banner de erro.
  final Color dangerSoft;

  /// Botão de perigo sólido em hover.
  final Color dangerHover;

  /// Botão de perigo sólido pressionado.
  final Color dangerPressed;

  /// Número sobre o contador de atenção (fundo attention).
  final Color onAttention;

  /// Texto sobre fundo danger (botão perigo pressionado).
  final Color onDanger;

  /// Em segundo plano / aguardando vizinho: ampulheta. ≥ 6.7:1 sobre as surfaces.
  final Color waiting;

  /// Fundo do contador de segundo plano nas abas.
  final Color waitingSoft;

  /// Identidade #1 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idRose;

  /// Identidade #2 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idClay;

  /// Identidade #3 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idSand;

  /// Identidade #4 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idOlive;

  /// Identidade #5 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idMoss;

  /// Identidade #6 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idJade;

  /// Identidade #7 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idTeal;

  /// Identidade #8 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idSky;

  /// Identidade #9 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idSlate;

  /// Identidade #10 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idIris;

  /// Identidade #11 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idOrchid;

  /// Identidade #12 de agente/bancada. A identidade é o NOME escrito nesta cor (AgentName); para bancadas, também o traço de 2px da aba ativa. Nunca em dot redondo, reservado a estado. Como texto, ≥ 7:1 sobre qualquer surface.
  final Color idMauve;

  /// Texto sobre uma cor de identidade, se algum dia ela for fundo (≥ 7.5:1).
  final Color onIdentity;

  /// Fundo de linha adicionada no diff.
  final Color diffAddBg;

  /// Realce de palavra adicionada dentro de uma linha (sobre diff-add-bg).
  final Color diffAddWord;

  /// Sinal '+', número de linha e contagem '+12' de adições.
  final Color diffAddFg;

  /// Fundo de linha removida no diff.
  final Color diffDelBg;

  /// Realce de palavra removida dentro de uma linha (sobre diff-del-bg).
  final Color diffDelWord;

  /// Sinal '−', número de linha e contagem '−4' de remoções.
  final Color diffDelFg;

  /// Texto padrão de código e identificadores.
  final Color synText;

  /// Comentários (≥ 4.5:1 sobre surface-2).
  final Color synComment;

  /// Palavras-chave: if, return, class, import.
  final Color synKeyword;

  /// Strings e templates.
  final Color synString;

  /// Números, booleanos, null.
  final Color synNumber;

  /// Nomes de função e método.
  final Color synFunction;

  /// Tipos, classes, interfaces.
  final Color synType;

  /// Constantes, enums, propriedades de objeto.
  final Color synConstant;

  /// Tags HTML/JSX e chaves de JSON/YAML.
  final Color synTag;

  /// Pontuação e operadores.
  final Color synPunct;

  /// Fundo do terminal = obsidian, para o terminal 'afundar' na superfície graphite.
  final Color termBg;

  /// Texto padrão do terminal.
  final Color termFg;

  /// Cursor de bloco do terminal.
  final Color termCursor;

  /// Seleção de texto no terminal e no editor.
  final Color termSelection;

  /// ANSI 0.
  final Color termBlack;

  /// ANSI 1.
  final Color termRed;

  /// ANSI 2.
  final Color termGreen;

  /// ANSI 3.
  final Color termYellow;

  /// ANSI 4.
  final Color termBlue;

  /// ANSI 5.
  final Color termMagenta;

  /// ANSI 6.
  final Color termCyan;

  /// ANSI 7.
  final Color termWhite;

  /// ANSI 8.
  final Color termBrightBlack;

  /// ANSI 9.
  final Color termBrightRed;

  /// ANSI 10.
  final Color termBrightGreen;

  /// ANSI 11.
  final Color termBrightYellow;

  /// ANSI 12.
  final Color termBrightBlue;

  /// ANSI 13.
  final Color termBrightMagenta;

  /// ANSI 14.
  final Color termBrightCyan;

  /// ANSI 15.
  final Color termBrightWhite;

  /// Véu atrás de diálogos modais.
  final Color scrim;

  /// Aresta do canvas em repouso (1.5px). Selecionada vira accent; com tráfego, running; limite atingido, line.
  final Color edge;

  /// Transparente: o "sem cor" que as bordas e fundos de estado usam.
  static const clear = Color(0x00000000);

  /// Branco translúcido (overlay-N do DS) por cima de qualquer fundo;
  /// o número é a opacidade em %.
  static const overlay2 = Color(0x06FFFFFF);
  static const overlay4 = Color(0x0AFFFFFF);
  static const overlay6 = Color(0x0FFFFFFF);
  static const overlay8 = Color(0x14FFFFFF);
  static const overlay10 = Color(0x1AFFFFFF);
  static const overlay12 = Color(0x1FFFFFFF);

  static const dark = EgeonColors(
    obsidian: Color(0xFF0D0F11),
    graphite: Color(0xFF15181B),
    carbon: Color(0xFF1C2024),
    steel: Color(0xFF252A30),
    steelActive: Color(0xFF2D333A),
    lineSubtle: Color(0xFF1F2328),
    line: Color(0xFF2A3036),
    lineStrong: Color(0xFF3A4148),
    lineHover: Color(0xFF4A525B),
    controlBorder: Color(0xFF555D66),
    controlBorderHover: Color(0xFF6B737C),
    textPrimary: Color(0xFFE8E8E6),
    textSecondary: Color(0xFF92999F),
    textMuted: Color(0xFF626A72),
    textDisabled: Color(0xFF4A5058),
    accent: Color(0xFFA4C2DC),
    accentHover: Color(0xFFB9D5ED),
    accentPressed: Color(0xFF8FADC7),
    accentSoft: Color(0x1AA4C2DC),
    onAccent: Color(0xFF0D0F11),
    primary: Color(0xFF3F6D98),
    primaryHover: Color(0xFF4776A1),
    primaryPressed: Color(0xFF396791),
    onPrimary: Color(0xFFFFFFFF),
    focusRing: Color(0xFFA4C2DC),
    attention: Color(0xFFFF9B45),
    attentionSoft: Color(0x24FF9B45),
    running: Color(0xFF64A9F3),
    runningSoft: Color(0x1F64A9F3),
    success: Color(0xFF5FCE8C),
    successSoft: Color(0x1F5FCE8C),
    danger: Color(0xFFED6863),
    dangerSoft: Color(0x1FED6863),
    dangerHover: Color(0xFFF37571),
    dangerPressed: Color(0xFFD94D4A),
    onAttention: Color(0xFF1A0F05),
    onDanger: Color(0xFF0B0D10),
    waiting: Color(0xFFA89AD5),
    waitingSoft: Color(0x1FA89AD5),
    idRose: Color(0xFFD6989C),
    idClay: Color(0xFFD49C84),
    idSand: Color(0xFFC7A475),
    idOlive: Color(0xFFB1AE76),
    idMoss: Color(0xFF97B686),
    idJade: Color(0xFF7DBA9F),
    idTeal: Color(0xFF6FBAB9),
    idSky: Color(0xFF75B5CF),
    idSlate: Color(0xFF8BAEDA),
    idIris: Color(0xFFA5A5D9),
    idOrchid: Color(0xFFBD9DCC),
    idMauve: Color(0xFFCE98B6),
    onIdentity: Color(0xFF0B0D10),
    diffAddBg: Color(0xFF0D1E13),
    diffAddWord: Color(0xFF123923),
    diffAddFg: Color(0xFF81D39F),
    diffDelBg: Color(0xFF261413),
    diffDelWord: Color(0xFF4A2322),
    diffDelFg: Color(0xFFEF9491),
    synText: Color(0xFFCDD1D6),
    synComment: Color(0xFF7E848A),
    synKeyword: Color(0xFFBDA4DD),
    synString: Color(0xFF9CC992),
    synNumber: Color(0xFFE7B780),
    synFunction: Color(0xFF8FC1EB),
    synType: Color(0xFF85D1D0),
    synConstant: Color(0xFFEAA48C),
    synTag: Color(0xFFE1979C),
    synPunct: Color(0xFF92999F),
    termBg: Color(0xFF0D0F11),
    termFg: Color(0xFFCED1D5),
    termCursor: Color(0xFFE8E8E6),
    termSelection: Color(0x33A4C2DC),
    termBlack: Color(0xFF24272A),
    termRed: Color(0xFFE66E68),
    termGreen: Color(0xFF68CA80),
    termYellow: Color(0xFFEBC166),
    termBlue: Color(0xFF67AAED),
    termMagenta: Color(0xFFC68BD3),
    termCyan: Color(0xFF5DCBD1),
    termWhite: Color(0xFFCED1D5),
    termBrightBlack: Color(0xFF6E7277),
    termBrightRed: Color(0xFFFF8880),
    termBrightGreen: Color(0xFF83E499),
    termBrightYellow: Color(0xFFFDDB7C),
    termBrightBlue: Color(0xFF86C3FF),
    termBrightMagenta: Color(0xFFDDA7EA),
    termBrightCyan: Color(0xFF85E3E8),
    termBrightWhite: Color(0xFFF4F5F7),
    scrim: Color(0xA3000000),
    edge: Color(0xFF3A4148),
  );

  /// As 12 cores de identidade, na ordem de atribuição automática.
  List<Color> get identities => [
    idSky,
    idIris,
    idOrchid,
    idTeal,
    idSlate,
    idSand,
    idMauve,
    idJade,
    idOlive,
    idRose,
    idClay,
    idMoss,
  ];

  @override
  EgeonColors copyWith() => this;

  @override
  EgeonColors lerp(ThemeExtension<EgeonColors>? other, double t) {
    if (other is! EgeonColors) return this;
    return EgeonColors(
      obsidian: Color.lerp(obsidian, other.obsidian, t)!,
      graphite: Color.lerp(graphite, other.graphite, t)!,
      carbon: Color.lerp(carbon, other.carbon, t)!,
      steel: Color.lerp(steel, other.steel, t)!,
      steelActive: Color.lerp(steelActive, other.steelActive, t)!,
      lineSubtle: Color.lerp(lineSubtle, other.lineSubtle, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      lineHover: Color.lerp(lineHover, other.lineHover, t)!,
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
      controlBorderHover: Color.lerp(
        controlBorderHover,
        other.controlBorderHover,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      attentionSoft: Color.lerp(attentionSoft, other.attentionSoft, t)!,
      running: Color.lerp(running, other.running, t)!,
      runningSoft: Color.lerp(runningSoft, other.runningSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      dangerHover: Color.lerp(dangerHover, other.dangerHover, t)!,
      dangerPressed: Color.lerp(dangerPressed, other.dangerPressed, t)!,
      onAttention: Color.lerp(onAttention, other.onAttention, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      waiting: Color.lerp(waiting, other.waiting, t)!,
      waitingSoft: Color.lerp(waitingSoft, other.waitingSoft, t)!,
      idRose: Color.lerp(idRose, other.idRose, t)!,
      idClay: Color.lerp(idClay, other.idClay, t)!,
      idSand: Color.lerp(idSand, other.idSand, t)!,
      idOlive: Color.lerp(idOlive, other.idOlive, t)!,
      idMoss: Color.lerp(idMoss, other.idMoss, t)!,
      idJade: Color.lerp(idJade, other.idJade, t)!,
      idTeal: Color.lerp(idTeal, other.idTeal, t)!,
      idSky: Color.lerp(idSky, other.idSky, t)!,
      idSlate: Color.lerp(idSlate, other.idSlate, t)!,
      idIris: Color.lerp(idIris, other.idIris, t)!,
      idOrchid: Color.lerp(idOrchid, other.idOrchid, t)!,
      idMauve: Color.lerp(idMauve, other.idMauve, t)!,
      onIdentity: Color.lerp(onIdentity, other.onIdentity, t)!,
      diffAddBg: Color.lerp(diffAddBg, other.diffAddBg, t)!,
      diffAddWord: Color.lerp(diffAddWord, other.diffAddWord, t)!,
      diffAddFg: Color.lerp(diffAddFg, other.diffAddFg, t)!,
      diffDelBg: Color.lerp(diffDelBg, other.diffDelBg, t)!,
      diffDelWord: Color.lerp(diffDelWord, other.diffDelWord, t)!,
      diffDelFg: Color.lerp(diffDelFg, other.diffDelFg, t)!,
      synText: Color.lerp(synText, other.synText, t)!,
      synComment: Color.lerp(synComment, other.synComment, t)!,
      synKeyword: Color.lerp(synKeyword, other.synKeyword, t)!,
      synString: Color.lerp(synString, other.synString, t)!,
      synNumber: Color.lerp(synNumber, other.synNumber, t)!,
      synFunction: Color.lerp(synFunction, other.synFunction, t)!,
      synType: Color.lerp(synType, other.synType, t)!,
      synConstant: Color.lerp(synConstant, other.synConstant, t)!,
      synTag: Color.lerp(synTag, other.synTag, t)!,
      synPunct: Color.lerp(synPunct, other.synPunct, t)!,
      termBg: Color.lerp(termBg, other.termBg, t)!,
      termFg: Color.lerp(termFg, other.termFg, t)!,
      termCursor: Color.lerp(termCursor, other.termCursor, t)!,
      termSelection: Color.lerp(termSelection, other.termSelection, t)!,
      termBlack: Color.lerp(termBlack, other.termBlack, t)!,
      termRed: Color.lerp(termRed, other.termRed, t)!,
      termGreen: Color.lerp(termGreen, other.termGreen, t)!,
      termYellow: Color.lerp(termYellow, other.termYellow, t)!,
      termBlue: Color.lerp(termBlue, other.termBlue, t)!,
      termMagenta: Color.lerp(termMagenta, other.termMagenta, t)!,
      termCyan: Color.lerp(termCyan, other.termCyan, t)!,
      termWhite: Color.lerp(termWhite, other.termWhite, t)!,
      termBrightBlack: Color.lerp(termBrightBlack, other.termBrightBlack, t)!,
      termBrightRed: Color.lerp(termBrightRed, other.termBrightRed, t)!,
      termBrightGreen: Color.lerp(termBrightGreen, other.termBrightGreen, t)!,
      termBrightYellow: Color.lerp(
        termBrightYellow,
        other.termBrightYellow,
        t,
      )!,
      termBrightBlue: Color.lerp(termBrightBlue, other.termBrightBlue, t)!,
      termBrightMagenta: Color.lerp(
        termBrightMagenta,
        other.termBrightMagenta,
        t,
      )!,
      termBrightCyan: Color.lerp(termBrightCyan, other.termBrightCyan, t)!,
      termBrightWhite: Color.lerp(termBrightWhite, other.termBrightWhite, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
    );
  }
}

extension EgeonContext on BuildContext {
  EgeonColors get eg => Theme.of(this).extension<EgeonColors>()!;
}
