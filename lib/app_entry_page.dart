import 'dart:async';

import 'package:flutter/material.dart';

import 'api/api_session_storage.dart';
import 'authentication_page.dart';
import 'main.dart' show MyHomePage;

class AppEntryPage extends StatefulWidget {
  const AppEntryPage({super.key});

  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage> {
  bool _isAuthenticated = false;
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    final bool restored = await ApiSessionStorage.restoreSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAuthenticated = restored;
      _isRestoringSession = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoringSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isAuthenticated) {
      return const MyHomePage(title: 'Studket');
    }

    return AuthenticationPage(
      onAuthenticated: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthenticated = true;
        });
      },
    );
  }
}
