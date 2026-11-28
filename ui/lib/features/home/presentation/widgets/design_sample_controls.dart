import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/agent_name.dart';
import '../../../../commons/widgets/eg/attention_ring.dart';
import '../../../../commons/widgets/eg/badge.dart';
import '../../../../commons/widgets/eg/banner.dart';
import '../../../../commons/widgets/eg/button.dart';
import '../../../../commons/widgets/eg/checkbox.dart';
import '../../../../commons/widgets/eg/code_block.dart';
import '../../../../commons/widgets/eg/context_ring.dart';
import '../../../../commons/widgets/eg/counter.dart';
import '../../../../commons/widgets/eg/diff_view.dart';
import '../../../../commons/widgets/eg/edge_label.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/identity.dart';
import '../../../../commons/widgets/eg/info_pill.dart';
import '../../../../commons/widgets/eg/radio.dart';
import '../../../../commons/widgets/eg/segmented_control.dart';
import '../../../../commons/widgets/eg/view_switch.dart';
import '../../../../commons/widgets/eg/select.dart';
import '../../../../commons/widgets/eg/slider.dart';
import '../../../../commons/widgets/eg/spinner.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/widgets/eg/text_area.dart';
import '../../../../commons/widgets/eg/text_field.dart';
import '../../../../commons/widgets/eg/toast.dart';
import '../../../../commons/widgets/eg/toggle.dart';
import '../../../../commons/widgets/eg/usage_bar.dart';
import '../../../../commons/widgets/eg/workbench_clock.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import 'design_sample_sections.dart';

/// Galeria dos campos: normal, preenchido, com ícone e sufixo, carregando,
/// erro, desabilitado; área de texto e lista de escolha.
class SampleFields extends StatefulWidget {
  const SampleFields({super.key});

  @override
  State<SampleFields> createState() => _SampleFieldsState();
}

class _SampleFieldsState extends State<SampleFields> {
  String? _model = 'opus';

  @override
  Widget build(BuildContext context) {
    return SampleWrap([
      const TextField(
        label: 'Nome da bancada',
        placeholder: 'ex.: loja/front',
        hint: 'Aparece na aba e no endereço.',
        width: 260,
      ),
      const TextField(
        label: 'Pasta',
        initialValue: '~/Documents/loja',
        icon: EgIcons.folder,
        mono: true,
        suffix: '4 itens',
        width: 260,
      ),
      const TextField(
        label: 'Buscando',
        initialValue: 'worktree',
        icon: EgIcons.search,
        loading: true,
        width: 260,
      ),
      const TextField(
        label: 'Com erro',
        initialValue: 'a/b',
        error: 'Esse nome já existe. Escolha outro.',
        width: 260,
      ),
      const TextField(
        label: 'Desabilitado',
        initialValue: 'somente leitura',
        enabled: false,
        width: 260,
      ),
      const TextArea(
        label: 'Prompt inicial',
        placeholder: 'O que o agente faz ao abrir?',
        width: 260,
      ),
      Select<String>(
        label: 'Modelo',
        icon: EgIcons.agent,
        width: 260,
        value: _model,
        onChanged: (v) => setState(() => _model = v),
        options: const [
          SelectOption('opus', 'Opus 5.5', desc: 'o mais capaz'),
          SelectOption('sonnet', 'Sonnet 5.5', desc: 'equilibrado'),
          SelectOption('haiku', 'Haiku 5.5', desc: 'rápido'),
          SelectOption('fable', 'Fable 5.2', desc: 'em breve'),
        ],
      ),
      const Select<String>(
        label: 'Desabilitado',
        width: 260,
        onChanged: null,
        options: [],
      ),
    ]);
  }
}

/// Galeria dos controles: marcar, opção, interruptor, passos e escolha de
/// visão, ligados, desligados e desabilitados.
class SampleControls extends StatefulWidget {
  const SampleControls({super.key});

  @override
  State<SampleControls> createState() => _SampleControlsState();
}

class _SampleControlsState extends State<SampleControls> {
  bool _check = true;
  bool _toggle = true;
  int _radio = 0;
  int _effort = 1;
  bool _auto = false;
  String _filter = 'todas';
  ViewSwitchMode _view = ViewSwitchMode.canvas;

