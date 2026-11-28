import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/button.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_type.dart';
import 'chat_palette.dart';
import '../../domain/entities/permission_request.dart';
import '../../../../theme/egeon_colors.dart';

/// O verbo de uma ferramenta, para "revisor quer editar lib/a.dart": o que o
/// pedido diz em português. Ferramenta que não se conhece fica "usar X".
String toolVerb(String tool) => switch (tool) {
  'Edit' || 'MultiEdit' || 'NotebookEdit' => 'editar',
  'Write' => 'escrever',
  'Read' => 'ler',
  'Bash' || 'BashOutput' => 'rodar',
  'Glob' || 'Grep' || 'LS' => 'buscar em',
  'WebFetch' => 'abrir',
  'WebSearch' => 'pesquisar',
  'Task' => 'delegar',
  _ => 'usar $tool',
};

/// A bandeja de permissão: o agente quer usar uma ferramenta, ou faz perguntas.
/// Laranja, sem spinner — não há trabalho andando, há você para decidir.
class PermissionTray extends StatefulWidget {
  const PermissionTray({
    required this.request,
    required this.agentName,
    required this.onAnswer,
    required this.onChoose,
    required this.onAnswerAll,
    super.key,
  });

  final PermissionRequest request;

  /// Quem pede, para o título.
  final String agentName;
  final void Function(String request, String answer) onAnswer;
  final void Function(String request, String choice) onChoose;
  final void Function(String request, Map<String, List<String>> answers)
  onAnswerAll;

  @override
  State<PermissionTray> createState() => _PermissionTrayState();
}

class _PermissionTrayState extends State<PermissionTray> {
  final _picked = <String, List<String>>{};

  PermissionRequest get _ask => widget.request;

  @override
  void didUpdateWidget(PermissionTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id != widget.request.id) _picked.clear();
  }

  bool get _complete =>
      _ask.questions.every((q) => (_picked[q.question] ?? const []).isNotEmpty);

  void _toggle(PermissionQuestion question, String option) {
    final id = _ask.id;
    if (!_ask.collects) return widget.onChoose(id, option);
    setState(() {
      final list = _picked.putIfAbsent(question.question, () => []);
      if (question.multiSelect) {
        if (!list.remove(option)) list.add(option);
      } else {
        list
          ..clear()
          ..add(option);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final verb = _ask.isQuestion ? ' pergunta' : ' quer ${toolVerb(_ask.tool)}';
    final who = ChatPalette.ofId(c, widget.agentName);
    return DecoratedBox(
      key: const ValueKey('permission-tray'),
      decoration: BoxDecoration(
        color: c.attention.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.attention.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const StatusDot(Status.attention, animated: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    key: const ValueKey('permission-summary-tip'),
                    message: _ask.summary,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: widget.agentName,
                            style: TextStyle(
                              color: who,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: verb),
                          // O que se aprova (arquivo, comando, URL) na mesma
                          // linha, em mono.
                          if (!_ask.isQuestion && _ask.summary.isNotEmpty)
                            TextSpan(
                              text: ' ${_ask.summary.replaceAll('\n', ' ⏎ ')}',
                              style: EgeonType.monoMeta.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                        ],
                      ),
                      // Um comando longo quebra em até 3 linhas antes de cortar,
                      // e a dica traz o texto inteiro: não se aprova o que não
                      // se lê.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: EgeonType.small.copyWith(
                        color: c.textPrimary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                if (!_ask.isQuestion) ..._tool(),
              ],
            ),
            if (!_ask.isQuestion && _ask.detail != null)
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 4),
                child: Text(
                  _ask.detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EgeonType.caption.copyWith(
                    color: c.textMuted,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            if (_ask.isQuestion)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _questions(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Permitir · Sempre · Negar: o texto fixo do DS.
  List<Widget> _tool() => [
    const SizedBox(width: 10),
    Button(
      key: const ValueKey('permission-allow'),
      label: 'Permitir',
      size: ButtonSize.sm,
      kind: ButtonKind.primary,
      onPressed: () => widget.onAnswer(_ask.id, 'allow'),
    ),
    if (_ask.canAlwaysAllow) ...[
      const SizedBox(width: 6),
      Button(
        key: const ValueKey('permission-always'),
        label: 'Sempre',
        size: ButtonSize.sm,
        kind: ButtonKind.secondary,
        onPressed: () => widget.onAnswer(_ask.id, 'always'),
      ),
    ],
    const SizedBox(width: 6),
    Button(
      key: const ValueKey('permission-deny'),
      label: 'Negar',
      size: ButtonSize.sm,
      kind: ButtonKind.secondary,
      onPressed: () => widget.onAnswer(_ask.id, 'deny'),
    ),
  ];

  /// Recusa a pergunta: o agente segue sem a resposta. Vai junto do
  /// "Responder" ou, sem ele, ao fim das opções da última pergunta.
  Widget get _refuse => Button(
    key: const ValueKey('permission-refuse'),
    label: 'Recusar',
    size: ButtonSize.sm,
    kind: ButtonKind.secondary,
    onPressed: () => widget.onAnswer(_ask.id, 'deny'),
  );

  List<Widget> _questions() {
    final c = context.eg;
    return [
      for (final (index, q) in _ask.questions.indexed) ...[
        Text(
          '${q.header == null ? '' : '${q.header} · '}${q.question}',
          style: EgeonType.small.copyWith(
            color: c.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in q.options)
              Button(
                label: option,
                size: ButtonSize.sm,
                kind: ButtonKind.secondary,
                selected: (_picked[q.question] ?? const []).contains(option),
                onPressed: () => _toggle(q, option),
              ),
            if (!_ask.collects && index == _ask.questions.length - 1) _refuse,
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (_ask.collects)
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 6,
            children: [
              Button(
                label: 'Responder',
                size: ButtonSize.sm,
                onPressed: _complete
                    ? () => widget.onAnswerAll(_ask.id, {
                        for (final e in _picked.entries) e.key: [...e.value],
                      })
                    : null,
              ),
              _refuse,
            ],
          ),
        )
      else if (_ask.questions.isEmpty)
        _refuse,
    ];
  }
}
