import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.onAuthenticated,
    this.onSwitchToRegister,
  });

  final VoidCallback? onAuthenticated;
  final VoidCallback? onSwitchToRegister;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateIdentity(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) return 'Email or username is required.';
    return null;
  }

  String? _validatePassword(String? value) {
    final String text = value ?? '';
    if (text.isEmpty) return 'Password is required.';
    if (text.length < 6) return 'Use at least 6 characters.';
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.fixed),
      );
  }

  Future<void> _submitLogin() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await AuthApi.login(
        emailOrUsername: _emailController.text,
        password: _passwordController.text,
      );

      _showMessage('Login successful.');
      widget.onAuthenticated?.call();
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Login failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: constraints.maxHeight - 40,
                  ),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Studket',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to your account',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _emailController,
                              textInputAction: TextInputAction.next,
                              validator: _validateIdentity,
                              decoration: _fieldDecoration(
                                label: 'Email or username',
                                prefixIcon: Icons.alternate_email,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_passwordVisible,
                              validator: _validatePassword,
                              decoration: _fieldDecoration(
                                label: 'Password',
                                prefixIcon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _passwordVisible = !_passwordVisible;
                                    });
                                  },
                                  icon: Icon(
                                    _passwordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submitLogin,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Login'),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      if (widget.onSwitchToRegister != null) {
                                        widget.onSwitchToRegister!.call();
                                        return;
                                      }
                                      Navigator.of(context).pushReplacement(
                                        PageRouteBuilder<void>(
                                          pageBuilder:
                                              (context, animation, _) =>
                                                  RegisterPage(
                                                    onAuthenticated:
                                                        widget
                                                            .onAuthenticated,
                                                  ),
                                          transitionDuration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          reverseTransitionDuration:
                                              const Duration(
                                                milliseconds: 220,
                                              ),
                                          transitionsBuilder: (
                                            context,
                                            animation,
                                            _,
                                            child,
                                          ) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            );
                                          },
                                        ),
                                      );
                                    },
                              child: const Text('No account yet? Register'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
