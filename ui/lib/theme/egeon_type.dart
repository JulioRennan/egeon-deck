import 'package:flutter/painting.dart';

/// Estilos de texto. Fontes no pubspec: 'Noto Sans' e 'JetBrains Mono' (fonts/*.ttf, normal e itálico).
abstract final class EgeonType {
  static const sans = 'Noto Sans';
  static const mono = 'JetBrains Mono';

  /// Reserva de tokens.json (type.families), para glifos que a fonte não tem.
  static const sansFallback = ['-apple-system', 'SF Pro Text', 'system-ui'];
  static const monoFallback = ['SF Mono', 'Menlo'];
  static const _tab = [FontFeature.tabularFigures()];

  /// Raro: estado vazio de tela cheia e onboarding. No máximo um por tela.
  static const display = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 28.0,
    height: 1.2143,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.56,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Título de diálogo e de painel principal.
  static const title = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 20.0,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Cabeçalho de seção, nome do agente em destaque, título de grupo.
  static const heading = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 15.0,
    height: 1.4667,
    fontWeight: FontWeight.w600,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Texto corrido: mensagens do chat, descrições, conteúdo de diálogos.
  static const body = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 14.0,
    height: 1.5714,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Rótulo de botão, aba, item da barra lateral, opção de menu.
  static const label = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 14.0,
    height: 1.4286,
    fontWeight: FontWeight.w500,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Texto secundário, ajuda de campo, tooltip, linhas de tabela.
  static const small = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 13.0,
    height: 1.3846,
    fontWeight: FontWeight.w400,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Badges, contadores, cabeçalho de coluna, rótulo de grupo na barra lateral.
  static const caption = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 12.0,
    height: 1.3333,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.12,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Terminal dos nós. O protagonista: nunca abaixo de 13px.
  static const terminal = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 14.0,
    height: 1.4286,
    fontWeight: FontWeight.w400,
    fontFeatures: _tab,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Blocos de código, diffs e código inline no chat.
  static const code = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 13.0,
    height: 1.5385,
    fontWeight: FontWeight.w400,
    fontFeatures: _tab,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Números tabulares: cronômetro, custo, contexto, endereço do nó, PID.
  static const monoMeta = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 12.0,
    height: 1.3333,
    fontWeight: FontWeight(450),
    fontFeatures: _tab,
    leadingDistribution: TextLeadingDistribution.even,
  );
}
