import 'package:fav/core/persistence/app_database.dart'
    show resolveDbEncryptionKey;
import 'package:fav/core/persistence/secure_store.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Name of the Hive box holding user preferences.
const String preferencesBoxName = 'preferences';

/// Opens the encrypted `preferences` box. Hive must already be initialized.
Future<Box<Map<dynamic, dynamic>>> openPreferencesBox(SecureStore store) async {
  final key = await resolveDbEncryptionKey(store);
  return Hive.openBox<Map<dynamic, dynamic>>(
    preferencesBoxName,
    encryptionCipher: HiveAesCipher(key),
  );
}
