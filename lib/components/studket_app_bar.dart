import 'package:flutter/material.dart';

class StudketAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudketAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.titleStyle,
    this.titleSpacing = NavigationToolbar.kMiddleSpacing,
    this.bottom,
    this.elevation,
    this.scrolledUnderElevation,
    this.actions,
  });

  final String title;
  final Widget? titleWidget;
  final TextStyle? titleStyle;
  final double titleSpacing;
  final PreferredSizeWidget? bottom;
  final double? elevation;
  final double? scrolledUnderElevation;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = Theme.of(context).colorScheme.primary;
    final Color foregroundColor = Theme.of(context).colorScheme.onPrimary;

    return AppBar(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      surfaceTintColor: backgroundColor,
      elevation: elevation,
      scrolledUnderElevation: scrolledUnderElevation,
      titleSpacing: titleSpacing,
      title:
          titleWidget ??
          Text(
            title,
            style:
                titleStyle ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: foregroundColor,
                ),
          ),
      iconTheme: IconThemeData(color: foregroundColor),
      actionsIconTheme: IconThemeData(color: foregroundColor),
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 0),
  );
}
