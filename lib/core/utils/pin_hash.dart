import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Returns the SHA-256 hex digest of [pin].
///
/// The raw PIN never leaves the device; only this hash is stored and sent.
/// A 4-digit PIN space (10 000 values) is trivially rainbow-table-reversible
/// regardless of hashing, so no salt is used — hashing here signals intent
/// and prevents accidental plaintext logging.
String hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();
