import 'package:flutter/material.dart';

/// 与现有 Web 后台一致的设计语言：
/// 以中性 ink 灰阶为主，陶土 accent 作为强调色，圆角 + 极简描边卡片。
class AppColors {
  // 中性灰阶（界面与文字主色）。
  static const ink50 = Color(0xFFFAFAFA);
  static const ink100 = Color(0xFFF4F4F5);
  static const ink200 = Color(0xFFE4E4E7);
  static const ink300 = Color(0xFFD4D4D8);
  static const ink400 = Color(0xFFA1A1AA);
  static const ink500 = Color(0xFF71717A);
  static const ink600 = Color(0xFF52525B);
  static const ink700 = Color(0xFF3F3F46);
  static const ink800 = Color(0xFF27272A);
  static const ink900 = Color(0xFF18181B);
  static const ink950 = Color(0xFF09090B);

  // 陶土暖色强调，用于高亮 / 主要操作点缀。
  static const accent50 = Color(0xFFFDF4EF);
  static const accent100 = Color(0xFFFBE6DA);
  static const accent400 = Color(0xFFE6815A);
  static const accent500 = Color(0xFFDB6238);
  static const accent600 = Color(0xFFC44D28);
  static const accent700 = Color(0xFFA33D22);

  // 状态色。
  static const amber400 = Color(0xFFFBBF24);
  static const amber50 = Color(0xFFFFFBEB);
  static const amber700 = Color(0xFFB45309);
  static const emerald500 = Color(0xFF10B981);
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const rose600 = Color(0xFFE11D48);
  static const rose50 = Color(0xFFFFF1F2);
  static const rose200 = Color(0xFFFECDD3);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.ink900,
      primary: AppColors.ink900,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.ink50,
    fontFamily: 'PingFang SC',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink900,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.white,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink900,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: 'PingFang SC',
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.ink100, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: const TextStyle(color: AppColors.ink400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.ink200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.ink200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.ink900, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.ink300,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink700,
        side: const BorderSide(color: AppColors.ink200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink900,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 极简描边卡片，对应 Web 端 `.card`（白底、1px ink-200 描边、柔和阴影）。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14181B1B),
            blurRadius: 14,
            offset: Offset(0, 4),
            spreadRadius: -8,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// ink-900 圆形品牌图标（白色话筒），对应 Web 端 logo。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36, this.radius = 999});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.mic_none_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}
