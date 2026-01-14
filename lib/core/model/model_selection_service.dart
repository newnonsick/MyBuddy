import 'package:shared_preferences/shared_preferences.dart';

class ModelSelectionService {
  static const String _selectedIdKey = 'mybuddy.selected_model_id.v1';
  static const String _lastUsedIdKey = 'mybuddy.last_used_model_id.v1';

  Future<String?> loadSelectedModelId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_selectedIdKey);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> saveSelectedModelId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    final v = (id ?? '').trim();
    if (v.isEmpty) {
      await prefs.remove(_selectedIdKey);
      return;
    }
    await prefs.setString(_selectedIdKey, v);
  }

  Future<String?> loadLastUsedModelId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_lastUsedIdKey);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> saveLastUsedModelId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    final v = (id ?? '').trim();
    if (v.isEmpty) {
      await prefs.remove(_lastUsedIdKey);
      return;
    }
    await prefs.setString(_lastUsedIdKey, v);
  }
}
