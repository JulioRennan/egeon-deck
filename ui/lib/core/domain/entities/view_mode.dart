/// O modo de olhar a bancada. Os nomes são formato de arquivo e parâmetro de
/// rota do core Rust.
enum ViewMode {
  canvas('canvas', 'Canvas'),
  chat('chat', 'Chat');

  const ViewMode(this.wire, this.label);

  final String wire;
  final String label;

  /// Ausente ou desconhecido abre como canvas: bancada gravada com um modo que
  /// saiu do app não pode derrubar a carga.
  static ViewMode fromWire(Object? raw) => values.firstWhere(
    (mode) => mode.wire == raw,
    orElse: () => ViewMode.canvas,
  );
}
