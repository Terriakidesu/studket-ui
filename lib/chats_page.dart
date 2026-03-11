import 'dart:async';

import 'package:flutter/material.dart';

import 'api/user_realtime_service.dart';
import 'components/studket_app_bar.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_realtime.ensureConnected());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StudketAppBar(title: 'Chats'),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          if (_realtime.conversations.isEmpty) {
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
            itemCount: _realtime.conversations.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (BuildContext context, int index) {
              final UserRealtimeConversation conversation =
                  _realtime.conversations[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  child: Text(
                    conversation.title.isEmpty
                        ? '?'
                        : conversation.title[0].toUpperCase(),
                  ),
                ),
                title: Text(
                  conversation.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(conversation.conversationType),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatThreadPage(
                        sellerName: conversation.title,
                        lastMessage: conversation.conversationType,
                        sellerAvatarUrl: '',
                        conversationId: conversation.conversationId,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.sellerName,
    required this.lastMessage,
    required this.sellerAvatarUrl,
    this.inquiryProduct,
    this.conversationId,
  });

  final String sellerName;
  final String lastMessage;
  final String sellerAvatarUrl;
  final InquiryProductData? inquiryProduct;
  final int? conversationId;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_realtime.ensureConnected());
    if (widget.conversationId != null) {
      unawaited(_realtime.subscribeConversation(widget.conversationId!));
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final int? conversationId = widget.conversationId;
    final String text = _messageController.text.trim();
    if (conversationId == null || text.isEmpty) {
      return;
    }

    await _realtime.sendMessage(
      conversationId: conversationId,
      messageText: text,
    );
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final int? conversationId = widget.conversationId;

    return Scaffold(
      appBar: StudketAppBar(title: widget.sellerName),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          if (conversationId == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Starting a brand new conversation is not documented as a public user endpoint yet. Existing websocket conversations are available from the Chats screen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final List<UserRealtimeMessage> messages =
              _realtime.messagesFor(conversationId);

          return Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'Subscribed to the conversation. New websocket messages will appear here.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (BuildContext context, int index) {
                          final UserRealtimeMessage message = messages[index];
                          return Align(
                            alignment: message.isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: message.isMine
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: message.isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.messageText,
                                    style: TextStyle(
                                      color: message.isMine
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message.senderUsername,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: message.isMine
                                          ? Colors.white70
                                          : Colors.black54,
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
                child: Row(
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
              ),
            ],
          );
        },
      ),
    );
  }
}

class InquiryProductData {
  const InquiryProductData({
    required this.name,
    required this.location,
    required this.imageUrl,
  });

  final String name;
  final String location;
  final String imageUrl;
}
