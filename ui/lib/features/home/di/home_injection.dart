import '../../../core/adapters/injector.dart';
import '../domain/repository/screen_control.dart';
import '../domain/repository/shell_repository.dart';
import '../domain/repository/socket_shell_repository.dart';
import '../domain/repository/socket_ui_request_repository.dart';
import '../domain/repository/ui_request_repository.dart';
import '../domain/usecase/answer_ui_request.dart';
import '../domain/usecase/reply_ui_request.dart';
import '../domain/usecase/resolve_access_lock.dart';
import '../domain/usecase/set_view_mode.dart';
import '../domain/usecase/watch_shell.dart';
import '../domain/usecase/watch_ui_requests.dart';
import '../presentation/cubit/shell_cubit.dart';
import '../presentation/cubit/ui_request_cubit.dart';

/// O que a casca entrega ao cubit dos pedidos de tela: quem os atende e como
/// trazer a janela para a frente.
typedef UiRequestHost = ({
  ScreenControl screen,
  Future<void> Function() activate,
});

/// A casca falando com o core Rust: a vista da bancada e os pedidos de tela.
void registerHomeRepositories() {
  Injector.factory<ShellRepository>(() => SocketShellRepository(inject()));
  Injector.factory<UiRequestRepository>(
    () => SocketUiRequestRepository(inject()),
  );
}

void registerHomeDomain() {
  Injector.factory(() => WatchShell(inject()));
  Injector.factory(() => SetViewMode(inject()));
  Injector.factory(() => ResolveAccessLock(inject()));
  Injector.factory(
    () => ShellCubit(watch: inject(), setView: inject(), access: inject()),
  );

  Injector.factory(() => WatchUiRequests(inject()));
  Injector.factory(() => ReplyUiRequest(inject()));
  // Quem atende o pedido é a tela da casca, que só existe montada.
  Injector.factoryParam<AnswerUiRequest, ScreenControl>(AnswerUiRequest.new);
  Injector.factoryParam<UiRequestCubit, UiRequestHost>(
    (host) => UiRequestCubit(
      watch: inject(),
      answer: inject(host.screen),
      reply: inject(),
      activate: host.activate,
      activations: inject<UiRequestRepository>().activations(),
    ),
  );
}
