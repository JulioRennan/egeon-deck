import 'dart:typed_data';

import '../entities/terminal_effect.dart';
import '../entities/terminal_frame.dart';
import '../entities/terminal_info.dart';
import '../entities/terminal_key.dart';
import '../entities/terminal_pointer.dart';

abstract interface class TerminalRepository {
  Future<List<TerminalInfo>> list();

  /// Cria um terminal no core. Sem tamanho: a UI informa o dela em seguida.
  Future<TerminalInfo> create({String? cwd});

  /// A tela do terminal [nodeId]. O primeiro quadro traz a tela inteira.
  Stream<TerminalFrame> watch(String nodeId);

  Future<void> sendKey(String nodeId, TerminalKey key);

  /// Texto já composto pelo método de entrada (acento, ç): vai como está.
  Future<void> sendText(String nodeId, String text);

  /// ⌘V: o core embrulha em bracketed paste quando o programa pediu.
  Future<void> paste(String nodeId, String text);

  Future<void> resize(String nodeId, int columns, int rows);

  /// O gesto do mouse, cru; o core decide o que ele significa.
  Future<void> sendPointer(String nodeId, TerminalPointer pointer);

  /// Rolar a vista pela barra de rolagem ou por atalho.
  Future<void> scroll(String nodeId, TerminalScroll scroll);

  /// ⌘A.
  Future<void> selectAll(String nodeId);

  /// ⌘C: o texto da seleção (linhas quebradas juntadas); vazio ou nulo sem
  /// seleção.
  Future<String?> copy(String nodeId);

  /// Beep e área de transferência pedidos pelo programa.
  Stream<TerminalEffect> effects(String nodeId);

  /// Resposta a um [ClipboardRequest]: o texto da área de transferência.
  Future<void> sendClipboard(String nodeId, String text);

  /// Há link (arquivo ou endereço) na célula [x], [y]? O ⌘-clique abre; a UI só
  /// mostra a mão por cima.
  Future<bool> linkHover(String nodeId, double x, double y);

  /// Arquivos soltos no terminal; o core monta o texto que vai ao agente.
  Future<void> dropFiles(String nodeId, List<String> paths);

  /// Imagem solta sem arquivo (TIFF já convertido para PNG).
  Future<void> dropImage(String nodeId, Uint8List png);
}
