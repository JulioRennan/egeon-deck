import 'package:egeon_deck/commons/utils/bench_identity.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('os 24 nomes antigos do core estão no mapa', () {
    expect(BenchIdentity.oldNames.toSet().length, 24);
  });

  test(
    'cada identidade grava um nome antigo, e lido de volta dá ela mesma',
    () {
      final written = <String>{};
      for (final identity in Identity.values) {
        final name = BenchIdentity.nameOf(identity);
        expect(written.add(name), isTrue, reason: 'nome repetido: $name');
        expect(BenchIdentity.of(name), identity, reason: identity.name);
      }
    },
  );

  test('toda identidade é lida por algum nome antigo', () {
    final reached = {
      for (final n in BenchIdentity.oldNames) BenchIdentity.of(n),
    };
    expect(reached, Identity.values.toSet());
  });

  test('cada nome antigo lê como a identidade combinada', () {
    const expected = {
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
    expect(BenchIdentity.oldNames.toSet(), expected.keys.toSet());
    expected.forEach((name, identity) {
      expect(BenchIdentity.of(name), identity, reason: name);
    });
  });

  test('sem nome ou com nome que saiu da paleta, slate', () {
    expect(BenchIdentity.of(null), Identity.slate);
    expect(BenchIdentity.of('dourado'), Identity.slate);
  });
}
