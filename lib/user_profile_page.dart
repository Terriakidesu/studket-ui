import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api/api_auth_session.dart';
import 'api/auth_api.dart';
import 'api/user_realtime_service.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  bool _isSubmittingTrustedSellerRequest = false;

  @override
  void initState() {
    super.initState();
    unawaited(_realtime.ensureConnected());
  }

  void _showMessage(String message) {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final String username = ApiAuthSession.username ?? 'studket_user';
    final String marketplaceRole =
        ApiAuthSession.marketplaceRole ?? 'buyer';

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _realtime,
          builder: (BuildContext context, _) {
            return ListView(
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
                                username,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_capitalize(marketplaceRole)} account • ${ApiAuthSession.accountType ?? 'user'}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey[700]),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _StatChip(
                                    label: 'Account ID',
                                    value: '${ApiAuthSession.accountId ?? '-'}',
                                  ),
                                  _StatChip(
                                    label: 'Trusted',
                                    value:
                                        ApiAuthSession.trustedSeller
                                            ? 'Yes'
                                            : 'No',
                                  ),
                                  _StatChip(
                                    label: 'Socket',
                                    value: _realtime.isConnected
                                        ? 'Live'
                                        : 'Offline',
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Public REST Endpoints',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Register and login are already active. Trusted seller request is available here.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed:
                              _isSubmittingTrustedSellerRequest ||
                                  ApiAuthSession.trustedSeller
                              ? null
                              : _requestTrustedSeller,
                          child: _isSubmittingTrustedSellerRequest
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  ApiAuthSession.trustedSeller
                                      ? 'Trusted Seller Active'
                                      : 'Request Trusted Seller',
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'User WebSocket',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _realtime.isConnecting
                                  ? null
                                  : _realtime.ensureConnected,
                              child: const Text('Connect'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: _realtime.isConnected
                                  ? _realtime.sendPing
                                  : null,
                              child: const Text('Ping'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _realtime.isConnected
                              ? 'Connected to `/ws/users/${ApiAuthSession.accountId}`'
                              : (_realtime.error ??
                                    'Open a live user websocket to receive bootstrap conversations and notifications.'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                        if (_realtime.lastPongAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last pong: ${_formatDateTime(_realtime.lastPongAt!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        if (_realtime.notifications.isEmpty)
                          const Text(
                            'No notifications yet. They will appear here after websocket bootstrap or realtime events.',
                          )
                        else
                          ..._realtime.notifications.map((
                            UserRealtimeNotification notification,
                          ) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(notification.title),
                                subtitle: Text(notification.body),
                                trailing: notification.isRead
                                    ? const Icon(Icons.done_all, size: 18)
                                    : TextButton(
                                        onPressed: () {
                                          _realtime.markNotificationRead(
                                            notification.notificationId,
                                          );
                                        },
                                        child: const Text('Mark read'),
                                      ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conversations',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        if (_realtime.conversations.isEmpty)
                          const Text(
                            'No conversations yet. Bootstrap conversation summaries will appear here when the websocket connects.',
                          )
                        else
                          ..._realtime.conversations.map((
                            UserRealtimeConversation conversation,
                          ) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(conversation.title),
                              subtitle: Text(
                                conversation.conversationType,
                              ),
                              trailing: const Icon(Icons.chat_bubble_outline),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatDateTime(DateTime value) {
    final DateTime local = value.toLocal();
    final String hour = local.hour.toString().padLeft(2, '0');
    final String minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute';
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
