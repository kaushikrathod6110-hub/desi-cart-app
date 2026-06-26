import 'package:flutter/material.dart';

import 'package:my_app/admin/admin_Notification_page.dart';
import 'package:my_app/admin/all_users_page.dart';
import 'package:my_app/admin/app_configuration_page.dart';
import 'package:my_app/admin/changePassword_page.dart';
import 'package:my_app/admin/security_settings_page.dart';
import 'package:my_app/admin/system_info_page.dart';

class AdminSettingPage extends StatefulWidget{
  const AdminSettingPage({super.key});

  @override
  State<AdminSettingPage> createState() => _AdminSettingPageState();
}

class _AdminSettingPageState extends State<AdminSettingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Admin Settings"),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 760 ? 760.0 : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    _sectionTitle("User Management"),
                    _settingsTile(
                      icons: Icons.people,
                      title: "Manage Users",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> AllUsersPage()),
                        );
                      },
                    ),

                    _sectionTitle("System Settings"),
                    _settingsTile(
                      icons: Icons.settings,
                      title: "App Configuration",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> AppConfigurationPage()),
                        );
                      },
                    ),
                    _settingsTile(
                      icons: Icons.notifications,
                      title: "Notifications",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> AdminNotificationPage()),
                        );
                      },
                    ),

                    _sectionTitle("Security"),
                    _settingsTile(
                      icons: Icons.lock,
                      title: "Security Settings",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> SecuritySettingsPage()),
                        );
                      },
                    ),
                    _settingsTile(
                      icons: Icons.password,
                      title: "Change Admin Password",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> ChangePasswordPage()),
                        );
                      },
                    ),

                    /*_sectionTitle("Data & System"),
            _settingsTile(
              icons: Icons.backup,
              title: "Data & Backup",
              onTap: (){

              },
            ),*/
                    _settingsTile(
                      icons: Icons.info_outline,
                      title: "System Info",
                      onTap: (){
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context)=> SystemInfoPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String text){
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icons,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icons),
      title: Text(title),
      trailing: Icon(Icons.arrow_forward_ios, size: 16,),
      onTap: onTap,
    );
  }
}