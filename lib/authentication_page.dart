import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';

class AuthenticationPage extends StatefulWidget {
  const AuthenticationPage({super.key, this.onAuthenticated});

  final VoidCallback? onAuthenticated;

  @override
  State<StatefulWidget> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _registerFormKey = GlobalKey<FormState>();

  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();

  final TextEditingController _registerNameController =
      TextEditingController();
  final TextEditingController _registerEmailController =
      TextEditingController();
  final TextEditingController _registerPasswordController =
      TextEditingController();
  final TextEditingController _registerConfirmPasswordController =
      TextEditingController();

  bool _loginPasswordVisible = false;
  bool _registerPasswordVisible = false;
  bool _registerConfirmPasswordVisible = false;
  bool _isSubmitting = false;
  bool _showRegister = false;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmPasswordController.dispose();
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

  String _extractErrorMessage(
    http.Response response, {
    required bool isLogin,
  }) {
    if (isLogin && response.statusCode == 401) {
      return 'Invalid email or password.';
    }

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic message = decoded['message'] ?? decoded['detail'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode}).';
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  void _storeSessionFromAuthResponse(http.Response response) {
    ApiAuthSession.setCookieFromSetCookieHeader(response.headers['set-cookie']);

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      final dynamic token =
          decoded['access_token'] ??
          decoded['access'] ??
          decoded['token'] ??
          decoded['auth_token'] ??
          decoded['key'];
      if (token is String && token.trim().isNotEmpty) {
        ApiAuthSession.setBearerToken(token);
      }
    } catch (_) {}
  }

  Future<http.Response> _postJsonFollowRedirect(
    Uri uri,
    Map<String, String> body,
  ) async {
    const Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    http.Response response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(kApiRequestTimeout);

    if (_isRedirectStatus(response.statusCode)) {
      final String? location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        final Uri redirectedUri = uri.resolve(location);
        response = await http
            .post(redirectedUri, headers: headers, body: jsonEncode(body))
            .timeout(kApiRequestTimeout);
      }
    }

    return response;
  }

  Future<void> _submitLogin() async {
    final FormState? form = _loginFormKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final http.Response response = await _postJsonFollowRedirect(
        ApiRoutes.authLogin(),
        <String, String>{
          'email': _loginEmailController.text.trim(),
          'password': _loginPasswordController.text,
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response, isLogin: true));
      }

      _storeSessionFromAuthResponse(response);
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

  Future<void> _submitRegister() async {
    final FormState? form = _registerFormKey.currentState;
    if (form == null || !form.validate()) return;

    final String password = _registerPasswordController.text;
    final String confirmPassword = _registerConfirmPasswordController.text;
    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final http.Response response = await _postJsonFollowRedirect(
        ApiRoutes.authRegister(),
        <String, String>{
          'name': _registerNameController.text.trim(),
          'email': _registerEmailController.text.trim(),
          'password': _registerPasswordController.text,
          'confirm_password': _registerConfirmPasswordController.text,
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response, isLogin: false));
      }

      _storeSessionFromAuthResponse(response);
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
                      child: _showRegister
                          ? Form(
                                key: _registerFormKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Studket',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Create your account',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _registerNameController,
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
                                      controller: _registerEmailController,
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
                                      controller: _registerPasswordController,
                                      obscureText: !_registerPasswordVisible,
                                      textInputAction: TextInputAction.next,
                                      validator: _validatePassword,
                                      decoration: _fieldDecoration(
                                        label: 'Password',
                                        prefixIcon: Icons.lock_outline,
                                        suffixIcon: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _registerPasswordVisible =
                                                  !_registerPasswordVisible;
                                            });
                                          },
                                          icon: Icon(
                                            _registerPasswordVisible
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller:
                                          _registerConfirmPasswordController,
                                      obscureText:
                                          !_registerConfirmPasswordVisible,
                                      validator: _validatePassword,
                                      decoration: _fieldDecoration(
                                        label: 'Confirm password',
                                        prefixIcon: Icons.lock_person_outlined,
                                        suffixIcon: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _registerConfirmPasswordVisible =
                                                  !_registerConfirmPasswordVisible;
                                            });
                                          },
                                          icon: Icon(
                                            _registerConfirmPasswordVisible
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton(
                                      onPressed:
                                          _isSubmitting ? null : _submitRegister,
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
                                              setState(() {
                                                _showRegister = false;
                                              });
                                            },
                                      child: const Text(
                                        'Already have an account? Login',
                                      ),
                                    ),
                                  ],
                                ),
                              )
                          : Form(
                                key: _loginFormKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Studket',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Sign in to your account',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _loginEmailController,
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
                                      controller: _loginPasswordController,
                                      obscureText: !_loginPasswordVisible,
                                      validator: _validatePassword,
                                      decoration: _fieldDecoration(
                                        label: 'Password',
                                        prefixIcon: Icons.lock_outline,
                                        suffixIcon: IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _loginPasswordVisible =
                                                  !_loginPasswordVisible;
                                            });
                                          },
                                          icon: Icon(
                                            _loginPasswordVisible
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
                                              setState(() {
                                                _showRegister = true;
                                              });
                                            },
                                      child: const Text(
                                        'No account yet? Register',
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
