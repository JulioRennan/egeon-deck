part of 'worktree_branch_cubit.dart';

/// A branch da bancada no formulário de worktree e o veredito do core.
sealed class WorktreeBranchState {
  const WorktreeBranchState();
}

/// Nada escrito: não há o que perguntar.
final class BranchEmpty extends WorktreeBranchState {
  const BranchEmpty();
}

/// Esperando a pessoa parar de digitar, ou o core responder.
final class BranchAsking extends WorktreeBranchState {
  const BranchAsking(this.branch);

  final String branch;
}

/// O veredito do core para [branch].
final class BranchJudged extends WorktreeBranchState {
  const BranchJudged(this.branch, this.plan);

  final String branch;
  final WorktreePlan plan;
}
