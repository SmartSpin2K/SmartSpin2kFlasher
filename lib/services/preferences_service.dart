import 'package:shared_preferences/shared_preferences.dart';

/// Persists user preferences across app sessions.
class PreferencesService {
  static const _keyThemeMode = 'theme_mode';
  static const _keyFirmwareSource = 'firmware_source';
  static const _keySelectedReleaseTag = 'selected_release_tag';
  static const _keyLocalFirmwarePath = 'local_firmware_path';
  static const _keySelectedPort = 'selected_port';

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Theme
  static String get themeMode => _prefs.getString(_keyThemeMode) ?? 'dark';
  static Future<void> setThemeMode(String mode) =>
      _prefs.setString(_keyThemeMode, mode);

  // Firmware source ('github' or 'local')
  static String get firmwareSource =>
      _prefs.getString(_keyFirmwareSource) ?? 'github';
  static Future<void> setFirmwareSource(String source) =>
      _prefs.setString(_keyFirmwareSource, source);

  // Selected release tag
  static String? get selectedReleaseTag =>
      _prefs.getString(_keySelectedReleaseTag);
  static Future<void> setSelectedReleaseTag(String? tag) => tag != null
      ? _prefs.setString(_keySelectedReleaseTag, tag)
      : _prefs.remove(_keySelectedReleaseTag);

  // Local firmware path
  static String? get localFirmwarePath =>
      _prefs.getString(_keyLocalFirmwarePath);
  static Future<void> setLocalFirmwarePath(String? path) => path != null
      ? _prefs.setString(_keyLocalFirmwarePath, path)
      : _prefs.remove(_keyLocalFirmwarePath);

  // Selected serial port
  static String? get selectedPort => _prefs.getString(_keySelectedPort);
  static Future<void> setSelectedPort(String? port) => port != null
      ? _prefs.setString(_keySelectedPort, port)
      : _prefs.remove(_keySelectedPort);
}
