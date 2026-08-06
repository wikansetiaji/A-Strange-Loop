import 'package:shared_preferences/shared_preferences.dart';
import 'package:a_strange_loop/constants/hardcover_config.dart' as prod;
import 'package:a_strange_loop/constants/hardcover_config_qa.dart' as qa;

class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  bool isQaMode = false;

  String get metaColl => isQaMode ? 'meta_qa' : 'meta';
  String get sessionsColl => isQaMode ? 'sessions_qa' : 'sessions';

  String get hardcoverApiKey =>
      isQaMode ? qa.hardcoverApiKeyQa : prod.hardcoverApiKey;
  String get hardcoverUserId =>
      isQaMode ? qa.hardcoverUserIdQa : prod.hardcoverUserId.toString();
  String get hardcoverEndpoint => prod.hardcoverApiEndpoint;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isQaMode = prefs.getBool('qa_mode') ?? false;
  }

  Future<void> setQaMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qa_mode', v);
    isQaMode = v;
  }
}
