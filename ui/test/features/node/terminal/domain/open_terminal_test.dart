import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_info.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/open_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fake_terminal_repository.dart';

TerminalInfo info(String id, {bool alive = true}) =>
    TerminalInfo(id: id, alive: alive, columns: 80, rows: 24);

void main() {
  late FakeTerminalRepository repository;
  late OpenTerminal open;

  setUp(() {
    repository = FakeTerminalRepository();
    open = OpenTerminal(repository);
  });

  test('sem terminais, cria um', () async {
    expect((await open()).id, 't1');
    expect(repository.created, 1);
  });

  test('mantém o atual se ele ainda vive', () async {
    repository.terminals.addAll([info('a'), info('b')]);
    expect((await open(current: 'b')).id, 'b');
    expect(repository.created, 0);
  });

  test('sem atual, usa o primeiro vivo', () async {
    repository.terminals.addAll([info('a', alive: false), info('b')]);
    expect((await open()).id, 'b');
  });

  test('core reiniciado: o atual sumiu, cria outro', () async {
    expect((await open(current: 'velho')).id, 't1');
  });
}
