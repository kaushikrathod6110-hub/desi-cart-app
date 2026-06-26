import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool isDarkMode = false;
  bool notifications = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool("darkMode") ?? false;
      notifications = prefs.getBool("notifications") ?? true;
    });
  }

  Future<void> saveSettings(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _card(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Dark Mode"),
                  subtitle: const Text("Turn the app theme to dark mode"),
                  value: isDarkMode,
                  onChanged: (value) async {
                    setState(() => isDarkMode = value);
                    await saveSettings("darkMode", value);
                    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Notifications"),
                  subtitle: const Text("Show notification badge on home page"),
                  value: notifications,
                  onChanged: (value) async {
                    setState(() => notifications = value);
                    await saveSettings("notifications", value);
                  },
                ),
              ],
            ),
          ),
          _card(
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text("About"),
              subtitle: Text("Desi Cart settings for theme and notification badge"),
            ),
          ),
        ],
      ),
    );
  }
}