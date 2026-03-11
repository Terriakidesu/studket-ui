import 'package:flutter/material.dart';

import 'authentication_page.dart';
import 'chats_page.dart';
import 'components/studket_app_bar.dart';
import 'user_profile_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studket',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const AppEntryPage(),
    );
  }
}

class AppEntryPage extends StatefulWidget {
  const AppEntryPage({super.key});

  @override
  State<AppEntryPage> createState() => _AppEntryPageState();
}

class _AppEntryPageState extends State<AppEntryPage> {
  bool _isAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticated) {
      return const MyHomePage(title: 'Studket');
    }

    return AuthenticationPage(
      onAuthenticated: () {
        if (!mounted) return;
        setState(() {
          _isAuthenticated = true;
        });
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(
        title: widget.title,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 20,
        titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      body: Center(
        child: currentPageIndex == 0
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: ListView(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Endpoint Overview',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This app is wired to the backend endpoints that are public for normal user accounts.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.login),
                        title: const Text('POST /api/v1/auth/login'),
                        subtitle: const Text(
                          'Used by the sign-in screen for normal marketplace users.',
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.app_registration),
                        title: const Text('POST /api/v1/auth/register'),
                        subtitle: const Text(
                          'Used by the registration screen with explicit username, campus, first name, and last name fields.',
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text(
                          'POST /api/v1/auth/seller-status/request',
                        ),
                        subtitle: const Text(
                          'Exposed in the profile screen as a trusted-seller request, not a seller-activation requirement.',
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.wifi_tethering),
                        title: const Text('WS /ws/users/{account_id}'),
                        subtitle: const Text(
                          'Exposed through the profile and chat screens for bootstrap, ping, subscribe, send message, and notification read actions.',
                        ),
                      ),
                    ),
                    Card(
                      color: Colors.amber[50],
                      child: const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Not Public For User Accounts'),
                        subtitle: Text(
                          'Listings feed/search and CRUD resources remain management-only in the current backend reference.',
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const UserProfilePage(),
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: currentPageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ChatsPage()));
        },
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }
}
