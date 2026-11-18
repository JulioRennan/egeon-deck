/// `{"effect":…}` no tópico `app`: aviso de uma vez só — quem assina depois não
/// o recebe. O core manda o resultado pronto: título, texto e rótulos saem
/// dele, e a UI só os desenha e devolve o gesto.
sealed class AppEffect {
  const AppEffect();

  /// O efeito, ou nulo para o que não é daqui (`ui_request` é da casca).
  static AppEffect? tryParse(Map<String, Object?> map) =>
      switch (map['effect']) {
        'update_prompt' => UpdatePrompt(
          version: map['version'] as String? ?? '',
          title: map['title'] as String? ?? '',
          text: map['text'] as String? ?? '',
          auto: map['auto'] as bool? ?? false,
          autoLabel: map['auto_label'] as String? ?? '',
          acceptLabel: map['accept_label'] as String? ?? 'Atualizar',
          laterLabel: map['later_label'] as String? ?? 'Depois',
        ),
        'update_message' => UpdateMessage(
          title: map['title'] as String? ?? '',
          text: map['text'] as String? ?? '',
        ),
        'terminate' => const Terminate(),
        'show_processes' => const ShowProcesses(),
        _ => null,
      };
}

/// O aviso de versão nova (a folha do `UpdatePrompt` do Swift). A UI responde
/// com `update_answer`.
class UpdatePrompt extends AppEffect {
  const UpdatePrompt({
    required this.version,
    required this.title,
    required this.text,
    required this.auto,
    required this.autoLabel,
    required this.acceptLabel,
    required this.laterLabel,
  });

  final String version;
  final String title;
  final String text;

  /// Como a caixa "atualizar automaticamente" começa.
  final bool auto;
  final String autoLabel;
  final String acceptLabel;
  final String laterLabel;
}

/// Uma mensagem de uma linha e um texto (consulta que falhou, "você está na
/// última versão").
class UpdateMessage extends AppEffect {
  const UpdateMessage({required this.title, required this.text});

  final String title;
  final String text;
}

/// A troca está agendada: a UI encerra o app.
class Terminate extends AppEffect {
  const Terminate();
}

/// Abrir a janela "Processos".
class ShowProcesses extends AppEffect {
  const ShowProcesses();
}
