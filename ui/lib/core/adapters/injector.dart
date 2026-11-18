import 'dart:async';

import 'package:get_it/get_it.dart';

/// O registro de dependências do app, por cima do `get_it`. Só este arquivo
/// importa a biblioteca; o resto registra e pega por aqui.
abstract final class Injector {
  static final _getIt = GetIt.instance;

  /// A instância de [T]; com [param], a de um registro feito por
  /// [factoryParam] — dois valores vão juntos num record.
  static T get<T extends Object>([Object? param]) =>
      _getIt.get<T>(param1: param);

  /// Uma instância nova a cada [get].
  static void factory<T extends Object>(T Function() create) =>
      _getIt.registerFactory<T>(create);

  /// Uma instância nova a cada [get], feita a partir do parâmetro — o id da
  /// bancada, do nó, ou um record com os dois.
  static void factoryParam<T extends Object, P>(T Function(P param) create) =>
      _getIt.registerFactoryParam<T, P, void>((param, _) => create(param));

  /// Uma só, criada no primeiro [get].
  static void lazySingleton<T extends Object>(
    T Function() create, {
    FutureOr<void> Function(T instance)? dispose,
  }) => _getIt.registerLazySingleton<T>(create, dispose: dispose);

  /// Uma só, já criada.
  static void singleton<T extends Object>(
    T instance, {
    FutureOr<void> Function(T instance)? dispose,
  }) => _getIt.registerSingleton<T>(instance, dispose: dispose);

  /// Esquece todos os registros, descartando os únicos que já nasceram.
  static Future<void> reset() => _getIt.reset();
}

/// Atalho de [Injector.get].
T inject<T extends Object>([Object? param]) => Injector.get<T>(param);

/// Um nó de uma bancada: o parâmetro dos cubits de nó cujo repositório é o da
/// bancada.
typedef BenchNode = ({String workbenchId, String nodeId});
