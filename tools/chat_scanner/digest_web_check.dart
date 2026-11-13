import 'dart:typed_data';

import 'package:jobmate/features/chat/chat_file_digest.dart';

void main() {
  final values = <Uint8List, String>{
    Uint8List(0):
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    Uint8List.fromList('abc'.codeUnits):
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    Uint8List.fromList(List.filled(1000000, 97)):
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
  };
  for (final entry in values.entries) {
    if (chatFileDigest(entry.key) != entry.value) {
      throw StateError('SHA-256 mismatch');
    }
  }
  // ignore: avoid_print -- standalone offline verification command.
  print('PASS: JavaScript SHA-256 empty/abc/million-a vectors');
}
