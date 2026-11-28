import '../../../../../commons/utils/effort_names.dart';
import '../../../../canvas/domain/entities/canvas_component.dart';
import '../entities/node_form_view.dart';
import '../entities/node_template.dart';
import '../errors/agent_error.dart';
import '../repository/node_form_repository.dart';

/// Os nomes dos componentes salvos, na ordem do core: o menu de segurar o
/// botão Terminal.
class ListComponents {
  const ListComponents(this._repository);

  final NodeFormRepository _repository;

  Future<List<String>> call() async => [
    for (final component in await _repository.components()) component.name,
  ];

  /// Os mesmos componentes com a linha de apoio do menu: o CLI, o modelo e o
  /// esforço que o componente fixa, o que faltar fica de fora. O modelo sai
  /// com o título do catálogo do CLI do componente ("Opus 5.5"); se o catálogo
  /// não responde ou não o conhece, vale o apelido que o template guarda.
  Future<List<CanvasComponent>> choices(String workbenchId) async {
    final components = await _repository.components();
    final titles = <String, Map<String, String>>{};
    for (final component in components) {
      final cli = component.template.agent;
      if (cli == null || titles.containsKey(cli)) continue;
      titles[cli] = await _catalog(workbenchId, component.template, cli);
    }
    return [
      for (final component in components)
        CanvasComponent(
          component.name,
          meta: _meta(component, titles[component.template.agent] ?? const {}),
        ),
    ];
  }

  /// O catálogo de modelos do [cli]: o valor que o template guarda → o título.
  Future<Map<String, String>> _catalog(
    String workbenchId,
    NodeTemplate template,
    String cli,
  ) async {
    try {
      final screen = await _repository.screen(
        workbenchId,
        template: template,
        cli: cli,
      );
      return {
        for (final model in screen.models)
          if (model.id != null) model.id!: model.label,
      };
    } on AgentError {
      return const {};
    }
  }

  static String? _meta(ComponentInfo component, Map<String, String> titles) {
    final overrides = component.template.byAgent[component.template.agent];
    final parts = [
      if (component.subtitle.isNotEmpty) component.subtitle,
      if (overrides?.model case final model? when model.isNotEmpty)
        titles[model] ?? model,
      if (overrides?.effort case final effort? when effort.isNotEmpty)
        effortName(effort),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
