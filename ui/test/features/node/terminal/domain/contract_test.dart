import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_frame.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_info.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/protocol_fixtures.dart';

void main() {
  final events = loadProtocolFixture('events');
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');

  group('tela (screen/<id>)', () {
    for (final name in ['screen_full', 'screen_delta', 'screen_so_cursor']) {
      test('$name faz ida e volta', () {
        final event = events[name]!;
        final frame = TerminalFrame.fromMap(event);
        final expected = {...event}..remove('topic');
        expect(frame.toMap(), expected);
      });
    }

    test('full traz a tela inteira; delta só as linhas que mudaram', () {
      expect(TerminalFrame.fromMap(events['screen_full']!).full, isTrue);
      final delta = TerminalFrame.fromMap(events['screen_delta']!);
      expect(delta.full, isFalse);
      expect(delta.lines.keys, [0]);
    });

    test('os trechos guardam cor, estilo e células', () {
      final line = TerminalFrame.fromMap(events['screen_delta']!).lines[0]!;
      expect(line.runs, hasLength(3));
      expect(line.runs[1].style.foreground!.index, 2);
      expect(line.runs[1].style.bold, isTrue);
      final wide = line.runs[2];
      expect(wide.cells, 4);
      expect(wide.style.foreground!.rgb, 0xff8800);
      expect(wide.style.background!.index, 236);
      expect(wide.style.underline && wide.style.italic, isTrue);
    });

    test('cursor escondido e em barra', () {
      final frame = TerminalFrame.fromMap(events['screen_so_cursor']!);
      expect(frame.cursor.visible, isFalse);
      expect(frame.cursor.shape.name, 'bar');
      expect(frame.lines, isEmpty);
    });
  });

  group('terminais', () {
    test('resposta de create_terminal faz ida e volta', () {
      final reply = replies['terminal_criado']!;
      final info = TerminalInfo.fromMap(reply);
      expect(info.id, 't1');
      expect(
        info.toMap(),
        {...reply}..removeWhere((k, _) => k == 're' || k == 'ok'),
      );
    });

    test('lista traz terminal vivo e terminal que terminou', () {
      final list = (replies['lista']!['terminals']! as List<Object?>)
          .map((e) => TerminalInfo.fromMap(e! as Map<String, Object?>))
          .toList();
      expect(list[0].alive, isTrue);
      expect(list[1].alive, isFalse);
      expect(list[1].exitCode, 0);
      expect(list[1].command, 'make test');
    });
  });

  group('comando key', () {
    Map<String, Object?> wire(String name) {
      final c = commands[name]!;
      return {'key': c['key'], 'mods': c['mods'], 'text': ?c['text']};
    }

    test('enter', () {
      expect(const TerminalKey(key: 'enter').toMap(), wire('key_enter'));
    });
    test('Ctrl+C', () {
      expect(
        const TerminalKey(key: 'c', ctrl: true).toMap(),
        wire('key_ctrl_c'),
      );
    });
    test('Shift+A com texto', () {
      expect(
        const TerminalKey(key: 'a', text: 'A', shift: true).toMap(),
        wire('key_texto'),
      );
    });
    test('PageUp com Alt+Meta', () {
      expect(
        const TerminalKey(key: 'pageup', alt: true, meta: true).toMap(),
        wire('key_pageup_alt'),
      );
    });
  });
}
