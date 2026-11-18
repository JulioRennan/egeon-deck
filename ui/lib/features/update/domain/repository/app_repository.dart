import '../entities/app_effect.dart';
import '../entities/app_state.dart';

abstract interface class AppRepository {
  /// O estado do app (atualização e limpeza de órfãos): inteiro a cada mudança.
  Stream<AppState> watch();

  /// Aviso de versão nova, mensagem, encerrar e abrir Processos.
  Stream<AppEffect> effects();

  /// A resposta ao aviso: atualizar e reiniciar, ou depois — e a caixa de
  /// atualizar sozinho como ficou.
  Future<void> answerUpdate({
    required String version,
    required bool accept,
    required bool auto,
  });

  /// O item de menu "Atualizar automaticamente".
  Future<void> setUpdateAuto({required bool on});

  /// O item de menu "Procurar atualizações…" (ou o que o estado fizer dele).
  Future<void> pressUpdateMenu();

  /// O item de menu "Limpar órfãos automaticamente".
  Future<void> setReaperEnabled({required bool on});
}
