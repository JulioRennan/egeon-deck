import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/agent_name.dart';
import '../../../../commons/widgets/eg/badge.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/utils/agent_identity.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/processes_view.dart';

/// A tabela de processos do DS (`ProcessTable`): processo (com o dot de estado
/// e, órfão, a etiqueta), nó na cor dele, PID e tempo. CPU e memória não vêm do
/// core ainda, então não há coluna para elas. Cabeçalho de 32, linha de 36,
/// fio de baixo em cada uma; a selecionada tem o fundo do acento e a órfã o
/// texto apagado.
class ProcessTable extends StatelessWidget {
  const ProcessTable({
    required this.rows,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final List<ProcessRow> rows;
  final Set<int> selected;
  final void Function(
    ProcessRow row, {
    required bool additive,
    required bool range,
  })
  onTap;

  static const _node = 220.0;
  static const _pid = 80.0;
  static const _time = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          cells: const [
            (null, 'Processo', false),
            (_node, 'Nó', false),
            (_pid, 'PID', true),
            (_time, 'Tempo', true),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => _Row(
              row: rows[i],
              selected: selected.contains(rows[i].pid),
              onTap: onTap,
              line: c.lineSubtle,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.cells});

  final List<(double?, String, bool)> cells;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final style = EgeonType.caption.copyWith(
      fontWeight: FontWeight.w500,
      color: c.textMuted,
      decoration: TextDecoration.none,
    );
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: EgeonSpace.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          for (final (width, label, numeric) in cells)
            _cell(
              width,
              Text(
                label,
                maxLines: 1,
                textAlign: numeric ? TextAlign.right : TextAlign.left,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

Widget _cell(double? width, Widget child) => width == null
    ? Expanded(child: child)
    : SizedBox(width: width, child: child);

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.line,
  });

  final ProcessRow row;
  final bool selected;
  final void Function(
    ProcessRow row, {
    required bool additive,
    required bool range,
  })
  onTap;
  final Color line;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final dead = row.orphan;
    final text = dead ? c.textDisabled : c.textSecondary;
    final numeric = EgeonType.monoMeta.copyWith(
      color: text,
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
    return Pressable(
      key: ValueKey('process-${row.pid}'),
      semanticLabel: row.command,
      onPressed: () {
        final keys = HardwareKeyboard.instance;
        onTap(
          row,
          additive: keys.isMetaPressed || keys.isControlPressed,
          range: keys.isShiftPressed,
        );
      },
      builder: (context, s) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: EgeonSpace.s3),
        decoration: BoxDecoration(
          color: selected
              ? c.accentSoft
              : s.hovered
              ? c.steel
              : null,
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: Row(
          children: [
            _cell(
              null,
              Row(
                children: [
                  StatusDot(
                    dead ? Status.dead : Status.idle,
                    size: StatusDotSize.sm,
                  ),
                  const SizedBox(width: EgeonSpace.s2),
                  Flexible(
                    child: Text(
                      row.command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EgeonType.monoMeta.copyWith(
                        color: selected ? c.textPrimary : text,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (dead) ...[
                    const SizedBox(width: EgeonSpace.s2),
                    const Badge('órfão', tone: BadgeTone.outline),
                  ],
                ],
              ),
            ),
            _cell(
              ProcessTable._node,
              row.node == null
                  ? Text(
                      '—',
                      style: EgeonType.caption.copyWith(
                        color: c.textMuted,
                        decoration: TextDecoration.none,
                      ),
                    )
                  : AgentName(row.node!, identity: agentIdentity(row.node!)),
            ),
            _cell(
              ProcessTable._pid,
              Text('${row.pid}', textAlign: TextAlign.right, style: numeric),
            ),
            _cell(
              ProcessTable._time,
              Text(row.age, textAlign: TextAlign.right, style: numeric),
            ),
          ],
        ),
      ),
    );
  }
}
