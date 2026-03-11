import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api/api_auth_session.dart';
import 'api/api_session_storage.dart';
import 'api/auth_api.dart';
import 'api/user_realtime_service.dart';
import 'authentication_page.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isElevatingSeller = false;
  bool _isSubmittingTrustedSellerRequest = false;
  bool _isLoggingOut = false;

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _requestTrustedSeller() async {
    setState(() {
      _isSubmittingTrustedSellerRequest = true;
    });

    try {
      await AuthApi.requestSellerStatus(
        submissionNote: 'Requested from the Flutter marketplace app.',
      );
      _showMessage('Trusted seller verification request submitted.');
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to submit trusted seller request.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingTrustedSellerRequest = false;
        });
      }
    }
  }

  Future<void> _elevateToSeller() async {
    setState(() {
      _isElevatingSeller = true;
    });

    try {
      await AuthApi.elevateToSeller();
      _showMessage('Your account is now a seller account.');
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to elevate account to seller.');
    } finally {
      if (mounted) {
        setState(() {
          _isElevatingSeller = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) {
      return;
    }

    setState(() {
      _isLoggingOut = true;
    });

    await UserRealtimeService.instance.disconnect(clearState: true);
    await ApiSessionStorage.clear();
    ApiAuthSession.clear();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AuthenticationPage(onAuthenticated: () {}),
      ),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String username = ApiAuthSession.username ?? 'studket_user';
    final String email = ApiAuthSession.email ?? 'No email';
    final String accountType = ApiAuthSession.accountType ?? 'user';
    final String marketplaceRole = ApiAuthSession.marketplaceRole ?? 'buyer';
    final bool isSeller = ApiAuthSession.isSeller;
    final bool isTrustedSeller = ApiAuthSession.trustedSeller;
    final String avatarUrl =
        'https://i.pravatar.cc/300?img=${((ApiAuthSession.accountId ?? 21) % 70) + 1}';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E1F22),
                            width: 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 42,
                          backgroundColor: const Color(0xFF1E1F22),
                          backgroundImage: NetworkImage(avatarUrl),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1F22),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DiscordTag(
                        label: _capitalize(accountType),
                        backgroundColor: const Color(0xFFE8EAFF),
                        foregroundColor: const Color(0xFF4752C4),
                      ),
                      _DiscordTag(
                        label: _capitalize(marketplaceRole),
                        backgroundColor: isSeller
                            ? const Color(0xFFE7F7EC)
                            : const Color(0xFFF3F4F6),
                        foregroundColor: isSeller
                            ? const Color(0xFF1F8F4D)
                            : const Color(0xFF6B7280),
                      ),
                      _DiscordTag(
                        label: isTrustedSeller
                            ? 'Trusted Seller'
                            : 'Not Trusted Yet',
                        backgroundColor: isTrustedSeller
                            ? const Color(0xFFFFF1D6)
                            : const Color(0xFFF3F4F6),
                        foregroundColor: isTrustedSeller
                            ? const Color(0xFFC27C0E)
                            : const Color(0xFF6B7280),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DiscordSectionCard(
              title: 'Account',
              child: Column(
                children: [
                  _ActionRow(
                    icon: Icons.manage_accounts_outlined,
                    label: 'Account Settings',
                    value: 'Profile details, account info, and security',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountSettingsPage(),
                        ),
                      );
                    },
                  ),
                  if (!isSeller) ...[
                    const Divider(height: 24),
                    _ActionRow(
                      icon: Icons.storefront_outlined,
                      label: _isElevatingSeller
                          ? 'Becoming Seller...'
                          : 'Become a Seller',
                      value: 'Elevate your buyer account to post listings',
                      onTap: _isElevatingSeller ? null : _elevateToSeller,
                    ),
                  ],
                ],
              ),
            ),
            if (isSeller) ...[
              const SizedBox(height: 16),
              _DiscordSectionCard(
                title: 'Seller Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isTrustedSeller
                            ? const Color(0xFFFFF6E5)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isTrustedSeller
                                ? Icons.verified_rounded
                                : Icons.storefront_rounded,
                            color: isTrustedSeller
                                ? const Color(0xFFC27C0E)
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isTrustedSeller
                                  ? 'Your account already has trusted seller status.'
                                  : 'You are already a seller. You can now request trusted seller review.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF374151),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmittingTrustedSellerRequest ||
                                isTrustedSeller
                            ? null
                            : _requestTrustedSeller,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF5865F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSubmittingTrustedSellerRequest
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isTrustedSeller
                                    ? 'Trusted Seller Active'
                                    : 'Request Trusted Seller',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _DiscordSectionCard(
              title: 'Settings',
              child: Column(
                children: [
                  const _ActionRow(
                    icon: Icons.shield_outlined,
                    label: 'Saved Session',
                    value: 'Active on this device',
                  ),
                  const Divider(height: 24),
                  _ActionRow(
                    icon: Icons.logout_rounded,
                    label: 'Log Out',
                    value: 'Clear local session and disconnect',
                    danger: true,
                    onTap: _isLoggingOut ? null : _logout,
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
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _DiscordSectionCard extends StatelessWidget {
  const _DiscordSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DiscordTag extends StatelessWidget {
  const _DiscordTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? const Color(0xFFDC2626) : const Color(0xFF111827);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String username = ApiAuthSession.username ?? 'studket_user';
    final String email = ApiAuthSession.email ?? 'No email';
    final String accountType = ApiAuthSession.accountType ?? 'user';
    final String marketplaceRole = ApiAuthSession.marketplaceRole ?? 'buyer';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiscordSectionCard(
            title: 'Profile',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingInfoLine(
                  label: 'Account ID',
                  value: '${ApiAuthSession.accountId ?? '-'}',
                ),
                _SettingInfoLine(label: 'Username', value: username),
                _SettingInfoLine(label: 'Email', value: email),
                _SettingInfoLine(label: 'Account Type', value: accountType),
                _SettingInfoLine(
                  label: 'Marketplace Role',
                  value: marketplaceRole,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DiscordSectionCard(
            title: 'Preferences',
            child: _ActionRow(
              icon: Icons.security_outlined,
              label: 'Security',
              value: 'Session and account protection details',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SecurityPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiscordSectionCard(
            title: 'Session',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SettingInfoLine(
                  label: 'Saved Session',
                  value: 'Active on this device',
                ),
                _SettingInfoLine(
                  label: 'Realtime Connection',
                  value: 'Disconnected when logging out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DiscordSectionCard(
            title: 'Security Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use logout if you are sharing this device or want to clear the locally saved session.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Password change and session management endpoints are not documented in the current backend reference yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingInfoLine extends StatelessWidget {
  const _SettingInfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF9CA3AF),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
