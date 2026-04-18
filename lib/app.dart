import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'pages/birthday_setup_page.dart';
import 'pages/home_page.dart';

/// App 根组件 — 管理启动流程与生命周期
class TrailApp extends StatefulWidget {
  const TrailApp({super.key});

  @override
  State<TrailApp> createState() => _TrailAppState();
}

class _TrailAppState extends State<TrailApp> with WidgetsBindingObserver {
  bool _hasBirthday = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasBirthday = StorageService.instance.hasBirthday;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 生命周期恢复时不再自动把「活着」节点打卡为完成。
  }

  void _onBirthdayConfirmed() {
    setState(() => _hasBirthday = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '迹点',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: _hasBirthday
          ? const HomePage()
          : BirthdaySetupPage(onConfirmed: _onBirthdayConfirmed),
    );
  }
}
