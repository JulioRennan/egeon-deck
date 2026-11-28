import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/bench_color_grid.dart';
import '../../../../commons/widgets/form_dialog.dart';

/// A grade das 12 cores da bancada, numa janela. Devolve o nome que o core
/// grava (o mapa provisório de `BenchIdentity`), ou `null` se fechou.
Future<String?> showColorPalette(
  BuildContext context, {
  required String benchName,
  String? current,
}) => showFormDialog<String>(
  context,
  width: 300,
  builder: (_, close) => FormDialogBody(
    title: 'Cor da bancada',
    actions: [FormDialogButton('Cancelar', onTap: close)],
    child: BenchColorGrid(
      benchName: benchName,
      showTitle: false,
      current: BenchIdentity.of(current),
      onPick: (identity) => close(BenchIdentity.nameOf(identity)),
    ),
  ),
);
