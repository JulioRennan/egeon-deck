/// Uma tecnologia do projeto, para o selo da barra lateral (`Rs`, `TS`…).
/// Detectar a stack é do core Rust (pelos arquivos do repositório); até lá o
/// projeto não traz nenhuma.
class StackBadge {
  const StackBadge({required this.abbr, required this.name});

  final String abbr;
  final String name;
}
