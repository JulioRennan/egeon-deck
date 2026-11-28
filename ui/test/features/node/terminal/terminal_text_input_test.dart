import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_text_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> texts;
  late TerminalTextInput input;

  setUp(() {
    texts = [];
    input = TerminalTextInput(onText: texts.add);
  });

  tearDown(() => input.dispose());

  TextEditingValue value(String text, {TextRange? composing}) =>
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: composing ?? TextRange.empty,
      );

  test('composição em andamento não emite; o commit emite uma vez', () {
    input.attach();
    input.updateEditingValue(
      value('´', composing: const TextRange(start: 0, end: 1)),
    );
    expect(input.isComposing, isTrue);
    expect(input.composing.value, '´');
    expect(texts, isEmpty);

    input.updateEditingValue(value('á'));
    expect(input.isComposing, isFalse);
    expect(texts, ['á']);
  });

  test('tecla morta seguida de tecla incompatível sai como um texto só', () {
    input.attach();
    input.updateEditingValue(value('´x'));
    expect(texts, ['´x']);
  });

  test('perder o foco no meio da composição descarta o acento pendente', () {
    input.attach();
    input.updateEditingValue(
      value('´', composing: const TextRange(start: 0, end: 1)),
    );
    input.detach();
    expect(input.isComposing, isFalse);
    expect(texts, isEmpty);
  });

  test('conexão fechada avisa quem a reabre', () {
    var closed = 0;
    final watched = TerminalTextInput(
      onText: texts.add,
      onClosed: () => closed++,
    );
    watched.attach();
    watched.connectionClosed();
    expect(closed, 1);
    watched.dispose();
  });

  test('conexão fechada pelo sistema pode ser reaberta', () {
    input.attach();
    expect(input.attached, isTrue);
    input.connectionClosed();
    expect(input.attached, isFalse);
    input.attach();
    expect(input.attached, isTrue);
  });
}
