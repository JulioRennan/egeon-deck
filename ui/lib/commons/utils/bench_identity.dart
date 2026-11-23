import '../widgets/eg/identity.dart';

/// A cor da bancada, entre os dois mundos: o core grava um de 24 nomes antigos
/// (`WorkbenchColor`), o design system tem 12 identidades. Provisório, até o
/// Julio decidir o que fazer com a paleta: cada nome antigo lê como a
/// identidade de matiz mais próximo, e cada identidade grava um nome antigo
/// fixo que, lido de volta, dá a mesma identidade. Nada muda no core nem em
/// `~/.egeon`.
abstract final class BenchIdentity {
  /// Cada nome antigo na identidade de matiz mais próximo. Os sem cor própria
  /// (`brown`, `slate`, `grey`) vão para a vizinha neutra; `green` fica no
  /// `jade` (empata em matiz com `moss`) para toda identidade ter um nome.
  static const _fromName = <String, Identity>{
    'red': Identity.rose,
    'coral': Identity.clay,
    'peach': Identity.clay,
    'orange': Identity.sand,
    'amber': Identity.sand,
    'sand': Identity.sand,
    'yellow': Identity.olive,
    'lime': Identity.olive,
    'lightGreen': Identity.moss,
    'green': Identity.jade,
    'teal': Identity.teal,
    'cyan': Identity.sky,
    'sky': Identity.sky,
    'blue': Identity.slate,
    'indigo': Identity.iris,
    'deepPurple': Identity.orchid,
    'violet': Identity.orchid,
    'purple': Identity.orchid,
    'magenta': Identity.orchid,
    'pink': Identity.mauve,
    'raspberry': Identity.mauve,
    'brown': Identity.clay,
    'slate': Identity.slate,
    'grey': Identity.slate,
  };

  /// O nome antigo que cada identidade grava.
  static const _toName = <Identity, String>{
    Identity.sky: 'sky',
    Identity.iris: 'indigo',
    Identity.orchid: 'purple',
    Identity.teal: 'teal',
    Identity.slate: 'blue',
    Identity.sand: 'sand',
    Identity.mauve: 'pink',
    Identity.jade: 'green',
    Identity.olive: 'yellow',
    Identity.rose: 'red',
    Identity.clay: 'coral',
    Identity.moss: 'lightGreen',
  };

  /// A identidade de um nome gravado; sem nome (ou nome que saiu da paleta),
  /// `slate`.
  static Identity of(String? name) => _fromName[name] ?? Identity.slate;

  /// O nome antigo a gravar quando o usuário escolhe [identity].
  static String nameOf(Identity identity) => _toName[identity]!;

  /// Os 24 nomes antigos que o mapa lê.
  static Iterable<String> get oldNames => _fromName.keys;
}
