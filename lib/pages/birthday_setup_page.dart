import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/time_integrity_service.dart';
import '../services/storage_service.dart';
import '../services/haptic_service.dart';

/// 生日设置页（仅首次启动）
/// 纯黑背景 + 白色文字 + 日期选择器 + 确认按钮
/// 确认后永久不可修改
class BirthdaySetupPage extends StatefulWidget {
  final VoidCallback onConfirmed;

  const BirthdaySetupPage({super.key, required this.onConfirmed});

  @override
  State<BirthdaySetupPage> createState() => _BirthdaySetupPageState();
}

class _BirthdaySetupPageState extends State<BirthdaySetupPage>
    with SingleTickerProviderStateMixin {
  late DateTime _selectedDate;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year - 25, now.month, now.day);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    // 生日设置是一次性的起点写入 —— tampered 时拒绝，避免把错误起点永久固化
    if (TimeIntegrityService.instance.tampered) {
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('检测到系统时间异常，请修正后再确认'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    HapticService.checkInToggle();
    try {
      await StorageService.instance.saveBirthday(_selectedDate);
    } on TimeTamperedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('检测到系统时间异常，请修正后再确认'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // 标题
                const Text(
                  '你的生日',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '确认后不可修改',
                  style: TextStyle(
                    color: Color(0x55FFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                  ),
                ),

                const Spacer(flex: 2),

                // 日期选择器
                SizedBox(
                  height: 200,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.dark,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: _selectedDate,
                      minimumDate: DateTime(1900),
                      maximumDate: DateTime.now(),
                      onDateTimeChanged: (date) {
                        _selectedDate = date;
                        HapticService.dateSlide();
                      },
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // 确认按钮
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _confirm,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '确认',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
