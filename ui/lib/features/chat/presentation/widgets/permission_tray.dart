import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/permission_request.dart';
import 'chat_palette.dart';

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
    final verb = _ask.isQuestion
        ? ' pergunta'
        : (_ask.detail == null
              ? ' quer usar ${_ask.tool}'
              : ' quer usar ${_ask.tool} — ${_ask.detail}');
    return Container(
      key: const ValueKey('permission-tray'),
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.attention.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.attention.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: '⚠ ',
                  style: TextStyle(color: AppColors.attention),
                ),
                TextSpan(
                  text: widget.agentName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: verb,
                  style: TextStyle(color: AppColors.white(0.85)),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFFFFFFF),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 8),
          if (_ask.isQuestion) ..._questions() else ..._tool(),
        ],
      ),
    );
  }

  List<Widget> _tool() => [
    Text(
      _ask.summary.replaceAll('\n', ' ⏎ '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 11,
        color: AppColors.white(0.75),
        decoration: TextDecoration.none,
      ),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: [
        _Button(
          'Permitir',
          color: AppColors.done,
          onTap: () => widget.onAnswer(_ask.id, 'allow'),
        ),
        if (_ask.canAlwaysAllow)
          _Button('Sempre', onTap: () => widget.onAnswer(_ask.id, 'always')),
        _Button(
          'Negar',
          color: const Color(0xFFFF453A),
          onTap: () => widget.onAnswer(_ask.id, 'deny'),
        ),
      ],
    ),
  ];

  List<Widget> _questions() => [
    for (final q in _ask.questions) ...[
      Text(
        '${q.header == null ? '' : '${q.header} · '}${q.question}',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.white(0.9),
          decoration: TextDecoration.none,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final option in q.options)
            _Button(
              option,
              on: (_picked[q.question] ?? const []).contains(option),
              onTap: () => _toggle(q, option),
            ),
        ],
      ),
      const SizedBox(height: 8),
    ],
    if (_ask.collects)
      Align(
        alignment: Alignment.centerRight,
        child: _Button(
          'Responder',
          enabled: _complete,
          color: AppColors.done,
          onTap: () => widget.onAnswerAll(_ask.id, {
            for (final e in _picked.entries) e.key: [...e.value],
          }),
        ),
      ),
  ];
}

class _Button extends StatelessWidget {
  const _Button(
    this.label, {
    required this.onTap,
    this.color,
    this.on = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? ChatPalette.link;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: color != null
                  ? tint.withValues(alpha: 0.75)
                  : (on ? tint.withValues(alpha: 0.35) : AppColors.white(0.1)),
              borderRadius: BorderRadius.circular(6),
              border: on ? Border.all(color: tint) : null,
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFFFFFFFF),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