  @override
  Widget build(BuildContext context) {
    Widget group(List<Widget> children) => Wrap(
      spacing: EgeonSpace.s6,
      runSpacing: EgeonSpace.s3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group([
          Checkbox(
            checked: _check,
            onChanged: (v) => setState(() => _check = v),
            label: const Text('Ligada'),
          ),
          Checkbox(
            checked: false,
            onChanged: (_) {},
            label: const Text('Vazia'),
          ),
          Checkbox(
            checked: false,
            indeterminate: true,
            onChanged: (_) {},
            label: const Text('Indeterminada'),
          ),
          Checkbox(
            checked: false,
            error: true,
            onChanged: (_) {},
            label: const Text('Com erro'),
          ),
          const Checkbox(
            checked: true,
            onChanged: null,
            label: Text('Desabilitada'),
          ),
        ]),
        const SizedBox(height: EgeonSpace.s3),
        group([
          for (var i = 0; i < 3; i++)
            Radio(
              checked: _radio == i,
              onSelected: () => setState(() => _radio = i),
              label: Text('Opção ${i + 1}'),
            ),
          const Radio(
            checked: true,
            onSelected: null,
            label: Text('Desabilitada'),
          ),
        ]),
        const SizedBox(height: EgeonSpace.s3),
        group([
          Toggle(
            on: _toggle,
            onChanged: (v) => setState(() => _toggle = v),
            label: const Text('Ligado'),
          ),
          Toggle(on: false, onChanged: (_) {}, label: const Text('Desligado')),
          const Toggle(on: true, onChanged: null, label: Text('Desabilitado')),
        ]),
        const SizedBox(height: EgeonSpace.s4),
        group([
          Slider(
            value: _effort,
            onChanged: (v) => setState(() => _effort = v),
            auto: _auto,
            onAutoChanged: (v) => setState(() => _auto = v),
            width: 280,
          ),
          const Slider(value: 2, onChanged: null, width: 280),
        ]),
        const SizedBox(height: EgeonSpace.s4),
        group([
          ViewSwitch(value: _view, onChanged: (v) => setState(() => _view = v)),
          SegmentedControl<String>(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            options: const [
              SegmentOption('todas', 'Todas'),
              SegmentOption('ativas', 'Ativas'),
            ],
          ),
          const SegmentedControl<String>(
            value: 'a',
            onChanged: null,
            options: [
              SegmentOption('a', 'Log'),
              SegmentOption('b', 'Por agente'),
            ],
          ),
        ]),
      ],
    );
  }
}

/// Galeria do estado do agente: os nove estados em ponto, etiqueta, contador,
/// cronômetro, anel de contexto, halo de atenção e spinner.
class SampleStatus extends StatelessWidget {
  const SampleStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    Widget caption(String t) => Text(
      t,
      style: EgeonType.monoMeta.copyWith(
        color: c.textMuted,
        decoration: TextDecoration.none,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EgeonSpace.s6,
          runSpacing: EgeonSpace.s3,
          children: [
            for (final s in Status.values)
              SizedBox(
                width: 190,
                child: StatusDot(s, animated: true, showLabel: true),
              ),
          ],
        ),
        const SizedBox(height: EgeonSpace.s3),
        Wrap(
          spacing: EgeonSpace.s2,
          runSpacing: EgeonSpace.s2,
          children: [
            const Badge('neutro'),
            const Badge('contorno', tone: BadgeTone.outline, showIcon: false),
            for (final s in Status.values)
              Badge(s.label, tone: BadgeTone.status(s)),
          ],
        ),
        const SizedBox(height: EgeonSpace.s3),
        Wrap(
          spacing: EgeonSpace.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Counter(3),
            const Counter(2, tone: CounterTone.attention),
            Counter(4, tone: CounterTone.waiting, icon: EgIcons.hourglass),
            const Counter(120, tone: CounterTone.attention),
            const AttentionRing(
              round: true,
              child: StatusDot(Status.attention),
            ),
            const Spinner(),
            const Spinner(size: 20),
            const ContextRing(0.42),
            const ContextRing(0.85),
            const ContextRing(0.97),
            const ContextRing(null),
          ],
        ),
        const SizedBox(height: EgeonSpace.s3),
        Wrap(
          spacing: EgeonSpace.s6,
          runSpacing: EgeonSpace.s3,
          children: [
            const WorkbenchClock(
              work: Duration(minutes: 12, seconds: 4),
              you: Duration(seconds: 48),
              active: ClockPhase.work,
            ),
            const WorkbenchClock(work: Duration(minutes: 3, seconds: 20)),
            const WorkbenchClock(error: Duration(seconds: 12)),
            const WorkbenchClock(
              work: Duration(minutes: 12, seconds: 4),
              you: Duration(seconds: 48),
              compact: true,
            ),
            caption('← compacto: só a fase que manda'),
          ],
        ),
      ],
    );
  }
}

