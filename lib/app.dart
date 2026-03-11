import 'package:flutter/material.dart';

import 'app_entry_page.dart';
import 'app_theme_controller.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color _seedGreen = Color(0xFF2F7D32);

  ColorScheme _buildColorScheme(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF7FD68B),
        onPrimary: Color(0xFF0C2B13),
        primaryContainer: Color(0xFF173922),
        onPrimaryContainer: Color(0xFFA8F1B0),
        secondary: Color(0xFF8CC9FF),
        onSecondary: Color(0xFF06263F),
        secondaryContainer: Color(0xFF153450),
        onSecondaryContainer: Color(0xFFC2E4FF),
        tertiary: Color(0xFFFFC785),
        onTertiary: Color(0xFF3A2100),
        tertiaryContainer: Color(0xFF5A3A10),
        onTertiaryContainer: Color(0xFFFFDEB8),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF0E1411),
        onSurface: Color(0xFFE4ECE3),
        surfaceContainerLowest: Color(0xFF090D0B),
        surfaceContainerLow: Color(0xFF151C18),
        surfaceContainer: Color(0xFF1A221E),
        surfaceContainerHigh: Color(0xFF212A25),
        surfaceContainerHighest: Color(0xFF2A342E),
        onSurfaceVariant: Color(0xFFBBCBBE),
        outline: Color(0xFF859489),
        outlineVariant: Color(0xFF3B4A40),
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),
        inverseSurface: Color(0xFFE4ECE3),
        onInverseSurface: Color(0xFF1A211D),
        inversePrimary: Color(0xFF2F7D32),
        surfaceTint: Color(0xFF7FD68B),
      );
    }
    return ColorScheme.fromSeed(
      seedColor: _seedGreen,
      brightness: brightness,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final ColorScheme colorScheme = _buildColorScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: colorScheme.outlineVariant,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData.fromDefaults(
        secondaryColor: colorScheme.primaryContainer,
        brightness: brightness,
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (BuildContext context, _) {
        return MaterialApp(
          title: 'Studket',
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: AppThemeController.instance.themeMode,
          home: const AppEntryPage(),
        );
      },
    );
  }
}
