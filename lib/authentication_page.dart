import 'package:flutter/material.dart';

import 'login_page.dart';
import 'register_page.dart';

class AuthenticationPage extends StatefulWidget {
  const AuthenticationPage({super.key, this.onAuthenticated});

  final VoidCallback? onAuthenticated;

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _showLogin
          ? LoginPage(
              key: const ValueKey<String>('auth_login'),
              onAuthenticated: widget.onAuthenticated,
              onSwitchToRegister: () {
                setState(() {
                  _showLogin = false;
                });
              },
            )
          : RegisterPage(
              key: const ValueKey<String>('auth_register'),
              onAuthenticated: widget.onAuthenticated,
              onSwitchToLogin: () {
                setState(() {
                  _showLogin = true;
                });
              },
            ),
    );
  }
}
