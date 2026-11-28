import 'package:flutter/widgets.dart';

/// Avisa a altura que o filho tem depois de cada quadro: o composer flutua, e a
/// lista de mensagens guarda esse espaço embaixo para a última mensagem ficar
/// acima dele.
class SizeReporter extends StatefulWidget {
  const SizeReporter({required this.onHeight, required this.child, super.key});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<SizeReporter> createState() => _SizeReporterState();
}

class _SizeReporterState extends State<SizeReporter> {
  double _last = -1;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (box.size.height != _last) {
        _last = box.size.height;
        widget.onHeight(_last);
      }
    });
    return widget.child;
  }
}
