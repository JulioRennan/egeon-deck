import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Uma cor de bancada: o nome é o que o core grava (formato de arquivo), o
/// rótulo é o do menu.
class WorkbenchSwatch {
  const WorkbenchSwatch(this.name, this.label, this.color);

  final String name;
  final String label;
  final Color color;
}

/// As 24 cores que o core oferece para uma bancada. Escolher qual cada uma
/// ganha é do core; aqui só se desenha.
abstract final class WorkbenchPalette {
  static const all = <WorkbenchSwatch>[
    WorkbenchSwatch('red', 'Vermelho', Color(0xFFEF5350)),
    WorkbenchSwatch('coral', 'Coral', Color(0xFFFF7043)),
    WorkbenchSwatch('peach', 'Pêssego', Color(0xFFFFAB91)),
    WorkbenchSwatch('orange', 'Laranja', Color(0xFFFFA726)),
    WorkbenchSwatch('amber', 'Âmbar', Color(0xFFFFCA28)),
    WorkbenchSwatch('sand', 'Areia', Color.fromRGBO(237, 204, 115, 1)),
    WorkbenchSwatch('yellow', 'Amarelo', Color(0xFFFFEE58)),
    WorkbenchSwatch('lime', 'Lima', Color(0xFFD4E157)),
    WorkbenchSwatch('lightGreen', 'Verde-claro', Color(0xFF9CCC65)),
    WorkbenchSwatch('green', 'Verde', Color(0xFF66BB6A)),
    WorkbenchSwatch('teal', 'Verde-azulado', Color(0xFF26A69A)),
    WorkbenchSwatch('cyan', 'Ciano', Color.fromRGBO(64, 209, 242, 1)),
    WorkbenchSwatch('sky', 'Celeste', Color(0xFF29B6F6)),
    WorkbenchSwatch('blue', 'Azul', Color.fromRGBO(74, 143, 255, 1)),
    WorkbenchSwatch('indigo', 'Anil', Color.fromRGBO(102, 107, 242, 1)),
    WorkbenchSwatch('deepPurple', 'Roxo', Color(0xFF7E57C2)),
    WorkbenchSwatch('violet', 'Violeta', Color.fromRGBO(158, 107, 255, 1)),
    WorkbenchSwatch('purple', 'Púrpura', Color(0xFFAB47BC)),
    WorkbenchSwatch('magenta', 'Magenta', Color.fromRGBO(224, 77, 230, 1)),
    WorkbenchSwatch('pink', 'Rosa', Color.fromRGBO(255, 115, 179, 1)),
    WorkbenchSwatch('raspberry', 'Framboesa', Color(0xFFEC407A)),
    WorkbenchSwatch('brown', 'Marrom', Color(0xFF8D6E63)),
    WorkbenchSwatch('slate', 'Ardósia', Color(0xFF78909C)),
    WorkbenchSwatch('grey', 'Cinza', Color(0xFFBDBDBD)),
  ];

  /// A cor pelo nome gravado; sem nome (ou nome que saiu da paleta) vale o
  /// destaque do app.
  static Color of(String? name) {
    for (final swatch in all) {
      if (swatch.name == name) return swatch.color;
    }
    return AppColors.accent;
  }
}
