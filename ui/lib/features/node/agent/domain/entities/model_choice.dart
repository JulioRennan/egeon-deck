/// O que se trocou no seletor do cabeçalho de um agente. Modelo e esforço andam
/// juntos porque o efeito é o mesmo — o processo reinicia e a conversa fica.
sealed class ModelChoice {
  const ModelChoice();
}

/// Nulo é o padrão do CLI.
class ModelPick extends ModelChoice {
  const ModelPick(this.model);
  final String? model;
}

/// A barra do esforço foi para a marca [index] (arrasto, clique ou rolagem).
/// Quem decide o que isso vale é o core.
class EffortMove extends ModelChoice {
  const EffortMove(this.index);
  final int index;
}

/// A pílula "auto" foi tocada.
class EffortToggleAuto extends ModelChoice {
  const EffortToggleAuto();
}

/// A mão parou: o core aplica a escolha (reinicia o processo e mantém a
/// conversa).
class EffortSettle extends ModelChoice {
  const EffortSettle();
}

class UltracodePick extends ModelChoice {
  const UltracodePick({required this.on});
  final bool on;
}