/// Galeria de identidade e texto: nome na cor, pastilhas, rótulo de aresta,
/// código, diff e consumo.
class SampleContent extends StatelessWidget {
  const SampleContent({super.key});

  static const _code = '''// abre a bancada
const bench = workspace.open('api');
if (bench.ready) {
  await bench.send(42, true);
}''';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EgeonSpace.s4,
          runSpacing: EgeonSpace.s2,
          children: [
            for (final i in Identity.values) AgentName(i.name, identity: i),
            const AgentName(
              'front',
              identity: Identity.sky,
              address: 'loja/front',
              size: AgentNameSize.lg,
            ),
          ],
        ),
        const SizedBox(height: EgeonSpace.s3),
        const Wrap(
          spacing: EgeonSpace.s2,
          runSpacing: EgeonSpace.s2,
          children: [
            InfoPill('Opus 5.5', icon: EgIcons.agent),
            InfoPill('medium', icon: EgIcons.gauge),
            InfoPill('61% ctx', icon: EgIcons.layers, title: 'Contexto em uso'),
            InfoPill(
              'precisa de você',
              icon: EgIcons.hand,
              tone: InfoPillTone.attention,
            ),
            EdgeLabel(used: 3, max: 5),
            EdgeLabel(max: null),
            EdgeLabel(used: 5, max: 5, state: EdgeLabelState.spent),
            EdgeLabel(used: 1, max: 2, state: EdgeLabelState.selected),
          ],
        ),
        const SizedBox(height: EgeonSpace.s4),
        const SizedBox(
          width: 520,
          child: CodeBlock(_code, filename: 'bench.ts', lang: 'ts'),
        ),
        const SizedBox(height: EgeonSpace.s4),
        for (final mode in DiffMode.values) ...[
          SizedBox(
            width: 640,
            child: DiffView(
              filename: 'src/bench.dart',
              added: 2,
              removed: 1,
              mode: mode,
              rows: const [
                DiffRow(
                  left: DiffCell(10, 'final name = bench.name;'),
                  right: DiffCell(10, 'final name = bench.name;'),
                ),
                DiffRow(
                  left: DiffCell(
                    11,
                    'open([-slow]Bench(name));',
                    sign: DiffSign.removed,
                  ),
                  right: DiffCell(
                    11,
                    'open([+fast]Bench(name));',
                    sign: DiffSign.added,
                  ),
                ),
                DiffRow(
                  right: DiffCell(12, 'notify(name);', sign: DiffSign.added),
                ),
                DiffRow.fold('⋯ 12 linhas sem mudança'),
              ],
            ),
          ),
          const SizedBox(height: EgeonSpace.s3),
        ],
        const SizedBox(
          width: 520,
          child: UsageBar(
            title: 'Consumo da bancada',
            totalLabel: 'US\$ 1,19',
            segments: [
              UsageSegment(
                tariff: Tariff.output,
                value: 50,
                display: 'US\$ 0,60',
                tokens: '14,1K',
              ),
              UsageSegment(
                tariff: Tariff.input,
                value: 20,
                display: 'US\$ 0,24',
                tokens: '31K',
              ),
              UsageSegment(
                tariff: Tariff.cacheWrite,
                value: 15,
                display: 'US\$ 0,18',
                tokens: '9K',
              ),
              UsageSegment(
                tariff: Tariff.cacheRead,
                value: 10,
                display: 'US\$ 0,17',
                tokens: '220K',
              ),
            ],
            max: 120,
          ),
        ),
      ],
    );
  }
}

/// Galeria dos avisos: faixas fixas (Banner) e os cinco tons do Toast.
class SampleNotices extends StatelessWidget {
  const SampleNotices({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tone in BannerTone.values) ...[
          SizedBox(
            width: 520,
            child: NoticeBanner(
              tone: tone,
              action: Button(
                label: 'Ver',
                size: ButtonSize.sm,
                onPressed: () {},
              ),
              onDismiss: () {},
              child: Text(
                'Aviso de tom ${tone.name}: o que houve e o que fazer.',
              ),
            ),
          ),
          const SizedBox(height: EgeonSpace.s2),
        ],
        const SizedBox(height: EgeonSpace.s3),
        Wrap(
          spacing: EgeonSpace.s3,
          runSpacing: EgeonSpace.s3,
          children: [
            for (final tone in ToastTone.values)
              Toast(
                tone: tone,
                title: 'tom ${tone.name}',
                description: 'Descrição em uma frase.',
                agent: const Person('maestro', identity: Identity.iris),
                onDismiss: () {},
              ),
          ],
        ),
      ],
    );
  }
}
