import 'dart:ui';

import '../../../theme/egeon_colors.dart';

/// A identidade de um agente ou bancada: uma das 12 cores do DS, na ordem da
/// atribuição automática (`rose`, `clay` e `moss`, as mais próximas de erro,
/// atenção e terminou, ficam para escolha manual).
enum Identity {
  sky,
  iris,
  orchid,
  teal,
  slate,
  sand,
  mauve,
  jade,
  olive,
  rose,
  clay,
  moss;

  /// A identidade que a atribuição automática dá ao [index]-ésimo agente.
  factory Identity.auto(int index) => values[index % values.length];

  /// Pelo nome do DS (o que o core grava); `steel` é a `slate`, como no DS.
  /// Nome desconhecido cai em `slate`.
  factory Identity.fromName(String name) {
    if (name == 'steel') return slate;
    return values.firstWhere((i) => i.name == name, orElse: () => slate);
  }

  Color color(EgeonColors colors) => switch (this) {
    sky => colors.idSky,
    iris => colors.idIris,
    orchid => colors.idOrchid,
    teal => colors.idTeal,
    slate => colors.idSlate,
    sand => colors.idSand,
    mauve => colors.idMauve,
    jade => colors.idJade,
    olive => colors.idOlive,
    rose => colors.idRose,
    clay => colors.idClay,
    moss => colors.idMoss,
  };
}

/// A cor da identidade; sem ela, `slate`.
Color identityColor(EgeonColors colors, Identity? identity) =>
    (identity ?? Identity.slate).color(colors);

/// Quem fala ou é citado: nome, identidade e endereço (`bancada/id`).
class Person {
  const Person(this.name, {this.identity, this.address});

  final String name;
  final Identity? identity;
  final String? address;
}
