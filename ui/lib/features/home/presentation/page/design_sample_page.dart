import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../widgets/design_sample_components.dart';
import '../widgets/design_sample_controls.dart';
import '../widgets/design_sample_sections.dart';

/// Amostra do design system, só em modo dev (`EGEON_FLAVOR=dev` com
/// `EGEON_DESIGN_SAMPLE=1`), para conferir lado a lado com o DS publicado.
class DesignSamplePage extends StatefulWidget {
  const DesignSamplePage({super.key});

  @override
  State<DesignSamplePage> createState() => _DesignSamplePageState();
}

class _DesignSamplePageState extends State<DesignSamplePage> {
  /// Menu, popover, diálogo e toast precisam de um `Overlay` acima.
  late final OverlayEntry _entry = OverlayEntry(builder: _content);

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);

  Widget _content(BuildContext context) {
    final c = context.eg;
    return ColoredBox(
      color: c.graphite,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EgeonSpace.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Egeon — design system',
              style: EgeonType.display.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: EgeonSpace.s8),
            const SampleSection('Superfícies', SampleSurfaces()),
            const SampleSection('Texto', SampleTextColors()),
            const SampleSection('Estados', SampleStates()),
            const SampleSection('Identidades', SampleIdentities()),
            const SampleSection('Escala tipográfica', SampleTypeScale()),
            const SampleSection('Vidro sobre grade', SampleGlassOverGrid()),
            const SampleSection('Glifos de risco', SampleGlyphs()),
            const SampleSection('Ícones', SampleIcons()),
            const SampleSection('Botões', SampleButtons()),
            const SampleSection('Flutuantes', SampleFloating()),
            const SampleSection('Campos', SampleFields()),
            const SampleSection('Controles', SampleControls()),
            const SampleSection('Estado do agente', SampleStatus()),
            const SampleSection('Identidade e texto', SampleContent()),
            const SampleSection('Avisos', SampleNotices()),
          ],
        ),
      ),
    );
  }
}
