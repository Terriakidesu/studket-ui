import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api/api_auth_session.dart';
import 'api/auth_api.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

enum _ProfileMode { seller, buyer }

class _UserProfilePageState extends State<UserProfilePage> {
  _ProfileMode _mode = ApiAuthSession.isSeller
      ? _ProfileMode.seller
      : _ProfileMode.buyer;
  bool _isSubmittingSellerRequest = false;

  bool get _isSellerAccount => ApiAuthSession.isSeller;

  String get _displayName {
    final String username = ApiAuthSession.username ?? 'studket_user';
    return username.replaceAll('_', ' ');
  }

  String get _subtitle {
    final String role = ApiAuthSession.marketplaceRole ?? 'buyer';
    final String accountType = ApiAuthSession.accountType ?? 'user';
    return '${_capitalize(role)} account • $accountType';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _requestSellerAccess() async {
    setState(() {
      _isSubmittingSellerRequest = true;
    });

    try {
      await AuthApi.requestSellerStatus(
        submissionNote: 'Requested from the Flutter marketplace app.',
      );
      _showMessage('Seller access request submitted.');
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to submit seller request.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingSellerRequest = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSeller = _isSellerAccount && _mode == _ProfileMode.seller;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundImage: NetworkImage(
                        'https://i.pravatar.cc/150?img=${((ApiAuthSession.accountId ?? 21) % 70) + 1}',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StatChip(
                                label: 'Account ID',
                                value: '${ApiAuthSession.accountId ?? '-'}',
                              ),
                              const SizedBox(width: 8),
                              _StatChip(
                                label: 'Role',
                                value: _capitalize(
                                  ApiAuthSession.marketplaceRole ?? 'buyer',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isSellerAccount)
              SegmentedButton<_ProfileMode>(
                segments: const [
                  ButtonSegment<_ProfileMode>(
                    value: _ProfileMode.seller,
                    icon: Icon(Icons.storefront_outlined),
                    label: Text('Seller'),
                  ),
                  ButtonSegment<_ProfileMode>(
                    value: _ProfileMode.buyer,
                    icon: Icon(Icons.shopping_bag_outlined),
                    label: Text('Buyer'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (Set<_ProfileMode> selection) {
                  setState(() {
                    _mode = selection.first;
                  });
                },
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your backend currently exposes user auth and seller request endpoints. Submit a seller verification request here.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _isSubmittingSellerRequest
                            ? null
                            : _requestSellerAccess,
                        child: _isSubmittingSellerRequest
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Request Seller'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              isSeller ? 'Seller Access' : 'Buyer Access',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'The current backend reference only exposes user auth endpoints publicly. Marketplace feed, chat, and review APIs are management-only, so no listing or purchase data is rendered here.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  isSeller
                      ? 'Your account is marked as a seller in the current auth session.'
                      : 'No public marketplace data is available for buyer accounts yet.',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(ApiAuthSession.email ?? 'No email in session'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(ApiAuthSession.username ?? 'No username'),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('User API integration active'),
                    subtitle: Text(
                      'Register, login, and seller verification request are wired to the backend.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$value $label',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
    );
  }
}
