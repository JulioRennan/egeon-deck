import 'dart:async';
import 'dart:io';

import 'egeon_socket_client.dart';

/// Para onde vai o que a UI não conseguiu ler de um evento do core. Sem isso,
/// um campo que o core manda nulo e a UI não esperava derrubava o stream em
/// silêncio e o card ficava vazio sem ninguém saber por quê.
typedef ParseFailureSink = void Function(
  String what,
  Object error,
  StackTrace stack,
);

abstract final class ParseFailures {
  /// O destino das falhas: o stderr, que aparece no console do app em dev. A
  /// pasta de dados é do core; arquivo de log da UI ali seria dono duplo. O
  /// teste troca o destino por uma lista.
  static ParseFailureSink sink = _toStderr;

  static final _seen = <String, int>{};

  /// Quantas vezes cada falha distinta se repetiu nesta sessão.
  static Map<String, int> get counts => Map.unmodifiable(_seen);

  /// Registra a falha só na primeira vez que ela aparece (o que lê + o tipo
  /// do erro + a 1ª linha da mensagem): se um formato muda e todo evento
  /// falha, sai uma linha, não uma por evento.
  static void report(String what, Object error, StackTrace stack) {
    final first = error.toString().split('\n').first;
    final key = '$what|${error.runtimeType}|$first';
    final count = _seen[key] ?? 0;
    _seen[key] = count + 1;
    if (count == 0) sink(what, error, stack);
  }

  /// Esquece o que já viu: só o teste precisa.
  static void reset() => _seen.clear();

  static void _toStderr(String what, Object error, StackTrace stack) =>
      stderr.writeln('ui: não consegui ler "$what": $error');
}

extension ParsedEvents on Stream<EgeonMessage> {
  /// Lê cada evento com [read]. Se ele não se deixa ler, a falha vai para
  /// [ParseFailures.sink] e o stream segue vivo: com [fallback], o que ele der
  /// vira o estado, mas só enquanto nenhum estado bom chegou (a tela mostra o
  /// que der em vez de esperar para sempre); depois do primeiro bom, o evento
  /// ilegível é descartado e o último estado fica — a menos que
  /// [fallbackAfterFirst]: é o caso de quem recebe diff (o chat), que precisa
  /// saber do evento perdido para pedir o estado inteiro.
  Stream<T> parsed<T>(
    String what,
    T Function(EgeonMessage event) read, {
    T Function(EgeonMessage event)? fallback,
    bool fallbackAfterFirst = false,
  }) {
    var delivered = false;
    return transform(
      StreamTransformer<EgeonMessage, T>.fromHandlers(
        handleData: (event, sink) {
          try {
            sink.add(read(event));
            delivered = true;
          } on Object catch (error, stack) {
            ParseFailures.report(what, error, stack);
            if (fallback != null && (!delivered || fallbackAfterFirst)) {
              sink.add(fallback(event));
            }
          }
        },
      ),
    );
  }
}
