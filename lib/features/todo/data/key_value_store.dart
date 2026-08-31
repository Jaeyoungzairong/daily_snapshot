import 'package:shared_preferences/shared_preferences.dart';

/// 로컬 key-value 저장소에 대한 최소 추상화. [TodoRepository]가 실제 저장 수단(현재는
/// SharedPreferencesAsync)에 직접 묶이지 않게 해서, 테스트에서 인메모리 구현으로 손쉽게
/// 대체할 수 있도록 한다.
abstract class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore() : _preferences = SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) => _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
