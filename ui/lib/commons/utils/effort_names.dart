/// Os níveis de esforço em português (a v3: baixo, médio, alto, máximo). O
/// valor que vai ao core continua o do CLI (`low`…`max`): só o rótulo muda.
/// Nível que o app não conhece passa como veio; as reticências do "ainda não
/// assentou" (`high…`) ficam no fim.
String effortName(String level) {
  const pending = '…';
  final base = level.endsWith(pending)
      ? level.substring(0, level.length - pending.length)
      : level;
  final name = switch (base) {
    'low' => 'baixo',
    'medium' => 'médio',
    'high' => 'alto',
    'xhigh' => 'extra alto',
    'max' => 'máximo',
    _ => base,
  };
  return level.endsWith(pending) ? '$name$pending' : name;
}
