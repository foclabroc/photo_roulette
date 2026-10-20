import 'package:flutter_test/flutter_test.dart';
import 'package:photo_roulette/utils/room_code.dart';

void main() {
  test('normalise le code : majuscules, caractères ambigus retirés, 5 max', () {
    expect(normalizeRoomCode('ab c-d9xyz'), 'ABCD9');
    expect(normalizeRoomCode('o0i1l'), '');
  });

  test('valide uniquement les codes complets', () {
    expect(isValidRoomCode('ABCD9'), isTrue);
    expect(isValidRoomCode('ABC'), isFalse);
    expect(isValidRoomCode('abcd9'), isFalse);
  });
}
