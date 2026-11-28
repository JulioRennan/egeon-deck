import 'package:flutter_bloc/flutter_bloc.dart';

part 'multi_worktree_form_state.dart';

/// Dono do formulário de worktree de multi-projeto (`MultiWorktreeForm`). As
/// linhas dos repositórios acompanham a branch da bancada enquanto ninguém
/// mexe nelas; mexeu, a linha é sua; esvaziá-la volta a acompanhar.
class MultiWorktreeFormCubit extends Cubit<MultiWorktreeFormState> {
  MultiWorktreeFormCubit({required List<String> repos})
    : super(MultiWorktreeFormState(repos: repos));

  void setBranch(String branch) => emit(
    MultiWorktreeFormState(
      repos: state.repos,
      branch: branch,
      edited: state.edited,
    ),
  );

  void editRepo(String repo, String text) => emit(
    MultiWorktreeFormState(
      repos: state.repos,
      branch: state.branch,
      edited: {
        for (final entry in state.edited.entries)
          if (entry.key != repo) entry.key: entry.value,
        if (text.isNotEmpty) repo: text,
      },
    ),
  );
}
