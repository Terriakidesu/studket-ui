import 'package:flutter/material.dart';
import 'network_cached_image.dart';
import 'components/studket_app_bar.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  static const List<Map<String, String>> _chats = [
    {
      'seller': 'Ava Thompson',
      'lastMessage': 'Can you pick this up after 6 PM today?',
      'avatarUrl': 'https://i.pravatar.cc/150?img=1',
    },
    {
      'seller': 'Liam Carter',
      'lastMessage': 'Yes, the item is still available.',
      'avatarUrl': 'https://i.pravatar.cc/150?img=2',
    },
    {
      'seller': 'Noah Reyes',
      'lastMessage': 'I can lower the price to \$40 if you want it now.',
      'avatarUrl': 'https://i.pravatar.cc/150?img=3',
    },
    {
      'seller': 'Mia Brooks',
      'lastMessage': 'I just sent more photos in the chat.',
      'avatarUrl': 'https://i.pravatar.cc/150?img=4',
    },
    {
      'seller': 'Emma Gray',
      'lastMessage': 'Thanks! Let me know your preferred meet-up spot.',
      'avatarUrl': 'https://i.pravatar.cc/150?img=5',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StudketAppBar(title: 'Chats'),
      body: ListView.separated(
        itemCount: _chats.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: Colors.grey[200]),
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundImage: NetworkImage(chat['avatarUrl']!),
            ),
            title: Text(
              chat['seller']!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              chat['lastMessage']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatThreadPage(
                    sellerName: chat['seller']!,
                    lastMessage: chat['lastMessage']!,
                    sellerAvatarUrl: chat['avatarUrl']!,
                  ),
                ),
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
  });

  final String sellerName;
  final String lastMessage;
  final String sellerAvatarUrl;
  final InquiryProductData? inquiryProduct;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage>
    with SingleTickerProviderStateMixin {
  static const Duration _groupWindow = Duration(minutes: 2);
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _typingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final List<_ChatMessage> _messages = _buildDummyMessages();
  final TextEditingController _messageController = TextEditingController();
  final Set<int> _expandedMetaIndexes = <int>{};
  bool _isSellerTyping = false;
  bool _showScrollToBottom = false;
  int _replyIndex = 0;
  final List<String> _dummyReplies = const <String>[
    'Sounds good.',
    'Sure, that works for me.',
    'Great, see you then.',
    'Let me know when you are on the way.',
  ];

  List<_ChatMessage> _buildDummyMessages() {
    final DateTime now = DateTime.now();
    final List<_ChatMessage> items = <_ChatMessage>[
      _ChatMessage(
        text: 'Hi, is this still available?',
        isMine: true,
        sentAt: now.subtract(const Duration(minutes: 12)),
      ),
      _ChatMessage(
        text: 'Yes, it is still available.',
        isMine: false,
        sentAt: now.subtract(const Duration(minutes: 11, seconds: 30)),
      ),
      _ChatMessage(
        text: widget.lastMessage,
        isMine: false,
        sentAt: now.subtract(const Duration(minutes: 11)),
      ),
      _ChatMessage(
        text: 'Great, can I check it this afternoon?',
        isMine: true,
        sentAt: now.subtract(const Duration(minutes: 8)),
      ),
      _ChatMessage(
        text: 'Sure. I am free after 4 PM.',
        isMine: false,
        sentAt: now.subtract(const Duration(minutes: 7, seconds: 30)),
      ),
      _ChatMessage(
        text: 'Perfect, I will message you before I leave.',
        isMine: true,
        sentAt: now.subtract(const Duration(minutes: 4)),
      ),
    ];

    if (widget.inquiryProduct != null) {
      items.add(
        _ChatMessage(
          text: '',
          isMine: true,
          sentAt: now.subtract(const Duration(minutes: 1)),
          inquiryProduct: widget.inquiryProduct,
        ),
      );
    }

    return items;
  }

  @override
  void initState() {
    super.initState();
    _typingController.repeat();
    _typingController.stop();
    _scrollController.addListener(_handleScroll);
    _scheduleScrollToBottom(jump: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _typingController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    const double threshold = 120;
    final bool shouldShow =
        _scrollController.offset <
        (_scrollController.position.maxScrollExtent - threshold);
    if (shouldShow == _showScrollToBottom) return;
    setState(() {
      _showScrollToBottom = shouldShow;
    });
  }

  void _sendMessage() {
    final String text = _messageController.text.trim();
    if (text.isEmpty) return;
    final int insertIndex = _messages.length;
    setState(() {
      _messages.add(
        _ChatMessage(text: text, isMine: true, sentAt: DateTime.now()),
      );
      _messageController.clear();
    });
    _listKey.currentState?.insertItem(
      insertIndex,
      duration: const Duration(milliseconds: 260),
    );
    _scheduleScrollToBottom();
    _showTypingAndReply();
  }

  void _showTypingAndReply() {
    if (_isSellerTyping) return;
    setState(() {
      _isSellerTyping = true;
    });
    _typingController.repeat();
    _scheduleScrollToBottom();

    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final int insertIndex = _messages.length;
      final String reply = _dummyReplies[_replyIndex % _dummyReplies.length];
      _replyIndex++;
      setState(() {
        _isSellerTyping = false;
        _messages.add(
          _ChatMessage(text: reply, isMine: false, sentAt: DateTime.now()),
        );
      });
      _typingController
        ..stop()
        ..reset();
      _listKey.currentState?.insertItem(
        insertIndex,
        duration: const Duration(milliseconds: 260),
      );
      _scheduleScrollToBottom();
    });
  }

  void _scheduleScrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(jump: jump);
      Future<void>.delayed(const Duration(milliseconds: 40), () {
        if (!mounted) return;
        _scrollToBottom(jump: jump);
      });
    });
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (jump) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  bool _isGroupedWithPrevious(int index) {
    if (index <= 0) return false;
    final _ChatMessage current = _messages[index];
    final _ChatMessage previous = _messages[index - 1];
    final Duration gap = current.sentAt.difference(previous.sentAt).abs();
    return current.isMine == previous.isMine && gap <= _groupWindow;
  }

  bool _isRecent(DateTime sentAt) {
    return DateTime.now().difference(sentAt) < const Duration(hours: 24);
  }

  String _formatMessageMeta(DateTime sentAt) {
    if (_isRecent(sentAt)) {
      final int hour = sentAt.hour % 12 == 0 ? 12 : sentAt.hour % 12;
      final String minute = sentAt.minute.toString().padLeft(2, '0');
      final String period = sentAt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[sentAt.month - 1]} ${sentAt.day}, ${sentAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(title: widget.sellerName),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedList(
                key: _listKey,
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                initialItemCount: _messages.length,
                itemBuilder: (context, index, animation) {
                  final _ChatMessage message = _messages[index];
                  final bool isMine = message.isMine;
                  final bool groupedWithPrevious = _isGroupedWithPrevious(
                    index,
                  );
                  return SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                    child: FadeTransition(
                      opacity: animation,
                      child: Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: groupedWithPrevious ? 2 : 10,
                            bottom: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isMine && !groupedWithPrevious) ...[
                                CircleAvatar(
                                  radius: 14,
                                  backgroundImage: NetworkImage(
                                    widget.sellerAvatarUrl,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else if (!isMine && groupedWithPrevious) ...[
                                const SizedBox(width: 36),
                              ],
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                    if (_expandedMetaIndexes.contains(index)) {
                                      _expandedMetaIndexes.remove(index);
                                    } else {
                                      _expandedMetaIndexes.add(index);
                                    }
                                  });
                                },
                                    child: Column(
                                      crossAxisAlignment: isMine
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (message.inquiryProduct != null)
                                          _InquiryProductCard(
                                            product: message.inquiryProduct!,
                                            isMine: isMine,
                                          )
                                        else
                                          Container(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.72,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isMine
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              message.text,
                                              style: TextStyle(
                                                color: isMine
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        if (_expandedMetaIndexes.contains(index))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                          top: 4,
                                          left: 4,
                                          right: 4,
                                        ),
                                        child: Text(
                                          _formatMessageMeta(message.sentAt),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.grey[600],
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            AnimatedSlide(
              offset: _showScrollToBottom ? Offset.zero : const Offset(0, 0.4),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _showScrollToBottom ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_showScrollToBottom,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: IconButton.filledTonal(
                      onPressed: () => _scrollToBottom(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ),
              ),
            ),
            if (_isSellerTyping)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(widget.sellerAvatarUrl),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _TypingDots(animation: _typingController),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      onTap: () => _scheduleScrollToBottom(),
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
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isMine,
    required this.sentAt,
    this.inquiryProduct,
  });

  final String text;
  final bool isMine;
  final DateTime sentAt;
  final InquiryProductData? inquiryProduct;
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

class _InquiryProductCard extends StatelessWidget {
  const _InquiryProductCard({required this.product, required this.isMine});

  final InquiryProductData product;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isMine
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
        : Colors.grey.shade300;
    final Color cardColor = isMine
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
        : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: NetworkCachedImage(
              imageUrl: product.imageUrl,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Inquiry about this item',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.location,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatelessWidget {
  const _TypingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final double t = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (index) {
            final double phase = ((t - (index * 0.16)) + 1) % 1;
            final double opacity =
                0.3 + ((phase < 0.5 ? phase : 1 - phase) * 2) * 0.7;
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0).toDouble(),
                child: const CircleAvatar(
                  radius: 3,
                  backgroundColor: Colors.black54,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
