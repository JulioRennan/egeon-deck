import '../../../core/adapters/injector.dart';
import '../domain/repository/socket_workspace_repository.dart';
import '../domain/repository/workspace_repository.dart';
import '../domain/usecase/create_project.dart';
import '../domain/usecase/remove_workspace.dart';
import '../domain/usecase/save_workspace.dart';

void registerWorkspaceRepositories() {
  Injector.factory<WorkspaceRepository>(
    () => SocketWorkspaceRepository(inject()),
  );
}

void registerWorkspaceDomain() {
  Injector.factory(() => RemoveWorkspace(inject()));
  Injector.factory(() => SaveWorkspace(inject()));
  Injector.factory(() => CreateProject(inject()));
}
