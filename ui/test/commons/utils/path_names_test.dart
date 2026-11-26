import 'package:egeon_deck/commons/utils/path_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o último componente serve aos dois separadores', () {
    expect(lastPathComponent('/Users/x/proj'), 'proj');
    expect(lastPathComponent('/Users/x/proj/'), 'proj');
    expect(lastPathComponent(r'C:\Users\x\proj'), 'proj');
    expect(lastPathComponent(r'C:\Users\x\proj\'), 'proj');
    expect(lastPathComponent('C:/Users/x/proj'), 'proj');
    expect(lastPathComponent('/'), '');
    expect(lastPathComponent(''), '');
  });

  test('caminho do disco, de unidade e de rede; endereço não', () {
    expect(looksLikePath('~/a'), isTrue);
    expect(looksLikePath('/a'), isTrue);
    expect(looksLikePath(r'C:\a'), isTrue);
    expect(looksLikePath('C:/a'), isTrue);
    expect(looksLikePath(r'\\servidor\a'), isTrue);
    expect(looksLikePath('https://exemplo.com'), isFalse);
    expect(looksLikePath('exemplo.com'), isFalse);
  });
}
