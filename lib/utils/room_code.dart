import 'package:flutter/services.dart';

import '../config.dart';

/// Caractères autorisés dans un code de salon (identiques à pr_random_code côté SQL).
const roomCodeChars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Met en majuscules, retire tout ce qui n'est pas un caractère autorisé
/// et coupe à la bonne longueur.
String normalizeRoomCode(String input) {
  final upper = input.toUpperCase();
  final buffer = StringBuffer();
  for (final ch in upper.split('')) {
    if (roomCodeChars.contains(ch)) buffer.write(ch);
    if (buffer.length == AppConfig.codeLength) break;
  }
  return buffer.toString();
}

bool isValidRoomCode(String code) =>
    code.length == AppConfig.codeLength && normalizeRoomCode(code) == code;

class RoomCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = normalizeRoomCode(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
