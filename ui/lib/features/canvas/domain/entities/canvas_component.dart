/// Um componente salvo como o menu do terminal de agente o mostra: o nome e a
/// linha de baixo ("CLI · modelo · esforço", o que o componente tiver).
class CanvasComponent {
  const CanvasComponent(this.name, {this.meta});

  final String name;
  final String? meta;
}
