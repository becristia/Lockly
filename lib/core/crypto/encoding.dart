import 'dart:convert';
import 'dart:typed_data';

String b64(Uint8List value) => base64Encode(value);

Uint8List fromB64(String value) => Uint8List.fromList(base64Decode(value));
