import 'dart:io';

import 'package:crypto/crypto.dart';

Future<bool> verifySha256(File file, String expectedHex) async {
  if (!await file.exists()) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().toLowerCase() == expectedHex.toLowerCase();
}
