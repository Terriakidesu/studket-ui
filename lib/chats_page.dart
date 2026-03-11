import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/user_realtime_service.dart';
import 'components/account_avatar.dart';
import 'components/studket_app_bar.dart';
import 'seller_profile_page.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  Map<int, _ApiMessage> _latestMessagesByConversation =
      <int, _ApiMessage>{};
  int _lastRealtimeConversationCount = 0;
  int _lastRealtimeNotificationCount = 0;
  int _lastRealtimeNewMessageCount = 0;
  bool _isReloadingPreviews = false;

  void _openOtherUserProfile({
    required String name,
    required String avatarUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerProfilePage(
          sellerName: name,
          sellerAvatarUrl: avatarUrl,
          sellerRating: 4.5,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _realtime.addListener(_handleRealtimeChanged);
    unawaited(_realtime.ensureConnected());
    unawaited(_loadConversationPreviews());
  }

  @override
  void dispose() {
    _realtime.removeListener(_handleRealtimeChanged);
    super.dispose();
  }

  void _handleRealtimeChanged() {
    final int conversationCount = _realtime.conversations.length;
    final int notificationCount = _realtime.notifications.length;
    final int newMessageCount = _realtime.newMessageConversationCount;
    final bool shouldReload =
        conversationCount != _lastRealtimeConversationCount ||
        notificationCount != _lastRealtimeNotificationCount ||
        newMessageCount != _lastRealtimeNewMessageCount;
    _lastRealtimeConversationCount = conversationCount;
    _lastRealtimeNotificationCount = notificationCount;
    _lastRealtimeNewMessageCount = newMessageCount;
    if (shouldReload) {
      unawaited(_loadConversationPreviews());
    }
  }

  Future<void> _loadConversationPreviews() async {
    if (_isReloadingPreviews) {
      return;
    }
    _isReloadingPreviews = true;
    try {
      final http.Response response = await http
          .get(
            ApiRoutes.messages(),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return;
      }

      final Map<int, _ApiMessage> latestByConversation = <int, _ApiMessage>{};
      for (final MapEntry<int, Map<dynamic, dynamic>> entry
          in decoded.whereType<Map>().toList(growable: false).asMap().entries) {
        final _ApiMessage message = _ApiMessage.fromJson(
          Map<String, dynamic>.from(entry.value),
          sourceOrder: entry.key,
        );
        final _ApiMessage? existing = latestByConversation[message.conversationId];
        if (existing == null ||
            message.sentAt.isAfter(existing.sentAt) ||
            (message.sentAt.isAtSameMomentAs(existing.sentAt) &&
                message.sourceOrder > existing.sourceOrder)) {
          latestByConversation[message.conversationId] = message;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _latestMessagesByConversation = latestByConversation;
      });
    } catch (_) {
    } finally {
      _isReloadingPreviews = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const StudketAppBar(title: 'Chats'),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          final List<UserRealtimeConversation> conversations =
              _visibleConversations();
          if (conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _realtime.isConnected
                      ? 'No websocket conversations were returned for this user.'
                      : (_realtime.error ??
                            'Connect the user websocket to load conversations.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colorScheme.outlineVariant),
            itemBuilder: (BuildContext context, int index) {
              final UserRealtimeConversation conversation = conversations[index];
              final int avatarAccountId =
                  conversation.otherAccountId ?? conversation.conversationId;
              final bool hasNewMessage = _realtime.hasNewMessage(
                conversation.conversationId,
              );
              final UserRealtimeTypingState? typingState =
                  _realtime.typingStateFor(conversation.conversationId);
              final bool isTyping = typingState?.isTyping == true;
              final String recentMessage = isTyping
                  ? '${typingState!.username} is typing...'
                  : _recentMessagePreview(conversation);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: hasNewMessage
                      ? Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.10,
                        )
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      _openOtherUserProfile(
                        name: conversation.title,
                        avatarUrl: _avatarUrlForConversation(conversation),
                      );
                    },
                    child: AccountAvatar(
                      accountId: avatarAccountId,
                      radius: 20,
                      backgroundColor: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      label: conversation.title,
                    ),
                  ),
                  title: Text(
                    conversation.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    recentMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTyping
                          ? Theme.of(context).colorScheme.primary
                           : (hasNewMessage
                               ? colorScheme.onSurface
                               : colorScheme.onSurfaceVariant),
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                      fontWeight: hasNewMessage || isTyping
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: hasNewMessage
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    _realtime.openConversation(conversation.conversationId);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatThreadPage(
                          sellerName: conversation.title,
                          lastMessage: conversation.conversationType,
                          sellerAvatarUrl: _avatarUrlForConversation(
                            conversation,
                          ),
                          conversationId: conversation.conversationId,
                          conversationType: conversation.conversationType,
                          lastMessageAt: conversation.lastMessageAt,
                          isStaffParticipant: _isStaffAccountType(
                            conversation.otherAccountType,
                          ),
                        ),
                      ),
                    );
                    if (!mounted) {
                      return;
                    }
                    await _loadConversationPreviews();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _avatarUrlForConversation(UserRealtimeConversation conversation) {
    final int accountId =
        conversation.otherAccountId ?? conversation.conversationId;
    return '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId';
  }

  String _recentMessagePreview(UserRealtimeConversation conversation) {
    final List<UserRealtimeMessage> liveMessages = _realtime.messagesFor(
      conversation.conversationId,
    );
    if (liveMessages.isNotEmpty) {
      return _previewTextForMessage(liveMessages.last.messageText);
    }

    final String? apiPreview =
        _latestMessagesByConversation[conversation.conversationId]
            ?.messageText
            .trim();
    if (apiPreview != null && apiPreview.isNotEmpty) {
      return _previewTextForMessage(apiPreview);
    }

    final String? preview = conversation.lastMessageText?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }

    return _formatConversationType(conversation.conversationType);
  }

  String _previewTextForMessage(String messageText) {
    final InquiryProductData? inquiryProduct =
        _ChatThreadPageState._parseInquiryMessage(messageText);
    if (inquiryProduct != null) {
      return 'Inquiry: ${inquiryProduct.name}';
    }
    final QrConfirmationData? qrConfirmation =
        _ChatThreadPageState._parseQrConfirmationStartedMessage(messageText);
    if (qrConfirmation != null) {
      return 'QR confirmation: ${qrConfirmation.product.name}';
    }
    return messageText.trim();
  }

  String _formatConversationType(String conversationType) {
    if (conversationType.trim().isEmpty) {
      return 'Conversation';
    }
    return conversationType
        .split('_')
        .where((String segment) => segment.trim().isNotEmpty)
        .map(
          (String segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  bool _isStaffAccountType(String? accountType) {
    final String normalized = (accountType ?? '').trim().toLowerCase();
    return normalized == 'staff' ||
        normalized == 'management' ||
        normalized == 'superadmin';
  }

  List<UserRealtimeConversation> _visibleConversations() {
    final List<UserRealtimeConversation> merged =
        List<UserRealtimeConversation>.from(_realtime.conversations);
    final Set<int> knownIds = merged
        .map((UserRealtimeConversation item) => item.conversationId)
        .toSet();
    _latestMessagesByConversation.forEach((int conversationId, _ApiMessage message) {
      if (knownIds.contains(conversationId)) {
        return;
      }
      final bool isMine =
          message.senderId != null && message.senderId == ApiAuthSession.accountId;
      merged.add(
        UserRealtimeConversation(
          conversationId: conversationId,
          conversationType: 'conversation',
          otherAccountId: isMine ? null : message.senderId,
          otherUsername: isMine
              ? 'Conversation'
              : (message.senderUsername?.trim().isNotEmpty == true
                  ? message.senderUsername!.trim()
                  : 'Conversation'),
          otherAccountType: 'user',
          lastMessageText: message.messageText,
          lastMessageAt: message.sentAt,
          messageCount: 1,
        ),
      );
    });
    merged.sort(_compareConversationsByLatest);
    return merged;
  }

  int _compareConversationsByLatest(
    UserRealtimeConversation a,
    UserRealtimeConversation b,
  ) {
    final DateTime aTime =
        a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime bTime =
        b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final int byTime = bTime.compareTo(aTime);
    if (byTime != 0) {
      return byTime;
    }
    return b.conversationId.compareTo(a.conversationId);
  }
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.sellerName,
    required this.lastMessage,
    required this.sellerAvatarUrl,
    this.sellerAccountId,
    this.inquiryProducts = const <InquiryProductData>[],
    this.inquiryProduct,
    this.initialMessageText,
    this.conversationId,
    this.conversationType,
    this.lastMessageAt,
    this.isStaffParticipant = false,
  });

  final String sellerName;
  final String lastMessage;
  final String sellerAvatarUrl;
  final int? sellerAccountId;
  final List<InquiryProductData> inquiryProducts;
  final InquiryProductData? inquiryProduct;
  final String? initialMessageText;
  final int? conversationId;
  final String? conversationType;
  final DateTime? lastMessageAt;
  final bool isStaffParticipant;

  List<InquiryProductData> get effectiveInquiryProducts {
    if (inquiryProducts.isNotEmpty) {
      return inquiryProducts;
    }
    if (inquiryProduct != null) {
      return <InquiryProductData>[inquiryProduct!];
    }
    return const <InquiryProductData>[];
  }

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  static const String _inquiryMessagePrefix = '[studket_inquiry]';
  static const String _offerAcceptedMessagePrefix = '[studket_offer_accepted]';
  static const String _offerRejectedMessagePrefix = '[studket_offer_rejected]';
  static const String _qrConfirmationStartedMessagePrefix =
      '[studket_qr_confirmation_started]';
  static const String _transactionCompletedMessagePrefix =
      '[studket_transaction_completed]';

  final UserRealtimeService _realtime = UserRealtimeService.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MobileScannerController _qrScannerController =
      MobileScannerController();
  Timer? _typingDebounce;
  bool _isSendingTyping = false;

  bool _isLoadingHistory = false;
  bool _isStartingConversation = false;
  String? _historyError;
  List<_ApiMessage> _historyMessages = const <_ApiMessage>[];
  _ResolvedInquiryPreview? _resolvedInquiry;
  int _lastRenderedMessageCount = 0;
  int? _activeConversationId;
  bool _hasSentInitialInquiry = false;
  bool _isConfirmingQr = false;
  bool _hasHandledScan = false;
  final Set<String> _consumedQrTokens = <String>{};

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleComposerChanged);
    unawaited(_realtime.ensureConnected());
    _activeConversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_activeConversationId != null) {
        _bindConversation(
          _activeConversationId!,
          sendInitialInquiry: _shouldSendInitialInquiry,
        );
      } else if (widget.sellerAccountId != null) {
        unawaited(_bootstrapInquiryConversation());
      }
    });
  }

  bool get _shouldSendInitialInquiry {
    return widget.effectiveInquiryProducts.isNotEmpty ||
        (widget.initialMessageText ?? '').trim().isNotEmpty;
  }

  bool get _shouldOpenListingInquiry {
    return widget.effectiveInquiryProducts.isNotEmpty;
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    unawaited(_stopTyping());
    _messageController.removeListener(_handleComposerChanged);
    if (_activeConversationId != null) {
      _realtime.closeConversation(_activeConversationId!);
    }
    _qrScannerController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(int conversationId) async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final http.Response response = await http
          .get(
            ApiRoutes.messages(),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Messages response must be a list.');
      }

      final List<_ApiMessage> parsed = decoded
          .whereType<Map>()
          .toList(growable: false)
          .asMap()
          .entries
          .map(
            (MapEntry<int, Map<dynamic, dynamic>> entry) => _ApiMessage.fromJson(
              Map<String, dynamic>.from(entry.value),
              sourceOrder: entry.key,
            ),
          )
          .where(
            (_ApiMessage item) => item.conversationId == conversationId,
          )
          .toList(growable: false)
        ..sort((_ApiMessage a, _ApiMessage b) => a.sentAt.compareTo(b.sentAt));

      if (!mounted) return;
      setState(() {
        _historyMessages = parsed;
      });
      _scheduleScrollToBottom(jump: true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Loading previous messages timed out.';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Could not connect to the messages endpoint.';
      });
    } on HttpException catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error.message;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Messages endpoint returned an invalid response.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Failed to load previous messages.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _bindConversation(int conversationId, {bool sendInitialInquiry = false}) {
    _activeConversationId = conversationId;
    _realtime.openConversation(conversationId);
    unawaited(_realtime.subscribeConversation(conversationId));
    unawaited(_loadHistory(conversationId));
    unawaited(_loadInquiryForConversation(conversationId));
    if (sendInitialInquiry) {
      unawaited(_sendInitialInquiryIfNeeded());
    }
  }

  Future<void> _loadInquiryForConversation(int conversationId) async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null || accountId <= 0) {
      return;
    }

    try {
      final http.Response response = await http
          .get(
            ApiRoutes.userInquiries(accountId),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final dynamic decoded = jsonDecode(response.body);
      final _ResolvedInquiryPreview? inquiry = _extractInquiryForConversation(
        decoded,
        conversationId: conversationId,
      );
      if (!mounted || _activeConversationId != conversationId || inquiry == null) {
        return;
      }

      setState(() {
        _resolvedInquiry = inquiry == null
            ? null
            : _ResolvedInquiryPreview(
                inquiryId: inquiry.inquiryId,
                product: _enrichInquiryProduct(inquiry.product),
                buyerAccountId: inquiry.buyerAccountId,
                isMine: inquiry.isMine,
                status: inquiry.status,
              );
      });
    } catch (_) {}
  }

  Future<void> _bootstrapInquiryConversation() async {
    final int? sellerAccountId = widget.sellerAccountId;
    if (sellerAccountId == null) {
      return;
    }

    setState(() {
      _isStartingConversation = true;
      _historyError = null;
    });

    try {
      await _realtime.ensureConnected();
      if (_shouldOpenListingInquiry) {
        final int conversationId = await _openListingInquiry(
          product: widget.effectiveInquiryProducts.first,
          messageText: (widget.initialMessageText ?? '').trim(),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isStartingConversation = false;
          _hasSentInitialInquiry = false;
        });
        _bindConversation(conversationId, sendInitialInquiry: true);
        return;
      }

      final UserRealtimeConversation? existing = _findExistingConversation(
        sellerAccountId,
      );
      if (existing != null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isStartingConversation = false;
        });
        _bindConversation(
          existing.conversationId,
          sendInitialInquiry: _shouldSendInitialInquiry,
        );
        return;
      }

      final int conversationId = await _createConversation(
        sellerAccountId: sellerAccountId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingConversation = false;
      });
      _bindConversation(conversationId, sendInitialInquiry: true);
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingConversation = false;
        _historyError = 'The inquiry request timed out.';
      });
    } on SocketException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingConversation = false;
        _historyError = 'Could not connect to start the inquiry.';
      });
    } on HttpException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingConversation = false;
        _historyError = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStartingConversation = false;
        _historyError = 'Could not start the inquiry.';
      });
    }
  }

  UserRealtimeConversation? _findExistingConversation(int sellerAccountId) {
    for (final UserRealtimeConversation conversation in _realtime.conversations) {
      if (conversation.otherAccountId == sellerAccountId) {
        return conversation;
      }
    }
    return null;
  }

  Future<int> _openListingInquiry({
    required InquiryProductData product,
    required String messageText,
  }) async {
    final int? currentAccountId = ApiAuthSession.accountId;
    if (currentAccountId == null || currentAccountId <= 0) {
      throw const HttpException('No authenticated account id was found.');
    }

    final http.Response response = await http
        .post(
          ApiRoutes.listingInquiries(product.listingId),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(<String, dynamic>{
            'account_id': currentAccountId,
            if (messageText.isNotEmpty) 'message_text': messageText,
          }),
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }

    final dynamic decoded = jsonDecode(response.body);
    final int? conversationId = _extractConversationId(decoded);
    if (conversationId == null || conversationId <= 0) {
      throw const FormatException('Listing inquiry response was invalid.');
    }
    return conversationId;
  }

  Future<int> _createConversation({required int sellerAccountId}) async {
    final int? currentAccountId = ApiAuthSession.accountId;
    if (currentAccountId == null || currentAccountId <= 0) {
      throw const HttpException('No authenticated account id was found.');
    }

    final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[
      <String, dynamic>{
        'participant1_id': currentAccountId,
        'participant2_id': sellerAccountId,
        'conversation_type': 'direct',
      },
      <String, dynamic>{
        'participant1_id': currentAccountId,
        'participant2_id': sellerAccountId,
      },
      <String, dynamic>{
        'participant1_id': sellerAccountId,
        'participant2_id': currentAccountId,
        'conversation_type': 'direct',
      },
      <String, dynamic>{
        'participant1_id': sellerAccountId,
        'participant2_id': currentAccountId,
      },
    ];

    HttpException? lastHttpError;
    FormatException? lastFormatError;

    for (final Map<String, dynamic> payload in payloads) {
      final http.Response response = await http
          .post(
            ApiRoutes.conversations(),
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
            body: jsonEncode(payload),
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastHttpError = HttpException(_extractErrorMessage(response));
        continue;
      }

      final dynamic decoded = jsonDecode(response.body);
      final int? conversationId = _extractConversationId(decoded);
      if (conversationId != null && conversationId > 0) {
        return conversationId;
      }
      lastFormatError =
          const FormatException('Conversation response was invalid.');
    }

    if (lastHttpError != null) {
      throw lastHttpError;
    }
    throw lastFormatError ??
        const FormatException('Conversation response was invalid.');
  }

  Future<void> _sendInitialInquiryIfNeeded() async {
    final int? conversationId = _activeConversationId;
    final String text = (widget.initialMessageText ?? '').trim();
    if (_hasSentInitialInquiry || conversationId == null) {
      return;
    }

    final List<_TimelineMessage> timeline = _buildTimeline(conversationId);
    final _TimelineMessage? currentInquiry = _currentInquiryFromTimeline(timeline);
    if (currentInquiry != null &&
        currentInquiry.inquiryProduct != null &&
        currentInquiry.isMine) {
      _hasSentInitialInquiry = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your current inquiry is still pending. Wait for the seller to accept or reject it before sending another one.',
            ),
          ),
        );
      }
      return;
    }

    _hasSentInitialInquiry = true;
    for (final InquiryProductData product in widget.effectiveInquiryProducts) {
      await _realtime.sendMessage(
        conversationId: conversationId,
        messageText: _serializeInquiryMessage(product),
      );
    }
    if (widget.effectiveInquiryProducts.isEmpty && text.isNotEmpty) {
      await _realtime.sendMessage(
        conversationId: conversationId,
        messageText: text,
      );
    }
  }

  Future<void> _acceptInquiryOffer(_TimelineMessage inquiryMessage) async {
    await _acceptResolvedInquiryOffer(
      product: inquiryMessage.inquiryProduct,
      buyerAccountId: inquiryMessage.senderAccountId,
      inquiryId: _resolveInquiryIdForProduct(inquiryMessage.inquiryProduct),
    );
  }

  Future<void> _acceptResolvedInquiryOffer({
    required InquiryProductData? product,
    required int? buyerAccountId,
    required int? inquiryId,
  }) async {
    final int? conversationId = _activeConversationId;
    if (conversationId == null) {
      return;
    }

    final int? sellerAccountId = ApiAuthSession.accountId;
    if (product == null ||
        sellerAccountId == null ||
        sellerAccountId <= 0 ||
        buyerAccountId == null ||
        buyerAccountId <= 0 ||
        inquiryId == null ||
        inquiryId <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start QR confirmation for this inquiry.'),
        ),
      );
      return;
    }

    try {
      await _acceptListingInquiry(
        listingId: product.listingId,
        inquiryId: inquiryId,
        accountId: sellerAccountId,
      );
      final QrConfirmationData qrConfirmation = await _startQrConfirmation(
        product: product,
        buyerAccountId: buyerAccountId,
        sellerAccountId: sellerAccountId,
      );
      await _realtime.sendMessage(
        conversationId: conversationId,
        messageText: _serializeAcceptedOfferMessage(product),
      );
      await _realtime.sendMessage(
        conversationId: conversationId,
        messageText: _serializeQrConfirmationStartedMessage(qrConfirmation),
      );
      if (mounted) {
        setState(() {
          final _ResolvedInquiryPreview? resolvedInquiry = _resolvedInquiry;
          if (resolvedInquiry != null && resolvedInquiry.inquiryId == inquiryId) {
            _resolvedInquiry = _ResolvedInquiryPreview(
              inquiryId: resolvedInquiry.inquiryId,
              product: resolvedInquiry.product,
              buyerAccountId: resolvedInquiry.buyerAccountId,
              isMine: resolvedInquiry.isMine,
              status: 'accepted',
            );
          }
        });
      }
      if (mounted) {
        _showQrConfirmationDialog(qrConfirmation, isMine: true);
      }
      _scheduleScrollToBottom();
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starting QR confirmation timed out.'),
        ),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to start QR confirmation.'),
        ),
      );
    } on HttpException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on FormatException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR confirmation returned an invalid response.'),
        ),
      );
    }
  }

  Future<void> _rejectInquiryOffer(InquiryProductData product) async {
    final int? sellerAccountId = ApiAuthSession.accountId;
    final int? inquiryId = _resolveInquiryIdForProduct(product);
    if (sellerAccountId == null ||
        sellerAccountId <= 0 ||
        inquiryId == null ||
        inquiryId <= 0) {
      return;
    }

    try {
      await _rejectListingInquiry(
        listingId: product.listingId,
        inquiryId: inquiryId,
        accountId: sellerAccountId,
      );
      final int? conversationId = _activeConversationId;
      if (conversationId != null) {
        await _realtime.sendMessage(
          conversationId: conversationId,
          messageText: _serializeRejectedOfferMessage(product),
        );
        if (mounted) {
          setState(() {
            final _ResolvedInquiryPreview? resolvedInquiry = _resolvedInquiry;
            if (resolvedInquiry != null && resolvedInquiry.inquiryId == inquiryId) {
              _resolvedInquiry = _ResolvedInquiryPreview(
                inquiryId: resolvedInquiry.inquiryId,
                product: resolvedInquiry.product,
                buyerAccountId: resolvedInquiry.buyerAccountId,
                isMine: resolvedInquiry.isMine,
                status: 'rejected',
              );
            }
          });
        }
        _scheduleScrollToBottom();
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rejecting this inquiry timed out.')),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to reject this inquiry.')),
      );
    } on HttpException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is Map<String, dynamic>) {
          final dynamic error = detail['error'];
          if (error is String && error.trim().isNotEmpty) {
            return error.trim();
          }
        }
      }
    } catch (_) {}
    return 'Messages request failed (HTTP ${response.statusCode}).';
  }

  Future<void> _sendMessage() async {
    final int? conversationId = _activeConversationId;
    final String text = _messageController.text.trim();
    if (conversationId == null || text.isEmpty) {
      return;
    }

    await _stopTyping();
    await _realtime.sendMessage(
      conversationId: conversationId,
      messageText: text,
    );
    _messageController.clear();
    _scheduleScrollToBottom();
  }

  void _handleComposerChanged() {
    final int? conversationId = _activeConversationId;
    if (conversationId == null) {
      return;
    }

    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      _typingDebounce?.cancel();
      unawaited(_stopTyping());
      return;
    }

    if (!_isSendingTyping) {
      _isSendingTyping = true;
      unawaited(
        _realtime.sendTypingStatus(
          conversationId: conversationId,
          isTyping: true,
        ),
      );
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      unawaited(_stopTyping());
    });
  }

  Future<void> _stopTyping() async {
    final int? conversationId = _activeConversationId;
    if (!_isSendingTyping || conversationId == null) {
      return;
    }
    _isSendingTyping = false;
    await _realtime.sendTypingStatus(
      conversationId: conversationId,
      isTyping: false,
    );
  }

  List<_TimelineMessage> _buildTimeline(int conversationId) {
    final Map<String, _TimelineMessage> items = <String, _TimelineMessage>{};

    for (final _ApiMessage message in _historyMessages) {
      items['api:${message.messageId}'] = _TimelineMessage.api(
        message,
        otherParticipantName: widget.sellerName,
      );
    }
    for (final UserRealtimeMessage message
        in _realtime.messagesFor(conversationId)) {
      final String key = message.messageId > 0
          ? 'api:${message.messageId}'
          : 'rt:${message.conversationId}:${message.senderUsername}:${message.sentAt?.toIso8601String()}:${message.messageText}';
      items[key] = _TimelineMessage.realtime(message);
    }

    final List<_TimelineMessage> timeline = items.values.toList(growable: false)
      ..sort((_TimelineMessage a, _TimelineMessage b) {
        if (a.isRealtime != b.isRealtime) {
          return a.isRealtime ? 1 : -1;
        }
        if (a.isRealtime && b.isRealtime) {
          return a.sortOrder.compareTo(b.sortOrder);
        }
        final int byDate = a.sentAt.compareTo(b.sentAt);
        if (byDate != 0) {
          return byDate;
        }
        final int byId = a.messageId.compareTo(b.messageId);
        if (byId != 0) {
          return byId;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final Set<int> completedTransactionIds = _realtime.notifications
        .where(
          (UserRealtimeNotification notification) =>
              notification.notificationType.trim().toLowerCase() ==
                  'transaction_completed' &&
              (notification.relatedEntityType ?? '').trim().toLowerCase() ==
                  'transaction' &&
              (notification.relatedEntityId ?? 0) > 0,
        )
        .map(
          (UserRealtimeNotification notification) =>
              notification.relatedEntityId!,
        )
        .toSet();
    final Set<String> completedQrTokens = timeline
        .where(
          (_TimelineMessage message) => message.completedQrConfirmation != null,
        )
        .map(
          (_TimelineMessage message) => message.completedQrConfirmation!.qrToken,
        )
        .toSet();
    return timeline
        .map((_TimelineMessage message) {
          final QrConfirmationData? qrConfirmation = message.qrConfirmation;
          if (qrConfirmation == null) {
            return message;
          }
          final bool isCompleted =
              _consumedQrTokens.contains(qrConfirmation.qrToken) ||
              completedQrTokens.contains(qrConfirmation.qrToken) ||
              completedTransactionIds.contains(qrConfirmation.transactionId);
          if (!isCompleted) {
            return message;
          }
          return message.copyWith(
            qrConfirmation: null,
            completedQrConfirmation:
                message.completedQrConfirmation ?? qrConfirmation,
            text: '',
          );
        })
        .where(
          (_TimelineMessage message) =>
              message.qrConfirmation != null ||
              message.completedQrConfirmation != null ||
              message.inquiryProduct != null ||
              message.acceptedOfferProduct != null ||
              message.rejectedOfferProduct != null ||
              message.text.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  _TimelineMessage? _currentInquiryFromTimeline(List<_TimelineMessage> timeline) {
    final Set<int> resolvedListingIds = <int>{};
    for (final _TimelineMessage message in timeline.reversed) {
      if (message.acceptedOfferProduct != null) {
        resolvedListingIds.add(message.acceptedOfferProduct!.listingId);
        continue;
      }
      if (message.rejectedOfferProduct != null) {
        resolvedListingIds.add(message.rejectedOfferProduct!.listingId);
        continue;
      }
      final InquiryProductData? inquiry = message.inquiryProduct;
      if (inquiry != null && !resolvedListingIds.contains(inquiry.listingId)) {
        return message;
      }
    }
    return null;
  }

  void _scheduleScrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final double target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final int? conversationId = _activeConversationId;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: StudketAppBar(
        title: widget.sellerName,
        actions: [
          IconButton(
            tooltip: 'View profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SellerProfilePage(
                    sellerName: widget.sellerName,
                    sellerAvatarUrl: widget.sellerAvatarUrl,
                    sellerRating: 4.5,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          if (_isStartingConversation) {
            return const Center(child: CircularProgressIndicator());
          }

          if (conversationId == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _historyError ??
                          'The seller details needed for this inquiry are unavailable.',
                      textAlign: TextAlign.center,
                    ),
                    if (widget.sellerAccountId != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _bootstrapInquiryConversation,
                        child: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          final List<_TimelineMessage> timeline = _buildTimeline(conversationId);
          final _TimelineMessage? currentInquiry =
              _currentInquiryFromTimeline(timeline);
          final bool hasPendingResolvedInquiry =
              (_resolvedInquiry?.status ?? '').toLowerCase() == 'pending';
          final InquiryProductData? fallbackInquiryProduct =
              currentInquiry == null &&
                  (hasPendingResolvedInquiry ||
                      (_hasSentInitialInquiry &&
                          widget.effectiveInquiryProducts.isNotEmpty))
              ? _enrichInquiryProduct(
                  _resolvedInquiry?.product ?? widget.effectiveInquiryProducts.first,
                )
              : null;
          final bool fallbackInquiryIsMine =
              _resolvedInquiry?.isMine ?? true;
          final int? fallbackInquiryBuyerAccountId =
              _resolvedInquiry?.buyerAccountId;
          final UserRealtimeTypingState? typingState = _realtime.typingStateFor(
            conversationId,
          );
          if (timeline.length != _lastRenderedMessageCount) {
            _lastRenderedMessageCount = timeline.length;
            _scheduleScrollToBottom(
              jump: timeline.length <= 1 || _isLoadingHistory,
            );
          }

          return Column(
            children: [
              Expanded(
                child: _isLoadingHistory
                    ? const Center(child: CircularProgressIndicator())
                    : _historyError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _historyError!,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : timeline.isEmpty && fallbackInquiryProduct == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'No previous messages were returned from `api/v1/messages/` for this conversation.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            timeline.length + (fallbackInquiryProduct != null ? 1 : 0),
                        itemBuilder: (BuildContext context, int index) {
                          if (fallbackInquiryProduct != null && index == 0) {
                            return Align(
                              alignment: fallbackInquiryIsMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(top: 12, bottom: 2),
                                child: Column(
                                  crossAxisAlignment: fallbackInquiryIsMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        fallbackInquiryIsMine ? 'You' : widget.sellerName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    _InquiryMessageEmbed(
                                      product: fallbackInquiryProduct,
                                      isMine: fallbackInquiryIsMine,
                                      showResponseActions:
                                          !fallbackInquiryIsMine &&
                                          fallbackInquiryBuyerAccountId != null &&
                                          fallbackInquiryBuyerAccountId > 0,
                                      onAccept: () => _acceptResolvedInquiryOffer(
                                        product: fallbackInquiryProduct,
                                        buyerAccountId: fallbackInquiryBuyerAccountId,
                                        inquiryId: _resolvedInquiry?.inquiryId,
                                      ),
                                      onReject: () => _rejectInquiryOffer(
                                        fallbackInquiryProduct,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final int timelineIndex =
                              index - (fallbackInquiryProduct != null ? 1 : 0);
                          final _TimelineMessage message = timeline[timelineIndex];
                          final _TimelineMessage? previous = timelineIndex > 0
                              ? timeline[timelineIndex - 1]
                              : null;
                          final bool startsNewGroup =
                              previous == null || previous.isMine != message.isMine;
                          return Align(
                            alignment: message.isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: EdgeInsets.only(
                                top: startsNewGroup ? 12 : 2,
                                bottom: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: message.isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (startsNewGroup)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            message.senderName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                   color: colorScheme.onSurfaceVariant,
                                                ),
                                          ),
                                          if (!message.isMine &&
                                              widget.isStaffParticipant) ...[
                                            const SizedBox(width: 6),
                                            const _InlineStaffBadge(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  if (message.acceptedOfferProduct != null)
                                    _OfferAcceptedEmbed(
                                      product: message.acceptedOfferProduct!,
                                      isMine: message.isMine,
                                    )
                                  else if (message.rejectedOfferProduct != null)
                                    _OfferRejectedEmbed(
                                      product: message.rejectedOfferProduct!,
                                      isMine: message.isMine,
                                    )
                                  else if (message.inquiryProduct != null)
                                    _InquiryMessageEmbed(
                                      product: message.inquiryProduct!,
                                      isMine: message.isMine,
                                      showResponseActions:
                                          !message.isMine &&
                                          currentInquiry?.messageId ==
                                              message.messageId,
                                      onAccept: () => _acceptInquiryOffer(message),
                                      onReject: () => _rejectInquiryOffer(
                                        message.inquiryProduct!,
                                      ),
                                    )
                                  else if (message.qrConfirmation != null)
                                    _QrConfirmationStartedEmbed(
                                      qrConfirmation: message.qrConfirmation!,
                                      isMine: message.isMine,
                                      onTap: () =>
                                          _showQrConfirmationDialog(
                                            message.qrConfirmation!,
                                            isMine: message.isMine,
                                          ),
                                    )
                                  else if (message.completedQrConfirmation != null)
                                    _TransactionCompletedEmbed(
                                      product:
                                          message.completedQrConfirmation!.product,
                                      isMine: message.isMine,
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: message.isMine
                                            ? Theme.of(context).colorScheme.primary
                                            : colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        message.text,
                                        style: TextStyle(
                                          color: message.isMine
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatMessageMeta(message.sentAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                       color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: typingState?.isTyping == true
                          ? Padding(
                              key: const ValueKey('typing-indicator'),
                              padding: const EdgeInsets.only(
                                left: 4,
                                right: 4,
                                bottom: 8,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _TypingDots(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${typingState!.username} is typing...',
                                      style: TextStyle(
                                         color: colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                           : const SizedBox.shrink(
                               key: ValueKey('typing-indicator-empty'),
                             ),
                    ),
                    if (currentInquiry != null && !currentInquiry.isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PinnedCurrentInquiry(
                          product: currentInquiry.inquiryProduct!,
                          showResponseActions: true,
                          onAccept: () => _acceptInquiryOffer(currentInquiry),
                          onReject: () => _rejectInquiryOffer(
                            currentInquiry.inquiryProduct!,
                          ),
                        ),
                      )
                    else if (fallbackInquiryProduct != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PinnedCurrentInquiry(
                          product: fallbackInquiryProduct,
                          showResponseActions:
                              !fallbackInquiryIsMine &&
                              fallbackInquiryBuyerAccountId != null &&
                              fallbackInquiryBuyerAccountId > 0,
                          onAccept: () => _acceptResolvedInquiryOffer(
                            product: fallbackInquiryProduct,
                            buyerAccountId: fallbackInquiryBuyerAccountId,
                            inquiryId: _resolvedInquiry?.inquiryId,
                          ),
                          onReject: () => _rejectInquiryOffer(
                            fallbackInquiryProduct,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              hintText: 'Type a message',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatMessageMeta(DateTime sentAt) {
    final DateTime local = sentAt.toLocal();
    final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _serializeInquiryMessage(InquiryProductData product) {
    return '$_inquiryMessagePrefix${jsonEncode(product.toJson())}';
  }

  String _serializeAcceptedOfferMessage(InquiryProductData product) {
    return '$_offerAcceptedMessagePrefix${jsonEncode(product.toJson())}';
  }

  String _serializeRejectedOfferMessage(InquiryProductData product) {
    return '$_offerRejectedMessagePrefix${jsonEncode(product.toJson())}';
  }

  String _serializeQrConfirmationStartedMessage(QrConfirmationData qrConfirmation) {
    return '$_qrConfirmationStartedMessagePrefix${jsonEncode(qrConfirmation.toJson())}';
  }

  String _serializeTransactionCompletedMessage(QrConfirmationData qrConfirmation) {
    return '$_transactionCompletedMessagePrefix${jsonEncode(qrConfirmation.toJson())}';
  }

  static InquiryProductData? _parseInquiryMessage(String messageText) {
    final String trimmed = messageText.trim();
    if (!trimmed.startsWith(_inquiryMessagePrefix)) {
      return null;
    }
    final String rawJson = trimmed.substring(_inquiryMessagePrefix.length);
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return InquiryProductData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static InquiryProductData? _parseAcceptedOfferMessage(String messageText) {
    final String trimmed = messageText.trim();
    if (!trimmed.startsWith(_offerAcceptedMessagePrefix)) {
      return null;
    }
    final String rawJson = trimmed.substring(_offerAcceptedMessagePrefix.length);
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return InquiryProductData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static InquiryProductData? _parseRejectedOfferMessage(String messageText) {
    final String trimmed = messageText.trim();
    if (!trimmed.startsWith(_offerRejectedMessagePrefix)) {
      return null;
    }
    final String rawJson = trimmed.substring(_offerRejectedMessagePrefix.length);
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return InquiryProductData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  static QrConfirmationData? _parseQrConfirmationStartedMessage(String messageText) {
    final String trimmed = messageText.trim();
    if (!trimmed.startsWith(_qrConfirmationStartedMessagePrefix)) {
      return null;
    }
    final String rawJson = trimmed.substring(
      _qrConfirmationStartedMessagePrefix.length,
    );
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return QrConfirmationData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  int? _extractConversationId(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final int? directId =
          (decoded['conversation_id'] as num?)?.toInt() ??
          (decoded['id'] as num?)?.toInt();
      if (directId != null && directId > 0) {
        return directId;
      }

      for (final String key in <String>[
        'conversation',
        'data',
        'item',
        'inquiry',
        'message',
      ]) {
        final int? nestedId = _extractConversationId(decoded[key]);
        if (nestedId != null && nestedId > 0) {
          return nestedId;
        }
      }
      return null;
    }

    if (decoded is List) {
      for (final dynamic item in decoded) {
        final int? nestedId = _extractConversationId(item);
        if (nestedId != null && nestedId > 0) {
          return nestedId;
        }
      }
    }

    return null;
  }

  _ResolvedInquiryPreview? _extractInquiryForConversation(
    dynamic decoded, {
    required int conversationId,
  }) {
    if (decoded is List) {
      for (final dynamic item in decoded) {
        final _ResolvedInquiryPreview? inquiry = _extractInquiryForConversation(
          item,
          conversationId: conversationId,
        );
        if (inquiry != null) {
          return inquiry;
        }
      }
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final int? itemConversationId =
        (decoded['conversation_id'] as num?)?.toInt() ??
        (decoded['conversation'] is Map<String, dynamic>
            ? ((decoded['conversation'] as Map<String, dynamic>)['conversation_id']
                        as num?)
                    ?.toInt() ??
                ((decoded['conversation'] as Map<String, dynamic>)['id'] as num?)
                    ?.toInt()
            : null);
    if (itemConversationId != null && itemConversationId == conversationId) {
      final InquiryProductData? product = _inquiryProductFromObject(decoded);
      if (product == null) {
        return null;
      }
      final int? buyerAccountId = _extractInquiryBuyerAccountId(decoded);
      return _ResolvedInquiryPreview(
        inquiryId: (decoded['inquiry_id'] as num?)?.toInt() ?? 0,
        product: product,
        buyerAccountId: buyerAccountId,
        isMine: buyerAccountId != null && buyerAccountId == ApiAuthSession.accountId,
        status: (decoded['status'] ?? 'pending').toString().trim().toLowerCase(),
      );
    }

    for (final dynamic value in decoded.values) {
      final _ResolvedInquiryPreview? inquiry = _extractInquiryForConversation(
        value,
        conversationId: conversationId,
      );
      if (inquiry != null) {
        return inquiry;
      }
    }

    return null;
  }

  int? _extractInquiryBuyerAccountId(Map<String, dynamic> json) {
    return (json['inquirer_id'] as num?)?.toInt() ??
        (json['buyer_id'] as num?)?.toInt() ??
        (json['account_id'] as num?)?.toInt() ??
        (json['requester_id'] as num?)?.toInt() ??
        (json['user_id'] as num?)?.toInt() ??
        (json['sender_id'] as num?)?.toInt();
  }

  InquiryProductData _enrichInquiryProduct(InquiryProductData product) {
    for (final InquiryProductData candidate in widget.effectiveInquiryProducts) {
      if (candidate.listingId != product.listingId) {
        continue;
      }
      return InquiryProductData(
        listingId: product.listingId,
        name: product.name.trim().isNotEmpty && product.name != 'Listing'
            ? product.name
            : candidate.name,
        price: product.price.trim().isNotEmpty ? product.price : candidate.price,
        location: product.location.trim().isNotEmpty
            ? product.location
            : candidate.location,
        imageUrl: product.imageUrl.trim().isNotEmpty
            ? product.imageUrl
            : candidate.imageUrl,
      );
    }
    return product;
  }

  InquiryProductData? _inquiryProductFromObject(Map<String, dynamic> json) {
    final dynamic listing = json['listing'] ?? json['item'] ?? json['product'];
    final Map<String, dynamic> productJson = listing is Map<String, dynamic>
        ? Map<String, dynamic>.from(listing)
        : json;

    final int listingId =
        (productJson['listing_id'] as num?)?.toInt() ??
        (productJson['item_id'] as num?)?.toInt() ??
        (productJson['id'] as num?)?.toInt() ??
        0;
    if (listingId <= 0) {
      return null;
    }

    final String name =
        (productJson['name'] ??
                productJson['title'] ??
                productJson['listing_name'] ??
                productJson['product_name'] ??
                '')
            .toString()
            .trim();
    final String price =
        (productJson['price'] ??
                productJson['formatted_price'] ??
                productJson['price_text'] ??
                '')
            .toString()
            .trim();
    final String location =
        (productJson['location'] ??
                productJson['campus'] ??
                productJson['pickup_location'] ??
                '')
            .toString()
            .trim();
    final String imageUrl =
        normalizeApiAssetUrl(
          (productJson['image_url'] ??
                  productJson['primary_media_url'] ??
                  productJson['file_url'] ??
                  productJson['thumbnail_url'] ??
                  productJson['photo_url'] ??
                  '')
              .toString(),
        ) ??
        '';

    return InquiryProductData(
      listingId: listingId,
      name: name.isEmpty ? 'Listing' : name,
      price: price,
      location: location,
      imageUrl: imageUrl,
    );
  }

  Future<QrConfirmationData> _startQrConfirmation({
    required InquiryProductData product,
    required int buyerAccountId,
    required int sellerAccountId,
  }) async {
    final int transactionId = await _createTransactionForInquiry(
      product: product,
        buyerAccountId: buyerAccountId,
        sellerAccountId: sellerAccountId,
      );
    return _generateTransactionQr(
      transactionId: transactionId,
      product: product,
      accountId: sellerAccountId,
    );
  }

  int? _resolveInquiryIdForProduct(InquiryProductData? product) {
    if (product == null) {
      return null;
    }
    final _ResolvedInquiryPreview? resolvedInquiry = _resolvedInquiry;
    if (resolvedInquiry == null) {
      return null;
    }
    if (resolvedInquiry.product.listingId != product.listingId) {
      return null;
    }
    return resolvedInquiry.inquiryId > 0 ? resolvedInquiry.inquiryId : null;
  }

  Future<void> _acceptListingInquiry({
    required int listingId,
    required int inquiryId,
    required int accountId,
  }) async {
    final http.Response response = await http
        .post(
          ApiRoutes.acceptListingInquiry(listingId, inquiryId),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(<String, dynamic>{'account_id': accountId}),
        )
        .timeout(kApiRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }
  }

  static QrConfirmationData? _parseTransactionCompletedMessage(String messageText) {
    final String trimmed = messageText.trim();
    if (!trimmed.startsWith(_transactionCompletedMessagePrefix)) {
      return null;
    }
    final String rawJson = trimmed.substring(
      _transactionCompletedMessagePrefix.length,
    );
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return QrConfirmationData.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _rejectListingInquiry({
    required int listingId,
    required int inquiryId,
    required int accountId,
  }) async {
    final http.Response response = await http
        .post(
          ApiRoutes.rejectListingInquiry(listingId, inquiryId),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(<String, dynamic>{'account_id': accountId}),
        )
        .timeout(kApiRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }
  }

  Future<int> _createTransactionForInquiry({
    required InquiryProductData product,
    required int buyerAccountId,
    required int sellerAccountId,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'listing_id': product.listingId,
      'buyer_id': buyerAccountId,
      'seller_id': sellerAccountId,
      'quantity': 1,
      'agreed_price': _parsePriceValue(product.price),
      'transaction_status': 'pending',
    };

    final List<Uri> candidateUris = <Uri>[
      ApiRoutes.transactions(),
      ApiRoutes.transactionsNoSlash(),
    ];

    HttpException? lastError;
    for (final Uri uri in candidateUris) {
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
            body: jsonEncode(payload),
          )
          .timeout(kApiRequestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _parseCreatedItemId(
          response.body,
          const <String>['transaction_id', 'id'],
          fallbackError: 'Transaction response was invalid.',
        );
      }
      lastError = HttpException(_extractErrorMessage(response));
      if (response.statusCode != 404) {
        throw lastError;
      }
    }
    throw lastError ?? const HttpException('Transaction request failed.');
  }

  Future<QrConfirmationData> _generateTransactionQr({
    required int transactionId,
    required InquiryProductData product,
    required int accountId,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'transaction_id': transactionId,
      'account_id': accountId,
    };
    final http.Response response = await http
        .post(
          ApiRoutes.transactionQrGenerate(),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(payload),
        )
        .timeout(kApiRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }
    final dynamic decoded = jsonDecode(response.body);
    return _parseGeneratedQrConfirmation(
      decoded,
      transactionId: transactionId,
      product: product,
    );
  }

  QrConfirmationData _parseGeneratedQrConfirmation(
    dynamic decoded, {
    required int transactionId,
    required InquiryProductData product,
  }) {
    if (decoded is Map<String, dynamic>) {
      final int? transactionQrId = _findIntDeep(
        decoded,
        const <String>['transaction_qr_id', 'id'],
      );
      final String? qrToken = _findStringDeep(
        decoded,
        const <String>['qr_token', 'token'],
      );
      final DateTime? expiresAt = _findDateTimeDeep(
        decoded,
        const <String>['expires_at'],
      );
      if (transactionQrId != null &&
          transactionQrId > 0 &&
          qrToken != null &&
          qrToken.isNotEmpty) {
        return QrConfirmationData(
          transactionId: transactionId,
          transactionQrId: transactionQrId,
          qrToken: qrToken,
          expiresAt: expiresAt,
          product: product,
        );
      }
    }
    throw const FormatException('Transaction QR response was invalid.');
  }

  int _parseCreatedItemId(
    String responseBody,
    List<String> candidateKeys, {
    required String fallbackError,
  }) {
    final dynamic decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) {
      for (final String key in candidateKeys) {
        final int? value = (decoded[key] as num?)?.toInt();
        if (value != null && value > 0) {
          return value;
        }
      }
    }
    throw FormatException(fallbackError);
  }

  int? _findIntDeep(dynamic decoded, List<String> keys) {
    if (decoded is Map<String, dynamic>) {
      for (final String key in keys) {
        final int? value = (decoded[key] as num?)?.toInt();
        if (value != null && value > 0) {
          return value;
        }
      }
      for (final dynamic value in decoded.values) {
        final int? nested = _findIntDeep(value, keys);
        if (nested != null && nested > 0) {
          return nested;
        }
      }
    } else if (decoded is List) {
      for (final dynamic value in decoded) {
        final int? nested = _findIntDeep(value, keys);
        if (nested != null && nested > 0) {
          return nested;
        }
      }
    }
    return null;
  }

  String? _findStringDeep(dynamic decoded, List<String> keys) {
    if (decoded is Map<String, dynamic>) {
      for (final String key in keys) {
        final String value = (decoded[key] ?? '').toString().trim();
        if (value.isNotEmpty) {
          return value;
        }
      }
      for (final dynamic value in decoded.values) {
        final String? nested = _findStringDeep(value, keys);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    } else if (decoded is List) {
      for (final dynamic value in decoded) {
        final String? nested = _findStringDeep(value, keys);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return null;
  }

  DateTime? _findDateTimeDeep(dynamic decoded, List<String> keys) {
    if (decoded is Map<String, dynamic>) {
      for (final String key in keys) {
        final DateTime? value =
            DateTime.tryParse((decoded[key] ?? '').toString())?.toLocal();
        if (value != null) {
          return value;
        }
      }
      for (final dynamic value in decoded.values) {
        final DateTime? nested = _findDateTimeDeep(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    } else if (decoded is List) {
      for (final dynamic value in decoded) {
        final DateTime? nested = _findDateTimeDeep(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  double _parsePriceValue(String rawPrice) {
    final String normalized = rawPrice.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(normalized) ?? 0;
  }

  void _showQrConfirmationDialog(
    QrConfirmationData qrConfirmation, {
    required bool isMine,
  }) {
    _hasHandledScan = false;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMine ? 'QR confirmation started' : 'Scan seller QR',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (isMine)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: qrConfirmation.qrToken,
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: MobileScanner(
                          controller: _qrScannerController,
                          onDetect: (BarcodeCapture capture) {
                            if (_hasHandledScan || capture.barcodes.isEmpty) {
                              return;
                            }
                            final String rawValue =
                                capture.barcodes.first.rawValue?.trim() ?? '';
                            if (rawValue.isEmpty) {
                              return;
                            }
                            _hasHandledScan = true;
                            unawaited(
                              _confirmScannedQr(
                                scannedToken: rawValue,
                                expectedQr: qrConfirmation,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(qrConfirmation.product.name),
                  const SizedBox(height: 8),
                  Text(
                    isMine
                        ? 'Token: ${qrConfirmation.qrToken}'
                        : 'Scan the seller QR to confirm this transaction.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: isMine ? 'monospace' : null,
                          fontWeight: isMine ? FontWeight.w700 : FontWeight.w400,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    qrConfirmation.expiresAt == null
                        ? 'Does not expire automatically'
                        : 'Expires ${_formatQrExpiry(qrConfirmation.expiresAt!)}',
                  ),
                  if (!isMine && _isConfirmingQr) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _hasHandledScan = false;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatQrExpiry(DateTime expiresAt) {
    final DateTime local = expiresAt.toLocal();
    final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _confirmScannedQr({
    required String scannedToken,
    required QrConfirmationData expectedQr,
  }) async {
    if (_isConfirmingQr) {
      return;
    }
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null || accountId <= 0) {
      _hasHandledScan = false;
      return;
    }

    setState(() {
      _isConfirmingQr = true;
    });

    try {
      final http.Response response = await http
          .post(
            ApiRoutes.transactionQrConfirm(),
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
            body: jsonEncode(<String, dynamic>{
              'qr_token': scannedToken,
              'account_id': accountId,
            }),
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _consumedQrTokens.add(expectedQr.qrToken);
      });
      final int? conversationId = _activeConversationId;
      if (conversationId != null) {
        await _realtime.sendMessage(
          conversationId: conversationId,
          messageText: _serializeTransactionCompletedMessage(expectedQr),
        );
      }
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scannedToken == expectedQr.qrToken
                ? 'QR confirmed successfully.'
                : 'QR confirmed.',
          ),
        ),
      );
    } on TimeoutException {
      _hasHandledScan = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR confirmation timed out.')),
      );
    } on SocketException {
      _hasHandledScan = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to confirm the QR.')),
      );
    } on HttpException catch (error) {
      _hasHandledScan = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isConfirmingQr = false;
        });
      }
    }
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int index) {
            final double phase = (_controller.value - (index * 0.18)) % 1;
            final double opacity = 0.35 + ((1 - phase).clamp(0.0, 1.0) * 0.65);
            final double scale = 0.7 + ((1 - phase).clamp(0.0, 1.0) * 0.3);
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _InlineStaffBadge extends StatelessWidget {
  const _InlineStaffBadge();

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.32)),
      ),
      child: Text(
        'Staff',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class InquiryProductData {
  const InquiryProductData({
    required this.listingId,
    required this.name,
    required this.price,
    required this.location,
    required this.imageUrl,
  });

  final int listingId;
  final String name;
  final String price;
  final String location;
  final String imageUrl;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'listing_id': listingId,
      'name': name,
      'price': price,
      'location': location,
      'image_url': imageUrl,
    };
  }

  factory InquiryProductData.fromJson(Map<String, dynamic> json) {
    return InquiryProductData(
      listingId: (json['listing_id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? 'Listing').toString(),
      price: (json['price'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      imageUrl: normalizeApiAssetUrl((json['image_url'] ?? '').toString()) ?? '',
    );
  }
}

class _ResolvedInquiryPreview {
  const _ResolvedInquiryPreview({
    required this.inquiryId,
    required this.product,
    required this.buyerAccountId,
    required this.isMine,
    required this.status,
  });

  final int inquiryId;
  final InquiryProductData product;
  final int? buyerAccountId;
  final bool isMine;
  final String status;
}

class QrConfirmationData {
  const QrConfirmationData({
    required this.transactionId,
    required this.transactionQrId,
    required this.qrToken,
    required this.expiresAt,
    required this.product,
  });

  final int transactionId;
  final int transactionQrId;
  final String qrToken;
  final DateTime? expiresAt;
  final InquiryProductData product;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'transaction_id': transactionId,
      'transaction_qr_id': transactionQrId,
      'qr_token': qrToken,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'product': product.toJson(),
    };
  }

  factory QrConfirmationData.fromJson(Map<String, dynamic> json) {
    final dynamic productJson = json['product'];
    return QrConfirmationData(
      transactionId: (json['transaction_id'] as num?)?.toInt() ?? 0,
      transactionQrId: (json['transaction_qr_id'] as num?)?.toInt() ?? 0,
      qrToken: (json['qr_token'] ?? '').toString(),
      expiresAt:
          DateTime.tryParse((json['expires_at'] ?? '').toString())?.toLocal(),
      product: productJson is Map<String, dynamic>
          ? InquiryProductData.fromJson(productJson)
          : const InquiryProductData(
              listingId: 0,
              name: 'Listing',
              price: '',
              location: '',
              imageUrl: '',
            ),
    );
  }
}

class _InquiryMessageEmbed extends StatelessWidget {
  const _InquiryMessageEmbed({
    required this.product,
    required this.isMine,
    this.showResponseActions = false,
    this.onAccept,
    this.onReject,
  });

  final InquiryProductData product;
  final bool isMine;
  final bool showResponseActions;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isMine
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine ? colorScheme.primary.withValues(alpha: 0.25) : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 148,
            width: double.infinity,
            child: product.imageUrl.trim().isNotEmpty
                ? Image.network(product.imageUrl, fit: BoxFit.cover)
                : Container(
                    color: colorScheme.surfaceContainer,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inquiry',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  product.price,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isMine
                            ? colorScheme.primary
                            : colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (showResponseActions) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onAccept,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Accept'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onReject,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferAcceptedEmbed extends StatelessWidget {
  const _OfferAcceptedEmbed({
    required this.product,
    required this.isMine,
  });

  final InquiryProductData product;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMine
            ? colorScheme.tertiaryContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Offer accepted',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            product.price,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _OfferRejectedEmbed extends StatelessWidget {
  const _OfferRejectedEmbed({
    required this.product,
    required this.isMine,
  });

  final InquiryProductData product;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel_outlined,
                size: 18,
                color: colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Offer rejected',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            product.price,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _QrConfirmationStartedEmbed extends StatelessWidget {
  const _QrConfirmationStartedEmbed({
    required this.qrConfirmation,
    required this.isMine,
    required this.onTap,
  });

  final QrConfirmationData qrConfirmation;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget qrPreview = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: QrImageView(
        data: qrConfirmation.qrToken,
        version: QrVersions.auto,
        size: 148,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isMine
                  ? colorScheme.primaryContainer
                  : colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_2,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'QR confirmation started',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  qrConfirmation.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  qrConfirmation.product.price,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (isMine) ...[
                  const SizedBox(height: 12),
                  Center(child: qrPreview),
                ],
                const SizedBox(height: 8),
                Text(
                  isMine
                      ? 'Show this QR to the buyer or tap to enlarge'
                      : 'Tap to scan the seller QR',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionCompletedEmbed extends StatelessWidget {
  const _TransactionCompletedEmbed({
    required this.product,
    required this.isMine,
  });

  final InquiryProductData product;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMine
              ? colorScheme.primaryContainer
              : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Transaction completed for ${product.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedCurrentInquiry extends StatelessWidget {
  const _PinnedCurrentInquiry({
    required this.product,
    required this.showResponseActions,
    this.onAccept,
    this.onReject,
  });

  final InquiryProductData product;
  final bool showResponseActions;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52,
              height: 52,
              child: product.imageUrl.trim().isNotEmpty
                  ? Image.network(product.imageUrl, fit: BoxFit.cover)
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current inquiry',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.price,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (showResponseActions) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: onAccept,
                        child: const Text('Accept'),
                      ),
                      OutlinedButton(
                        onPressed: onReject,
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiMessage {
  const _ApiMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.messageText,
    required this.sentAt,
    required this.sourceOrder,
  });

  final int messageId;
  final int conversationId;
  final int? senderId;
  final String? senderUsername;
  final String messageText;
  final DateTime sentAt;
  final int sourceOrder;

  factory _ApiMessage.fromJson(Map<String, dynamic> json, {required int sourceOrder}) {
    final DateTime parsedSentAt =
        DateTime.tryParse((json['sent_at'] ?? '').toString())?.toLocal() ??
        DateTime.now();
    return _ApiMessage(
      messageId: (json['message_id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt(),
      senderUsername: (json['sender_username'] ?? '').toString().trim(),
      messageText: (json['message_text'] ?? '').toString(),
      sentAt: parsedSentAt,
      sourceOrder: sourceOrder,
    );
  }
}

class _TimelineMessage {
  const _TimelineMessage({
    required this.messageId,
    required this.text,
    required this.inquiryProduct,
    required this.acceptedOfferProduct,
    required this.rejectedOfferProduct,
    required this.qrConfirmation,
    required this.completedQrConfirmation,
    required this.isMine,
    required this.isRealtime,
    required this.senderName,
    required this.senderAccountId,
    required this.sentAt,
    required this.sortOrder,
  });

  final int messageId;
  final String text;
  final InquiryProductData? inquiryProduct;
  final InquiryProductData? acceptedOfferProduct;
  final InquiryProductData? rejectedOfferProduct;
  final QrConfirmationData? qrConfirmation;
  final QrConfirmationData? completedQrConfirmation;
  final bool isMine;
  final bool isRealtime;
  final String senderName;
  final int? senderAccountId;
  final DateTime sentAt;
  final int sortOrder;

  _TimelineMessage copyWith({
    String? text,
    InquiryProductData? inquiryProduct,
    InquiryProductData? acceptedOfferProduct,
    InquiryProductData? rejectedOfferProduct,
    QrConfirmationData? qrConfirmation,
    QrConfirmationData? completedQrConfirmation,
  }) {
    return _TimelineMessage(
      messageId: messageId,
      text: text ?? this.text,
      inquiryProduct: inquiryProduct ?? this.inquiryProduct,
      acceptedOfferProduct: acceptedOfferProduct ?? this.acceptedOfferProduct,
      rejectedOfferProduct: rejectedOfferProduct ?? this.rejectedOfferProduct,
      qrConfirmation: qrConfirmation,
      completedQrConfirmation:
          completedQrConfirmation ?? this.completedQrConfirmation,
      isMine: isMine,
      isRealtime: isRealtime,
      senderName: senderName,
      senderAccountId: senderAccountId,
      sentAt: sentAt,
      sortOrder: sortOrder,
    );
  }

  factory _TimelineMessage.api(
    _ApiMessage message, {
    required String otherParticipantName,
  }) {
    final bool isMine =
        message.senderId != null && message.senderId == ApiAuthSession.accountId;
    final InquiryProductData? inquiryProduct =
        _ChatThreadPageState._parseInquiryMessage(message.messageText);
    final InquiryProductData? acceptedOfferProduct =
        _ChatThreadPageState._parseAcceptedOfferMessage(message.messageText);
    final InquiryProductData? rejectedOfferProduct =
        _ChatThreadPageState._parseRejectedOfferMessage(message.messageText);
    final QrConfirmationData? qrConfirmation =
        _ChatThreadPageState._parseQrConfirmationStartedMessage(
          message.messageText,
        );
    final QrConfirmationData? completedQrConfirmation =
        _ChatThreadPageState._parseTransactionCompletedMessage(
          message.messageText,
        );
    return _TimelineMessage(
      messageId: message.messageId,
      text: inquiryProduct == null &&
              acceptedOfferProduct == null &&
              rejectedOfferProduct == null &&
              qrConfirmation == null &&
              completedQrConfirmation == null
          ? message.messageText
          : '',
      inquiryProduct: inquiryProduct,
      acceptedOfferProduct: acceptedOfferProduct,
      rejectedOfferProduct: rejectedOfferProduct,
      qrConfirmation: qrConfirmation,
      completedQrConfirmation: completedQrConfirmation,
      isMine: isMine,
      isRealtime: false,
      senderName: isMine ? 'You' : otherParticipantName,
      senderAccountId: message.senderId,
      sentAt: message.sentAt,
      sortOrder: message.sourceOrder,
    );
  }

  factory _TimelineMessage.realtime(UserRealtimeMessage message) {
    final InquiryProductData? inquiryProduct =
        _ChatThreadPageState._parseInquiryMessage(message.messageText);
    final InquiryProductData? acceptedOfferProduct =
        _ChatThreadPageState._parseAcceptedOfferMessage(message.messageText);
    final InquiryProductData? rejectedOfferProduct =
        _ChatThreadPageState._parseRejectedOfferMessage(message.messageText);
    final QrConfirmationData? qrConfirmation =
        _ChatThreadPageState._parseQrConfirmationStartedMessage(
          message.messageText,
        );
    final QrConfirmationData? completedQrConfirmation =
        _ChatThreadPageState._parseTransactionCompletedMessage(
          message.messageText,
        );
    return _TimelineMessage(
      messageId: message.messageId,
      text: inquiryProduct == null &&
              acceptedOfferProduct == null &&
              rejectedOfferProduct == null &&
              qrConfirmation == null &&
              completedQrConfirmation == null
          ? message.messageText
          : '',
      inquiryProduct: inquiryProduct,
      acceptedOfferProduct: acceptedOfferProduct,
      rejectedOfferProduct: rejectedOfferProduct,
      qrConfirmation: qrConfirmation,
      completedQrConfirmation: completedQrConfirmation,
      isMine: message.isMine,
      isRealtime: true,
      senderName: message.senderUsername,
      senderAccountId: message.senderId,
      sentAt: message.sentAt ?? DateTime.now(),
      sortOrder: message.receivedSequence,
    );
  }
}
