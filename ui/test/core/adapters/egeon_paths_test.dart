import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EGEON_HOME manda', () {
    final paths = EgeonPaths({'EGEON_HOME': '/tmp/h', 'HOME': '/Users/x'});
    expect(paths.home, '/tmp/h');
    expect(paths.socket, '/tmp/h/sock');
  });

  test('sem EGEON_HOME usa ~/.egeon-next, nunca ~/.egeon', () {
    final paths = EgeonPaths({'HOME': '/Users/x'});
    expect(paths.home, '/Users/x/.egeon-next');
    expect(paths.socket, '/Users/x/.egeon-next/sock');
  });
}
