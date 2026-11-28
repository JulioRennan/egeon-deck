part of 'multi_worktree_form_cubit.dart';

/// A branch da bancada e o que foi escrito à mão em cada repositório.
final class MultiWorktreeFormState {
  const MultiWorktreeFormState({
    required this.repos,
    this.branch = '',
    this.edited = const {},
  });

  /// Os nomes dos links, um campo por repositório.
  final List<String> repos;
  final String branch;

  /// Só as linhas que a pessoa escreveu (e não esvaziou).
  final Map<String, String> edited;

  /// A linha acompanha a bancada enquanto não foi editada.
  bool follows(String repo) => !edited.containsKey(repo);

  String rowText(String repo) => edited[repo] ?? branch;

  /// O que vai ao `worktree`: só os repositórios com branch diferente da da
  /// bancada.
  Map<String, String> get overrides {
    final main = branch.trim();
    return {
      for (final entry in edited.entries)
        if (entry.value.trim().isNotEmpty && entry.value.trim() != main)
          entry.key: entry.value.trim(),
    };
  }

  bool get canOpen => branch.trim().isNotEmpty;
}
