import 'package:egeon_deck/features/chat/presentation/widgets/chat_thread_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';

import '../../support/eg_host.dart';

void main() {
  final now = DateTime(2026, 11, 19, 23, 40);

  Future<void> show(WidgetTester tester, DateTime day) =>
      tester.pumpWidget(egHost(DaySeparator(day: day, now: now)));

  testWidgets('o dia de hoje se chama Hoje', (tester) async {
    await show(tester, DateTime(2026, 11, 19, 1));
    expect(find.text('Hoje'), findsOneWidget);
  });

  testWidgets('o dia anterior é Ontem; antes disso, a data', (tester) async {
    await show(tester, DateTime(2026, 11, 18, 23, 59));
    expect(find.text('Ontem'), findsOneWidget);
    await show(tester, DateTime(2026, 11, 3));
    expect(find.text('03/11/2026'), findsOneWidget);
  });

  HeaderBlock header(String id, DateTime? at) => HeaderBlock(
    id: id,
    messageKey: id,
    first: true,
    last: true,
    depth: 0,
    raw: const {},
    from: const ChatWho(id: 'a', address: 'deck/a', isAgent: true),
    at: at,
  );

  test('o separador entra onde o dia muda, e só ali', () {
    final blocks = [
      header('1', DateTime(2026, 11, 18, 22)),
      header('2', DateTime(2026, 11, 18, 23)),
      header('3', null),
      header('4', DateTime(2026, 11, 19, 8)),
    ];
    expect(dayStartingAt(blocks, 0)?.day, 18);
    expect(dayStartingAt(blocks, 1), isNull);
    expect(dayStartingAt(blocks, 2), isNull);
    expect(dayStartingAt(blocks, 3)?.day, 19);
  });

  test('o dia vem do relógio local, mesmo com o core mandando UTC', () {
    final first = DateTime.utc(2026, 11, 19, 2, 30);
    final second = DateTime.utc(2026, 11, 19, 22, 30);
    final blocks = [header('1', first), header('2', second)];
    final sameLocalDay = first.toLocal().day == second.toLocal().day;
    expect(dayStartingAt(blocks, 0)?.toLocal().day, first.toLocal().day);
    expect(dayStartingAt(blocks, 1) == null, sameLocalDay);
  });

  testWidgets('o separador compara o dia local, não o UTC', (tester) async {
    final at = DateTime.utc(2026, 11, 19, 23, 30);
    await tester.pumpWidget(egHost(DaySeparator(day: at, now: at.toLocal())));
    expect(find.text('Hoje'), findsOneWidget);
  });
}
