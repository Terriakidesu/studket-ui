import 'package:flutter/material.dart';

class StudketAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudketAppBar({
    super.key,
    required this.title,
    this.titleStyle,
    this.titleSpacing = NavigationToolbar.kMiddleSpacing,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
  });

  final String title;
  final TextStyle? titleStyle;
  final double titleSpacing;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final double? scrolledUnderElevation;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      surfaceTintColor: Colors.transparent,
      elevation: elevation,
      scrolledUnderElevation: scrolledUnderElevation,
      titleSpacing: titleSpacing,
      title: Text(
        title,
        style: titleStyle ?? const TextStyle(fontWeight: FontWeight.w700),
      ),
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
}
