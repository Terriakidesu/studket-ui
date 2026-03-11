import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api/auth_api.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    this.onAuthenticated,
    this.onSwitchToLogin,
  });

  final VoidCallback? onAuthenticated;
  final VoidCallback? onSwitchToLogin;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSubmitting = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) return 'Email is required.';
    final RegExp pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(text)) return 'Enter a valid email address.';
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

  Future<void> _submitRegister() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await AuthApi.register(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      _showMessage('Registration successful.');
      widget.onAuthenticated?.call();
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Registration failed. Please try again.');
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
                              'Create your account',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Full name is required.';
                                }
                                return null;
                              },
                              decoration: _fieldDecoration(
                                label: 'Full name',
                                prefixIcon: Icons.person_outline,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: _validateEmail,
                              decoration: _fieldDecoration(
                                label: 'Email',
                                prefixIcon: Icons.email_outlined,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_passwordVisible,
                              textInputAction: TextInputAction.next,
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
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: !_confirmPasswordVisible,
                              validator: _validatePassword,
                              decoration: _fieldDecoration(
                                label: 'Confirm password',
                                prefixIcon: Icons.lock_person_outlined,
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _confirmPasswordVisible =
                                          !_confirmPasswordVisible;
                                    });
                                  },
                                  icon: Icon(
                                    _confirmPasswordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submitRegister,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Register'),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      if (widget.onSwitchToLogin != null) {
                                        widget.onSwitchToLogin!.call();
                                        return;
                                      }
                                      Navigator.of(context).pushReplacement(
                                        PageRouteBuilder<void>(
                                          pageBuilder:
                                              (context, animation, _) =>
                                                  LoginPage(
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
                              child: const Text(
                                'Already have an account? Login',
                              ),
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
