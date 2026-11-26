import 'package:egeon_deck/core/adapters/path_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('macOS e Linux', () {
    final picker = SystemPathPicker(home: '/Users/x');

    test('a pasta pessoal vira ~', () {
      expect(picker.abbreviate('/Users/x'), '~');
      expect(picker.abbreviate('/Users/x/proj/'), '~/proj');
      expect(picker.abbreviate('/Users/xy/proj'), '/Users/xy/proj');
      expect(picker.abbreviate('/opt/proj'), '/opt/proj');
      expect(picker.abbreviate(null), isNull);
    });

    test('o ~ volta a ser a pasta pessoal', () {
      expect(picker.expand('~'), '/Users/x');
      expect(picker.expand('~/proj'), '/Users/x/proj');
      expect(picker.expand('/opt/proj'), '/opt/proj');
    });
  });

  group('Windows', () {
    final picker = SystemPathPicker(home: r'C:\Users\x');

    test('a pasta pessoal vira ~, sem ligar para maiúsculas', () {
      expect(picker.abbreviate(r'C:\Users\x'), '~');
      expect(picker.abbreviate(r'c:\users\X\proj\'), '~/proj');
      expect(picker.abbreviate(r'C:\Users\x\a\b'), '~/a/b');
    });

    test('fora da pasta pessoal fica como veio', () {
      expect(picker.abbreviate(r'C:\Users\xy\proj'), r'C:\Users\xy\proj');
      expect(picker.abbreviate(r'D:\proj'), r'D:\proj');
    });

    test('o ~ volta com barras invertidas', () {
      expect(picker.expand('~'), r'C:\Users\x');
      expect(picker.expand('~/a/b'), r'C:\Users\x\a\b');
      expect(picker.expand(r'D:\proj'), r'D:\proj');
    });
  });
}
