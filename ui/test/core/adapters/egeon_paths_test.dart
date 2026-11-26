import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:flutter_test/flutter_test.dart';

const installed =
    '/Applications/EgeonDeck Next.app/Contents/MacOS/EgeonDeck Next';

EgeonPaths release(Map<String, String> env) =>
    EgeonPaths(env, release: true, executable: installed);

void main() {
  test('EGEON_HOME manda', () {
    final paths = EgeonPaths({'EGEON_HOME': '/tmp/h', 'HOME': '/Users/x'});
    expect(paths.home, '/tmp/h');
    expect(paths.socket, '/tmp/h/sock');
  });

  test('sem EGEON_HOME usa ~/.egeon-next, nunca ~/.egeon', () {
    final paths = release({'HOME': '/Users/x'});
    expect(paths.flavor, EgeonFlavor.stable);
    expect(paths.home, '/Users/x/.egeon-next');
    expect(paths.socket, '/Users/x/.egeon-next/sock');
  });

  test('o dev tem pasta e nome próprios', () {
    final paths = EgeonPaths({'HOME': '/Users/x', 'EGEON_FLAVOR': 'dev'});
    expect(paths.flavor, EgeonFlavor.dev);
    expect(paths.home, '/Users/x/.egeon-next-dev');
    expect(paths.flavor.title, 'Egeon Deck (dev)');
  });

  test('EGEON_HOME vence o flavor', () {
    final paths = EgeonPaths({
      'HOME': '/Users/x',
      'EGEON_FLAVOR': 'dev',
      'EGEON_HOME': '/tmp/h',
    });
    expect(paths.home, '/tmp/h');
  });

  test('valor desconhecido de EGEON_FLAVOR vale o estável, como no core', () {
    final paths = release({'HOME': '/Users/x', 'EGEON_FLAVOR': 'Dev'});
    expect(paths.flavor, EgeonFlavor.stable);
  });

  test(
    'build de depuração nunca abre a pasta do estável, nem sem a variável',
    () {
      final paths = EgeonPaths(
        {'HOME': '/Users/x'},
        release: false,
        executable: installed,
      );
      expect(paths.flavor, EgeonFlavor.dev);
      expect(paths.home, '/Users/x/.egeon-next-dev');
    },
  );

  test('o bundle dev é dev mesmo quando o macOS perde o LSEnvironment', () {
    final paths = EgeonPaths(
      {'HOME': '/Users/x'},
      release: true,
      executable:
          '/x/ui/build/EgeonDeck Next Dev.app/Contents/MacOS/EgeonDeck Next',
    );
    expect(paths.flavor, EgeonFlavor.dev);
  });
}
