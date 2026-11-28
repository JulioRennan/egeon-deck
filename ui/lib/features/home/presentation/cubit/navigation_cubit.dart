import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/shell_snapshot.dart';
import '../../domain/errors/home_error.dart';
import '../../domain/usecase/go_to_bench.dart';
import '../../domain/usecase/watch_shell.dart';

part 'navigation_state.dart';

/// O histórico de navegação entre bancadas (voltar ⌘[ e avançar ⌘]). É só da
/// UI: o core não guarda por onde o usuário passou, só qual aba está na frente.
///
/// Lê as bancadas que passam pela tela e quais ainda têm aba; voltar e avançar
/// pedem a troca ao core, e a bancada que chega por esse pedido não conta como
/// visita nova. Bancada que fechou a aba sai do histórico.
class NavigationCubit extends Cubit<NavigationState> {
  NavigationCubit({required WatchShell watch, required this.goTo})
    : super(const NavigationFresh()) {
    _subscription = watch().listen(_onSnapshot);
  }

  final GoToBench goTo;
  StreamSubscription<ShellSnapshot>? _subscription;

  String? _current;
  Set<String> _open = const {};

  /// A bancada que voltar/avançar acabou de pedir: a visita que chegar com este
  /// id é a resposta, não uma navegação nova.
  String? _expected;

  static const _limit = 50;

  void _onSnapshot(ShellSnapshot snapshot) {
    _open = snapshot.openBenchIds;
    var back = state.back;
    var forward = state.forward;
    final id = snapshot.bench?.id;
    if (id != null && id != _current) {
      final previous = _current;
      _current = id;
      final answered = id == _expected;
      _expected = null;
      if (!answered && previous != null) {
        back = [...back, previous];
        if (back.length > _limit) back = back.sublist(back.length - _limit);
        forward = const [];
      }
    }
    // Só vale o que ainda tem aba.
    back = [
      for (final b in back)
        if (_open.contains(b)) b,
    ];
    forward = [
      for (final b in forward)
        if (_open.contains(b)) b,
    ];
    _emitIfChanged(back, forward);
  }

  void _emitIfChanged(List<String> back, List<String> forward) {
    if (_same(back, state.back) && _same(forward, state.forward)) return;
    emit(
      back.isEmpty && forward.isEmpty
          ? const NavigationFresh()
          : NavigationVisited(back: back, forward: forward),
    );
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

  /// ⌘[: a bancada de antes que ainda está aberta; sem nenhuma, nada.
  void back() => _travel(forward: false);

  /// ⌘]: a bancada de depois que ainda está aberta.
  void forward() => _travel(forward: true);

  void _travel({required bool forward}) {
    final from = [...(forward ? state.forward : state.back)];
    final current = _current;
    if (from.isEmpty || current == null) return;
    final target = from.removeLast();
    final before = (back: state.back, forward: state.forward);
    _expected = target;
    if (forward) {
      _emitIfChanged([...state.back, current], from);
    } else {
      _emitIfChanged(from, [...state.forward, current]);
    }
    unawaited(
      goTo(target).catchError((_) {
        // O core recusou: a bancada não mudou, o histórico volta como estava.
        _expected = null;
        _emitIfChanged(before.back, before.forward);
      }, test: (error) => error is HomeError),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
