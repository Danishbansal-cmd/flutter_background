import 'package:shared_preferences/shared_preferences.dart';

class DataStorage {
  static SharedPreferences? _preferences;

  static Future<SharedPreferences> get _instance async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  static Future<SharedPreferences> getInstace() async{
    return await _instance;
  }
}
