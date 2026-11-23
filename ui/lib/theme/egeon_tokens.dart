import 'package:flutter/painting.dart';
import 'package:flutter/animation.dart' show Curve, Cubic;

/// Espaçamento, grade de 4.
abstract final class EgeonSpace {
  /// Ajuste ótico: dot ao lado de texto.
  static const double s05 = 2.0;

  /// Entre ícone e rótulo pequeno.
  static const double s1 = 4.0;

  /// Entre ícone e rótulo de botão; gap entre botões de uma barra.
  static const double s2 = 8.0;

  /// Respiro horizontal de campos, itens de lista e botões sm; gap entre campos relacionados.
  static const double s3 = 12.0;

  /// Respiro horizontal de botões md; respiro de painéis e da barra lateral.
  static const double s4 = 16.0;

  /// Gap entre mensagens do chat; respiro de popovers; respiro de botões lg.
  static const double s5 = 20.0;

  /// Padding de diálogos; espaço entre grupos da barra lateral.
  static const double s6 = 24.0;

  /// Separação entre seções de um painel.
  static const double s8 = 32.0;

  /// Margem de conteúdo em telas de configuração.
  static const double s10 = 40.0;

  /// Respiro de estados vazios.
  static const double s12 = 48.0;

  /// Distância mínima entre nós no canvas.
  static const double s16 = 64.0;
}

/// Raios.
abstract final class EgeonRadius {
  /// Checkbox, atalho de teclado (kbd), realce de palavra no diff.
  static const double xs = 4.0;

  /// Badges, abas, itens de lista e de menu, itens do controle segmentado.
  static const double sm = 6.0;

  /// Botões, inputs, select, textarea, controle segmentado, pastilhas.
  static const double md = 8.0;

  /// Menus, popovers, toasts, blocos de código, diff, composer, painéis.
  static const double lg = 12.0;

  /// Diálogos e a barra de ferramentas flutuante. O maior raio do sistema.
  static const double xl = 14.0;

  /// Só formas circulares: dot de estado, trilho do toggle, spinner, contador. Nunca em botões.
  static const double full = 999.0;
}

/// Tamanhos de controles e estrutura.
abstract final class EgeonSize {
  /// Controles compactos: ações em linha, toasts, barra do composer. Padding horizontal 12px.
  static const double controlSm = 30.0;

  /// Altura padrão de botão, input, select. Padding horizontal 16px.
  static const double controlMd = 36.0;

  /// Botões de diálogo e ações principais de tela. Padding horizontal 20px.
  static const double controlLg = 42.0;

  /// Linhas de lista: item da barra lateral, opção de menu, passo do chat.
  static const double row = 32.0;

  /// Altura da barra de abas de bancada (abas de 32px).
  static const double tab = 40.0;

  /// Barra de título (inclui o espaço dos semáforos do macOS).
  static const double titlebar = 44.0;

  /// Ícone padrão (traço 1.5px).
  static const double icon = 16.0;

  /// Ícone em pastilhas e controles sm.
  static const double iconSm = 14.0;

  /// Dot de estado.
  static const double dot = 8.0;

  /// Largura padrão da barra lateral (redimensionável 220–360px).
  static const double sidebar = 264.0;
}

/// Espessuras de borda.
abstract final class EgeonBorder {
  /// Todas as bordas de superfície e controle.
  static const double hairline = 1.0;

  /// Arestas do canvas.
  static const double state = 1.5;

  /// Espessura do anel de foco (focus-ring), sobre a borda do controle.
  static const double focus = 2.0;
}

/// Opacidades.
abstract final class EgeonOpacity {
  /// Ícones e ilustrações de controles desabilitados (texto usa text-disabled).
  static const double disabled = 0.4;

  /// Ações secundárias (✕ da aba, copiar, ações em linha) ficam em 0 e vão a 1 no hover/foco do pai.
  static const double hoverReveal = 0.0;

  /// Nós e arestas fora do foco quando um nó está isolado.
  static const double muted = 0.64;
}

/// Durações e curvas. A única animação que chama é o pulso de atenção.
abstract final class EgeonMotion {
  /// Hover e pressionado.
  static const Duration instant = Duration(milliseconds: 80);

  /// Abrir menu, popover, tooltip; trocar aba; toggle.
  static const Duration fast = Duration(milliseconds: 140);

  /// Diálogo, toast, recolher passo do chat, trocar Canvas | Chat.
  static const Duration base = Duration(milliseconds: 200);

  /// Ciclo do halo de atenção — a única animação que chama.
  static const Duration attention = Duration(milliseconds: 1600);

  /// Uma volta do spinner de 'trabalhando'.
  static const Duration spin = Duration(milliseconds: 900);

  /// Padrão para entradas e mudanças de estado.
  static const Curve easeStandard = Cubic(0.2, 0, 0, 1);

  /// Saídas (fechar menu, toast saindo).
  static const Curve easeExit = Cubic(0.4, 0, 1, 1);

  /// Halo de atenção.
  static const Curve easePulse = Cubic(0.4, 0, 0.6, 1);
}

/// Sombras discretas: profundidade, não decoração.
abstract final class EgeonShadow {
  static const raised = [
    BoxShadow(color: Color(0x47000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const float = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0xFF2A3036), spreadRadius: 1),
  ];
  static const modal = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 64, offset: Offset(0, 24)),
    BoxShadow(color: Color(0xFF2A3036), spreadRadius: 1),
  ];
  static const drag = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// O inset de 1px do CSS vira `EgeonGlass.highlight`, desenhado como borda de topo.
  static const glass = [
    BoxShadow(color: Color(0x52000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}
